#!/usr/bin/env node
/**
 * AGC 云函数部署工具
 *
 * 由于华为 AGC 没有提供官方 CLI 工具（@agconnect/cli 不存在），
 * 也没有云函数管理的公开 REST API，此脚本自动化「打包」流程，
 * 并提供清晰的部署指引。
 *
 * 用法：
 *   node deploy.js              # 打包所有云函数
 *   node deploy.js pushData     # 只打包指定函数（兼容旧名称：实际匹配 push-data）
 *   node deploy.js --check      # 检查前置条件
 *   node deploy.js --clean      # 清理生成的 zip 文件
 *
 * 流程：
 *   1. 检查前置条件（Node.js 18+、各函数目录完整）
 *   2. 为每个函数复制 shared/ 依赖
 *   3. 安装 npm 依赖
 *   4. 打包为 zip（函数名.zip）
 *   5. 输出部署指引（AGC 控制台操作步骤）
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const zlib = require('zlib');

// ─── 配置 ───────────────────────────────────────────────
const CLOUD_DIR = path.resolve(__dirname);
const SHARED_DIR = path.join(CLOUD_DIR, 'shared');
const OUTPUT_DIR = path.join(CLOUD_DIR, 'dist');

const FUNCTIONS = [
  { name: 'push-data',       runtime: 'nodejs18', memory: 256, timeout: 30, trigger: 'HTTP (POST, AGC Auth)' },
  { name: 'pull-data',       runtime: 'nodejs18', memory: 256, timeout: 30, trigger: 'HTTP (POST, AGC Auth)' },
  { name: 'validate-invite', runtime: 'nodejs18', memory: 256, timeout: 30, trigger: 'HTTP (POST, AGC Auth)' },
  { name: 'merge-conflict',  runtime: 'nodejs18', memory: 256, timeout: 30, trigger: 'HTTP (POST, AGC Auth)' },
  { name: 'notify-family',   runtime: 'nodejs18', memory: 256, timeout: 30, trigger: 'Cloud DB (FamilyMember INSERT/UPDATE/DELETE, kabaoHomeZone)' },
];

// ─── 工具函数 ───────────────────────────────────────────
function log(tag, msg) {
  const colors = { ok: '\x1b[32m', warn: '\x1b[33m', err: '\x1b[31m', info: '\x1b[36m', dim: '\x1b[2m' };
  const reset = '\x1b[0m';
  const c = colors[tag] || '';
  const prefix = tag === 'ok' ? '✓' : tag === 'warn' ? '⚠' : tag === 'err' ? '✗' : tag === 'info' ? 'ℹ' : ' ';
  console.log(`${c}${prefix}${reset} ${msg}`);
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * 递归收集目录下所有文件的相对路径
 */
function collectFiles(dir, base = dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    const relPath = path.relative(base, fullPath);
    if (entry.isDirectory()) {
      // 跳过 node_modules 和 .git
      if (entry.name === 'node_modules' || entry.name === '.git') continue;
      files.push(...collectFiles(fullPath, base));
    } else {
      files.push(relPath);
    }
  }
  return files;
}

/**
 * 简易 zip 打包（不依赖外部工具）
 * 使用 Node.js 内置的 zlib 创建 ZIP 文件
 */
function createZip(sourceDir, outputPath) {
  // ZIP 文件格式常量
  const LOCAL_FILE_HEADER_SIG = 0x04034b50;
  const CENTRAL_DIR_HEADER_SIG = 0x02014b50;
  const END_OF_CENTRAL_DIR_SIG = 0x06054b50;

  const files = collectFiles(sourceDir);
  const localHeaders = [];
  const centralHeaders = [];
  let offset = 0;

  const buffers = [];

  for (const relPath of files) {
    const fullPath = path.join(sourceDir, relPath);
    const content = fs.readFileSync(fullPath);
    // 使用 POSIX 风格路径分隔符（ZIP 规范）
    const nameBytes = Buffer.from(relPath.split(path.sep).join('/'), 'utf8');

    // 压缩内容
    const compressed = zlib.deflateRawSync(content);

    // 计算 CRC32
    const crc = crc32(content);

    const localHeader = Buffer.alloc(30);
    localHeader.writeUInt32LE(LOCAL_FILE_HEADER_SIG, 0);   // 签名
    localHeader.writeUInt16LE(20, 4);                       // 版本需要
    localHeader.writeUInt16LE(0, 6);                        // 通用位标志
    localHeader.writeUInt16LE(8, 8);                        // 压缩方法 (deflate)
    localHeader.writeUInt16LE(0, 10);                       // 修改时间
    localHeader.writeUInt16LE(0, 12);                       // 修改日期
    localHeader.writeUInt32LE(crc, 14);                     // CRC-32
    localHeader.writeUInt32LE(compressed.length, 18);       // 压缩大小
    localHeader.writeUInt32LE(content.length, 22);          // 原始大小
    localHeader.writeUInt16LE(nameBytes.length, 26);        // 文件名长度
    localHeader.writeUInt16LE(0, 28);                       // 额外字段长度

    buffers.push(localHeader);
    buffers.push(nameBytes);
    buffers.push(compressed);

    // 中央目录头
    const centralHeader = Buffer.alloc(46);
    centralHeader.writeUInt32LE(CENTRAL_DIR_HEADER_SIG, 0);
    centralHeader.writeUInt16LE(20, 4);                    // 版本制作
    centralHeader.writeUInt16LE(20, 6);                    // 版本需要
    centralHeader.writeUInt16LE(0, 8);                     // 通用位标志
    centralHeader.writeUInt16LE(8, 10);                    // 压缩方法
    centralHeader.writeUInt16LE(0, 12);                    // 修改时间
    centralHeader.writeUInt16LE(0, 14);                    // 修改日期
    centralHeader.writeUInt32LE(crc, 16);                  // CRC-32
    centralHeader.writeUInt32LE(compressed.length, 20);    // 压缩大小
    centralHeader.writeUInt32LE(content.length, 24);       // 原始大小
    centralHeader.writeUInt16LE(nameBytes.length, 28);     // 文件名长度
    centralHeader.writeUInt16LE(0, 30);                    // 额外字段长度
    centralHeader.writeUInt16LE(0, 32);                    // 文件注释长度
    centralHeader.writeUInt16LE(0, 34);                    // 起始磁盘号
    centralHeader.writeUInt16LE(0, 36);                    // 内部文件属性
    centralHeader.writeUInt32LE(0, 38);                    // 外部文件属性
    centralHeader.writeUInt32LE(offset, 42);               // 本地头偏移

    centralHeaders.push(centralHeader);
    centralHeaders.push(nameBytes);

    offset += localHeader.length + nameBytes.length + compressed.length;
  }

  const centralDirOffset = offset;
  let centralDirSize = 0;
  for (const buf of centralHeaders) {
    buffers.push(buf);
    centralDirSize += buf.length;
  }

  // 结束中央目录记录
  const endRecord = Buffer.alloc(22);
  endRecord.writeUInt32LE(END_OF_CENTRAL_DIR_SIG, 0);
  endRecord.writeUInt16LE(0, 4);                           // 磁盘号
  endRecord.writeUInt16LE(0, 6);                           // 起始磁盘号
  endRecord.writeUInt16LE(files.length, 8);                // 本磁盘记录数
  endRecord.writeUInt16LE(files.length, 10);               // 总记录数
  endRecord.writeUInt32LE(centralDirSize, 12);             // 中央目录大小
  endRecord.writeUInt32LE(centralDirOffset, 16);           // 中央目录偏移
  endRecord.writeUInt16LE(0, 20);                          // 注释长度
  buffers.push(endRecord);

  fs.writeFileSync(outputPath, Buffer.concat(buffers));
  return files.length;
}

/**
 * CRC32 计算
 */
function crc32(buf) {
  let crc = 0xFFFFFFFF;
  const table = crc32.table || (crc32.table = (() => {
    const t = [];
    for (let i = 0; i < 256; i++) {
      let c = i;
      for (let j = 0; j < 8; j++) {
        c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      t[i] = c;
    }
    return t;
  })());
  for (let i = 0; i < buf.length; i++) {
    crc = table[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

// ─── 命令实现 ───────────────────────────────────────────

function checkPrerequisites() {
  log('info', '检查前置条件...\n');

  // Node.js 版本
  const nodeVersion = process.version;
  const major = parseInt(nodeVersion.slice(1).split('.')[0], 10);
  if (major >= 18) {
    log('ok', `Node.js 版本: ${nodeVersion}`);
  } else {
    log('err', `Node.js 版本过低: ${nodeVersion}（需要 >= 18）`);
    process.exit(1);
  }

  // shared/ 目录
  if (fs.existsSync(SHARED_DIR)) {
    const sharedFiles = fs.readdirSync(SHARED_DIR);
    log('ok', `shared/ 目录存在，包含 ${sharedFiles.length} 个文件: ${sharedFiles.join(', ')}`);
  } else {
    log('err', 'shared/ 目录不存在');
    process.exit(1);
  }

  // 各函数目录
  let allOk = true;
  for (const fn of FUNCTIONS) {
    const fnDir = path.join(CLOUD_DIR, fn.name);
    const hasIndex = fs.existsSync(path.join(fnDir, 'index.js'));
    const hasPackage = fs.existsSync(path.join(fnDir, 'package.json'));
    if (hasIndex && hasPackage) {
      log('ok', `${fn.name}/ — index.js ✓  package.json ✓`);
    } else {
      log('err', `${fn.name}/ — 缺少 ${!hasIndex ? 'index.js' : ''} ${!hasPackage ? 'package.json' : ''}`);
      allOk = false;
    }
  }

  console.log('');
  if (allOk) {
    log('ok', '所有前置条件满足，可以执行打包部署');
  } else {
    log('err', '部分前置条件不满足，请修复后重试');
    process.exit(1);
  }
}

function cleanDist() {
  if (fs.existsSync(OUTPUT_DIR)) {
    const files = fs.readdirSync(OUTPUT_DIR).filter(f => f.endsWith('.zip'));
    for (const f of files) {
      fs.unlinkSync(path.join(OUTPUT_DIR, f));
    }
    log('ok', `已清理 ${files.length} 个 zip 文件`);
  } else {
    log('info', 'dist/ 目录不存在，无需清理');
  }
}

function packageFunction(fn) {
  const fnDir = path.join(CLOUD_DIR, fn.name);
  const stagingDir = path.join(OUTPUT_DIR, '_staging', fn.name);
  const zipPath = path.join(OUTPUT_DIR, `${fn.name}.zip`);

  log('info', `打包 ${fn.name}...`);

  // 1. 创建临时暂存目录
  ensureDir(stagingDir);

  // 2. 复制函数代码
  const fnFiles = fs.readdirSync(fnDir);
  for (const f of fnFiles) {
    if (f === 'node_modules') continue;
    const src = path.join(fnDir, f);
    const dst = path.join(stagingDir, f);
    if (fs.statSync(src).isDirectory()) {
      copyDirRecursive(src, dst);
    } else {
      fs.copyFileSync(src, dst);
    }
  }

  // 3. 复制 shared/ 到函数目录内
  const sharedDest = path.join(stagingDir, 'shared');
  if (fs.existsSync(sharedDest)) {
    // 移除旧的
    rmDirRecursive(sharedDest);
  }
  copyDirRecursive(SHARED_DIR, sharedDest);

  // 4. 安装 npm 依赖
  try {
    execSync('npm install --production', {
      cwd: stagingDir,
      stdio: 'pipe',
      timeout: 60000,
    });
    log('ok', `  npm install 完成`);
  } catch (e) {
    log('warn', `  npm install 失败（可能 @hw-agconnect/cloud-server 不在公共 registry）`);
    log('warn', `  继续打包，部署时 AGC 运行时会提供该依赖`);
  }

  // 5. 打包为 zip
  const fileCount = createZip(stagingDir, zipPath);
  const zipSize = fs.statSync(zipPath).size;

  // 6. 清理暂存目录
  rmDirRecursive(stagingDir);
  // 清理空的 _staging 父目录
  const stagingParent = path.join(OUTPUT_DIR, '_staging');
  if (fs.existsSync(stagingParent)) {
    try { fs.rmdirSync(stagingParent); } catch (e) { /* 非空则保留 */ }
  }

  log('ok', `  → ${fn.name}.zip (${fileCount} 文件, ${formatSize(zipSize)})`);
  return { name: fn.name, zipPath, fileCount, zipSize };
}

function copyDirRecursive(src, dst) {
  ensureDir(dst);
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const dstPath = path.join(dst, entry.name);
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, dstPath);
    } else {
      fs.copyFileSync(srcPath, dstPath);
    }
  }
}

function rmDirRecursive(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      rmDirRecursive(fullPath);
    } else {
      fs.unlinkSync(fullPath);
    }
  }
  fs.rmdirSync(dir);
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function printDeployGuide(results, targets) {
  console.log('\n' + '═'.repeat(60));
  console.log('  AGC 控制台部署指引');
  console.log('═'.repeat(60));
  console.log(`
  1. 打开 AGC 控制台:
     https://developer.huawei.com/consumer/cn/service/josp/agc/

  2. 进入项目 → 构建 → 云函数

  3. 对每个函数执行以下步骤:`);

  for (let i = 0; i < targets.length; i++) {
    const fn = targets[i];
    const result = results[i];
    console.log(`
  ┌─ ${fn.name} ─────────────────────────────────
  │  a. 点击「新建函数」（首次）或选择已有函数（更新）
  │  b. 配置：
  │     - 函数名称: ${fn.name}
  │     - 运行时: ${fn.runtime}
  │     - 内存: ${fn.memory} MB
  │     - 超时时间: ${fn.timeout} 秒
  │  c. 上传代码包: ${result ? result.zipPath : 'cloud/dist/' + fn.name + '.zip'}
  │  d. 配置触发器: ${fn.trigger}
  └───────────────────────────────────────────`);
  }

  console.log(`
  4. 部署完成后，验证清单:
     □ 5 个云函数状态为「运行中」
     □ HTTP 触发器已开启 AGC Auth
     □ notify-family 的 Cloud DB 触发器指向 FamilyMember 表
     □ 客户端 AgcConfig.init() 在 EntryAbility.onCreate 中已调用
     □ 端到端走通：登录 → 创建家庭 → 产生数据 → Cloud DB 有记录

  ⚡ 提示: 首次部署建议逐个函数操作，确认每个函数部署成功后再部署下一个。
  `);
  console.log('═'.repeat(60));
}

// ─── 主入口 ─────────────────────────────────────────────

function main() {
  const args = process.argv.slice(2);

  if (args.includes('--check')) {
    checkPrerequisites();
    return;
  }

  if (args.includes('--clean')) {
    cleanDist();
    return;
  }

  // 确定要打包的函数
  const targetNames = args.filter(a => !a.startsWith('--'));
  const targets = targetNames.length > 0
    ? FUNCTIONS.filter(f => targetNames.includes(f.name))
    : FUNCTIONS;

  if (targets.length === 0) {
    log('err', `未找到匹配的函数: ${targetNames.join(', ')}`);
    log('info', `可用函数: ${FUNCTIONS.map(f => f.name).join(', ')}`);
    process.exit(1);
  }

  // 前置检查
  checkPrerequisites();

  console.log('');
  log('info', `开始打包 ${targets.length} 个云函数...\n`);

  // 创建输出目录
  ensureDir(OUTPUT_DIR);

  // 打包
  const results = [];
  for (const fn of targets) {
    try {
      const result = packageFunction(fn);
      results.push(result);
    } catch (e) {
      log('err', `打包 ${fn.name} 失败: ${e.message}`);
      results.push(null);
    }
  }

  // 汇总
  console.log('');
  const succeeded = results.filter(Boolean);
  const failed = results.filter(r => r === null);
  log('ok', `成功: ${succeeded.length}  失败: ${failed.length}`);
  log('info', `输出目录: ${OUTPUT_DIR}`);

  // 部署指引
  if (succeeded.length > 0) {
    printDeployGuide(results, targets);
  }
}

main();
