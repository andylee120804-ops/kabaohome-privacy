# 卡包 (Kabao) - 华为云 AGC 部署指南

本目录包含部署到 **AppGallery Connect (AGC)** 的所有服务端资源：
- 5 个云函数（Cloud Function）
- 1 份云存储安全规则（Cloud Storage Security Rules）

> ⚠️ **命名说明**：AGC 云函数名称必须只包含小写字母、数字和中划线（kebab-case），
> 所以目录名使用 `push-data` 而非 `pushData`。客户端调用时也需使用相同的名称。

---

## 📁 目录结构

```
cloud/
├── shared/                    # 共享工具库（部署时需复制到各函数目录）
│   ├── response.js            # 统一响应封装
│   ├── db.js                  # Cloud DB 访问封装
│   └── auth.js                # 鉴权工具
│
├── push-data/                 # 推送数据（HTTP 触发）
│   ├── index.js
│   └── package.json
│
├── pull-data/                 # 拉取增量数据（HTTP 触发）
│   ├── index.js
│   └── package.json
│
├── validate-invite/           # 验证邀请码（HTTP 触发）
│   ├── index.js
│   └── package.json
│
├── merge-conflict/            # 冲突合并（HTTP 触发）
│   ├── index.js
│   └── package.json
│
├── notify-family/             # 家庭成员变更通知（Cloud DB 触发）
│   ├── index.js
│   └── package.json
│
└── storage-rules.txt          # 云存储安全规则（AGC DSL 格式）
```

---

## 🚀 部署步骤

### 第一步：开通云函数服务

1. 登录 [AGC 控制台](https://developer.huawei.com/consumer/cn/service/josp/agc/)
2. 进入项目 **kabao** → **构建** → **云函数**
3. 点击 **立即开通**（首次使用，约需 1~2 分钟）

### 第二步：部署每个云函数

对每个函数（`push-data`、`pull-data`、`validate-invite`、`merge-conflict`、`notify-family`）执行：

#### 方式 A：控制台手动上传（推荐首次部署）

1. AGC 控制台 → 云函数 → **新建函数**
2. 填写配置：
   - **函数名称**：与目录名一致（如 `push-data`）—— 必须使用小写字母+中划线
   - **运行时**：Node.js 18
   - **内存**：256 MB
   - **超时时间**：30 秒
3. **代码打包**（Windows PowerShell）：
   ```powershell
   cd C:\Users\Andy\kabao\cloud\push-data
   # 把共享库拷贝进来（云函数运行时是隔离的，shared/ 必须随函数一起部署）
   Copy-Item -Recurse -Force ..\shared .\shared
   # 安装依赖
   npm install
   # 打包
   Compress-Archive -Path index.js,package.json,shared,node_modules `
                    -DestinationPath push-data.zip -Force
   ```
   > Linux / macOS 替代：
   > ```bash
   > cd cloud/push-data
   > cp -r ../shared ./shared
   > npm install
   > zip -r push-data.zip index.js package.json shared/ node_modules/
   > ```
4. 在控制台上传 `push-data.zip`，点击 **部署**

#### 方式 B：使用 AGC CLI（推荐 CI/CD）

```bash
npm install -g @agconnect/cli
agc login

agc function deploy --name push-data       --path ./cloud/push-data       --runtime nodejs18
agc function deploy --name pull-data       --path ./cloud/pull-data       --runtime nodejs18
agc function deploy --name validate-invite --path ./cloud/validate-invite --runtime nodejs18
agc function deploy --name merge-conflict  --path ./cloud/merge-conflict  --runtime nodejs18
agc function deploy --name notify-family   --path ./cloud/notify-family   --runtime nodejs18
```

### 第三步：配置触发器

| 函数 | 触发器类型 | 配置 |
|---|---|---|
| `push-data` | HTTP | 方法：POST；身份验证：开启 AGC Auth |
| `pull-data` | HTTP | 方法：POST；身份验证：开启 AGC Auth |
| `validate-invite` | HTTP | 方法：POST；身份验证：开启 AGC Auth |
| `merge-conflict` | HTTP | 方法：POST；身份验证：开启 AGC Auth |
| `notify-family` | **Cloud DB** | 对象类型：`FamilyMember`；事件：`INSERT`、`UPDATE`、`DELETE`；区域：`kabaoHomeZone` |

部署完成后，每个 HTTP 函数会生成一个调用 URL，格式：
```
https://<region>-<projectId>.cloudfunctions.huaweicloud.com/<functionName>
```

> ⚠️ 客户端通过 `cloudFunction.call({name: 'push-data', ...})` 调用时，SDK 会自动通过函数名解析，无需硬编码 URL。

### 第四步：部署云存储规则

1. AGC 控制台 → **构建** → **云存储**
2. 确认存储桶 `kabao-pl135` 已存在（已在 `AgcConfig.ets` 中配置）
3. **安全规则** 标签页 → **编辑**
4. 复制 `cloud/storage-rules.txt` 内容粘贴并 **发布**

> 📝 **说明**：AGC Storage 规则使用类 Firebase 的 `match`/`allow` DSL（**不是 JSON**）。
> 控制台编辑器会做语法校验，发布前可点 **预览** 检查。规则末尾的 `match /{allPaths=**} { allow read, write: if false; }` 是兜底拒绝规则，**必须保留**。

---

## 🔐 权限与安全要点

### 客户端鉴权流程

```
HarmonyOS App
    │
    │ ① 华为账号登录 → 获取 AccessToken
    │
    ▼
@hw-agconnect/auth → 注入 AGC 鉴权
    │
    │ ② cloudFunction.call({name, params})
    │    自动附加 X-AGC-User-Id Header
    │
    ▼
华为云函数（Node.js 18）
    │
    │ ③ 解析 event.context.auth.uid
    │
    ▼
Cloud DB / Cloud Storage
```

### 关键约定

1. **所有写操作必须校验 `familyId` 归属**：`push-data`、`merge-conflict` 都会先查 `FamilyMember` 表确认 uid 属于该家庭。
2. **客户端发送的 `familyId` 会被服务端强制覆盖**：防止跨家庭污染。
3. **保留字段不可被客户端覆盖**：`id`、`createdAt`、`createdBy` 等由服务端控制。
4. **批量操作有上限**：`push-data` 单次最多 500 条，`merge-conflict` 最多 200 条。

---

## 🧪 本地测试

每个函数可在本地用 Node.js 单测：

```bash
cd cloud/push-data
npm install
node -e "
require('./index').handler(
  {
    body: JSON.stringify({
      familyId: 'test_fam_1',
      operations: [{ type: 'Memo', op: 'upsert', data: { id: 'm1', content: 'hi', version: 1 } }]
    }),
    context: { auth: { uid: 'test_uid_1' } }
  },
  {},
  (err, res) => console.log(res)
);
"
```

> ⚠️ 本地测试时 `@hw-agconnect/cloud-server` 会因缺少 AGC 凭证而失败，可临时 mock `shared/db.js` 来调通业务逻辑。

---

## 📞 客户端调用对照

`entry/src/main/ets/service/CloudService.ets` 中调用云函数时，**函数名必须使用 kebab-case**：

| 客户端方法 | 调用的云函数 |
|---|---|
| `pushPendingOperations()` | `push-data` |
| `pullRemoteChanges()` | `pull-data` |
| `joinFamilyByInviteCode()` | `validate-invite` |
| `resolveConflicts()` | `merge-conflict` |
| —（被动接收推送） | `notify-family` |

ArkTS 调用示例：
```typescript
import { cloudFunction } from '@kit.CloudFoundationKit';

const result = await cloudFunction.call({
  name: 'push-data',     // ← 必须 kebab-case，与控制台一致
  params: { familyId, operations }
});
```

---

## ✅ 验收清单

- [ ] AGC 项目已开通云函数服务
- [ ] 5 个云函数全部部署成功，状态为「运行中」
- [ ] 函数名均为 kebab-case（小写字母 + 中划线）
- [ ] HTTP 触发器已开启 AGC Auth 身份验证
- [ ] `notify-family` 的 Cloud DB 触发器指向 `FamilyMember` 表 + `kabaoHomeZone` 区域
- [ ] 云存储 `kabao-pl135` 桶安全规则已发布
- [ ] 客户端 `AgcConfig.init()` 在 `EntryAbility.onCreate` 中已调用
- [ ] 客户端 `CloudService.ets` 中 `cloudFunction.call({name})` 已改为 kebab-case
- [ ] 端到端走通：登录 → 创建家庭 → 在 App 中产生数据 → 查看 Cloud DB 控制台已有记录

---

## 🐞 常见问题

**Q：函数名不符合规范导致创建失败？**
A：AGC 要求函数名仅含小写字母、数字、中划线，2~63 位，首字符为小写字母，末字符为小写字母或数字。本目录命名均已符合该规范。

**Q：部署后调用返回 401 Unauthorized？**
A：检查触发器是否开启了 AGC Auth；客户端是否正确登录华为账号；检查云函数日志中 `event.context.auth` 是否注入成功。

**Q：`@hw-agconnect/cloud-server` 报 "Cannot find module"？**
A：本地开发需要 `npm install`；部署时需要把 `node_modules` 一起打包到 zip 中，或在控制台 **依赖管理** 中声明。

**Q：Cloud DB 触发器没有触发 notify-family？**
A：① 确认 `FamilyMember` 在 AGC 控制台已创建为对象类型；② 触发器选择的 `zone` 必须是 `kabaoHomeZone`；③ 函数日志中可看到触发事件。

**Q：客户端调用 `cloudFunction.call` 报 "function not found"？**
A：① 检查函数名拼写完全一致（kebab-case，区分大小写）；② 部署完成后等待 1~2 分钟生效；③ 确认客户端代码中的 `name` 字段已从 `pushData` 改为 `push-data`。
