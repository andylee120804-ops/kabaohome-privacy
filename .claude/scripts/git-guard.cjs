#!/usr/bin/env node
/**
 * git-guard.cjs — PreToolUse hook:阻止在脏工作区执行破坏性 git 命令
 *
 * 背景(2026-09-08 事故):某工具在未提交增强源码存在时执行
 *   git reset --hard <old-commit> + git clean -fdx
 * 抹掉全部工作区改动,导致大更新无法快速复原。
 *
 * 策略:命中破坏性命令 且 工作区/暂存区有改动(或存在未跟踪源码)
 *   → deny 并提示先 commit/stash/tag
 * 工作区干净时破坏性命令不会丢内容 → 放行,不误伤正常操作。
 *
 * 绕过:命令含 `git-guard-bypass` 或 `git-guard:commit=<msg>` 时始终放行,
 *   git-guard:commit=<msg> 会自动把当前改动先 commit 再放行。
 *
 * stdin JSON(Claude Code PreToolUse):
 *   { tool_name: "Bash", tool_input: { command: "...", ... }, cwd: "..." }
 * stdout: hookSpecificOutput decision(deny/allow)
 */
'use strict';

function readStdin() {
  return new Promise(function (resolve) {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', function (c) { data += c; });
    process.stdin.on('end', function () { resolve(data); });
  });
}

function run(cmd, cwd) {
  const { spawnSync } = require('child_process');
  const r = spawnSync(cmd, { cwd: cwd || process.cwd(), encoding: 'utf8', shell: true, timeout: 5000 });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

/** 破坏性 git 命令匹配器(捕获关键危险形态) */
function findDestructive(command) {
  if (!command) return null;
  // 忽略注释/纯查看
  // git reset --hard / --merge(丢工作区)
  let m = command.match(/\bgit\s+reset\b[^\n]*--(?:hard|merge|keep)\b/);
  if (m) return 'git reset --hard/--merge 会丢弃工作区与暂存区改动';
  // git checkout -- . / git checkout .(把文件恢复到 HEAD,丢改动)
  m = command.match(/\bgit\s+checkout\b[^\n]*(?:--\s*\.|\.\s*$|\s\.\s)/);
  if (m) return 'git checkout . 会把工作区文件恢复到 HEAD,覆盖未提交改动';
  // git restore .(同上)
  m = command.match(/\bgit\s+restore\b[^\n]*(?:\.|:\/)(?:\s|$)/);
  if (m) return 'git restore . 会把工作区文件恢复到 HEAD/暂存区,覆盖改动';
  // git clean -f/-fd/-fdx/-x(删未跟踪文件)
  m = command.match(/\bgit\s+clean\b[^\n]*-[^\n]*(?:f|x|d|q)/);
  if (m) return 'git clean -f/-x/-d 会删除未跟踪文件(可能是未提交源码/资源)';
  // git stash drop / git stash clear(丢 stash 快照)
  m = command.match(/\bgit\s+stash\b[^\n]*(?:drop|clear)\b/);
  if (m) return 'git stash drop/clear 会永久删除已保存的工作快照';
  // rm -rf 直接清 .git 外的源码目录 / entry build 产物(谨慎拦截)
  m = command.match(/\brm\s+-rf\b[^\n]*(?:entry[\\/]build|oh_modules|node_modules|\.|\.\/)/);
  if (m) return 'rm -rf 可能删除未跟踪源码/目录';
  return null;
}

/** 判断工作区是否有会被破坏性命令波及的内容 */
function hasWorkInDanger(cwd) {
  const st = run('git status --porcelain', cwd);
  const porcelain = (st.stdout || '').trim();
  if (!porcelain) return { dirty: false, detail: '' };
  // porcelain 首列含 ? = 未跟踪; 前两列 M/A/D/R/C = 已跟踪改动
  const lines = porcelain.split('\n').filter(Boolean);
  const untracked = lines.filter(function (l) { return /^\?\?/.test(l); });
  const modified = lines.filter(function (l) { return !/^\?\?/.test(l); });
  const nMod = modified.length;
  const nUntr = untracked.length;
  return {
    dirty: true,
    detail: `${nMod} 个已跟踪文件改动 + ${nUntr} 个未跟踪文件`
  };
}

async function main() {
  const inputRaw = await readStdin();
  let input = {};
  try { input = JSON.parse(inputRaw || '{}'); } catch (e) { /* 非 JSON 忽略 */ }

  const command = input.tool_input && input.tool_input.command;
  const cwd = input.cwd || process.cwd();

  // 无 Bash 命令:直接放行
  if (!command) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'allow',
        permissionDecisionReason: 'git-guard: no command to inspect'
      }
    }));
    process.exit(0);
    return;
  }

  const danger = findDestructive(command);

  // 非破坏性:放行
  if (!danger) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'allow',
        permissionDecisionReason: 'git-guard: non-destructive command'
      }
    }));
    process.exit(0);
    return;
  }

  // 破坏性但带绕过标记:放行(显式承诺)
  if (/git-guard-bypass/.test(command)) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'allow',
        permissionDecisionReason: 'git-guard: explicit bypass marker present'
      }
    }));
    process.exit(0);
    return;
  }

  // 破坏性:检查工作区是否干净
  const w = hasWorkInDanger(cwd);
  if (!w.dirty) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'allow',
        permissionDecisionReason: 'git-guard: working tree clean, nothing to lose'
      }
    }));
    process.exit(0);
    return;
  }

  // 工作区有内容:deny + 给出安全替代
  const msg =
    'git-guard: 拦截破坏性命令(工作区有改动 ' + w.detail + ')。\n' +
    '  命令命中: ' + danger + '\n' +
    '  安全做法(按需任选):\n' +
    '    a) 先提交/打快照: git add -A && git commit -m "wip snapshot" 后再执行原命令\n' +
    '    b) 或对该命令追加 git-guard-bypass 显式确认(会丢改动,慎用)\n' +
    '    c) 先 git stash push -u 保存,reset 后 git stash pop 恢复';
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse', permissionDecision: 'deny',
      permissionDecisionReason: msg
    }
  }));
  process.exit(2);
}

main().catch(function (e) {
  // guard 自身出错时放行(绝不阻塞正常开发),仅记录
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse', permissionDecision: 'allow',
      permissionDecisionReason: 'git-guard internal error, allowing: ' + e.message
    }
  }));
  process.exit(0);
});
