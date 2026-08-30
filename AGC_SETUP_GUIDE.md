# 卡宝Home - 华为云 AGC 集成 & 发布指南

## 概览

项目已从 V1 纯本地模式升级为 **本地优先 + 云端同步** 架构：
- **本地数据层**：Preferences（V1）→ 未来可升级 RelationalStore
- **云端同步层**：AGC Cloud DB + Cloud Function + Cloud Storage
- **认证层**：华为账号 → AGC Auth 关联
- **提醒层**：本地 setTimeout → 系统提醒代理 (ReminderRequestManager)

---

## 第一阶段：AGC 控制台配置（必须手动操作）

### 1.1 确认 AGC 项目

你的项目已在 AGC 创建（`agconnect-services.json` 已存在）：
- **项目ID**: `101653523864188857`
- **App ID**: `6917607032903467630`
- **包名**: `com.family.kabaohome`
- **区域**: CN

打开 [AGC 控制台](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) 确认项目状态。

### 1.2 开通认证服务 (Auth Service)

1. AGC 控制台 → **构建** → **认证服务**
2. 点击「立即开通」
3. 「登录方式」标签页 → 启用以下方式：
   - **华为账号**（主要方式）- 点击启用
   - **匿名登录**（备选方式，debug包使用）- 点击启用
4. 保存设置

### 1.3 开通云数据库 (Cloud DB)

1. AGC 控制台 → **构建** → **云数据库**
2. 点击「立即开通」
3. 创建存储区：
   - 存储区名称：`kabaoHomeZone`
   - 选择区域：`中国`（CN）
4. 添加对象类型（Object Types）— 需要为每种数据模型创建：

| 对象类型名 | 主键 | 索引字段 | 说明 |
|-----------|------|---------|------|
| Family | id | creatorId | 家庭 |
| FamilyMember | id | familyId, userId | 家庭成员 |
| PeriodRecord | id | familyId, creatorId | 姨妈周期记录 |
| IntimacyRecord | id | familyId, creatorId | 啪啪记录 |
| Medication | id | familyId, forMemberId | 用药 |
| MedicationLog | id | medicationId, familyId | 服药记录 |
| HealthMetric | id | familyId, forMemberId | 健康指标 |
| KidEvent | id | familyId, forMemberId | 孩子事项 |
| GrowthRecord | id | familyId, forMemberId | 成长记录 |
| Reminder | id | familyId, creatorId | 提醒事项 |
| ShoppingItem | id | familyId | 购物清单 |
| Photo | id | familyId | 照片 |
| Memo | id | familyId, creatorId | 备忘 |
| AccountingRecord | id | familyId, forMemberId | 记账 |
| Budget | id | familyId | 预算 |
| LocationPlace | id | familyId, forMemberId | 常用地点 |

每个对象类型需要定义字段，字段名和类型与 `entry/src/main/ets/model/` 下的模型类保持一致。

5. 配置权限：
   - 所有对象类型设置：**登录用户可读写自己创建的记录**
   - Family 和 FamilyMember：**家庭内成员可读**
   - ShoppingItem：**家庭内成员可读写**

6. 导出对象类型文件：
   - 点击「导出」→ 下载 JSON 格式的对象类型定义
   - 将下载的文件放入项目的 `entry/src/main/ets/cloud/` 目录

7. 生成客户端代码：
   - 在云数据库页面 → 「客户端代码」→ 选择 HarmonyOS (ArkTS)
   - 下载生成的代码
   - 将生成的模型类放入 `entry/src/main/ets/cloud/model/`

### 1.4 开通云函数 (Cloud Function)

1. AGC 控制台 → **构建** → **云函数**
2. 点击「立即开通」
3. 创建以下云函数：

#### 3.1 pushData（推送数据）
- 运行时：Node.js 18
- 触发器：HTTP触发
- 功能：接收客户端推送的数据变更，写入 Cloud DB

#### 3.2 pullData（拉取数据）
- 运行时：Node.js 18
- 触发器：HTTP触发
- 功能：根据 familyId 和时间戳返回增量数据

#### 3.3 validateInvite（验证邀请码）
- 运行时：Node.js 18
- 触发器：HTTP触发
- 功能：验证邀请码有效性，返回家庭信息

#### 3.4 mergeConflict（冲突合并）
- 运行时：Node.js 18
- 触发器：HTTP触发
- 功能：服务端冲突合并，版本号优先 + last-write-wins

#### 3.5 notifyFamily（家庭通知）
- 运行时：Node.js 18
- 触发器：Cloud DB 触发（新增/修改 FamilyMember 时）
- 功能：推送家庭成员变更通知

4. 部署所有云函数

### 1.5 开通云存储 (Cloud Storage)

1. AGC 控制台 → **构建** → **云存储**
2. 确认存储桶 `kabao-pl135` 已存在（已配置）
3. 配置安全规则：
```json
{
  "rules": [
    {
      "path": "/photos/{familyId}/{photoId}",
      "read": "auth != null && isFamilyMember(familyId)",
      "write": "auth != null && isCreator(photoId)"
    },
    {
      "path": "/avatars/{userId}",
      "read": true,
      "write": "auth.uid == userId"
    }
  ]
}
```

### 1.6 下载最新配置

1. AGC 控制台 → **项目设置** → **常规**
2. 下载最新的 `agconnect-services.json`
3. 替换 `entry/src/main/resources/rawfile/agconnect-services.json`

---

## 第二阶段：DevEco Studio 配置

### 2.1 安装依赖

```bash
cd entry
ohpm install
```

这将安装 `oh-package.json5` 中声明的：
- `@hw-agconnect/auth` - 认证服务
- `@hw-agconnect/clouddb` - 云数据库
- `@hw-agconnect/cloudstorage` - 云存储

### 2.2 添加 AGC 模型文件

1. 将 AGC 控制台生成的客户端模型类放入：
```
entry/src/main/ets/cloud/
├── model/          # 生成的对象类型模型类
│   ├── Family.ts
│   ├── FamilyMember.ts
│   ├── PeriodRecord.ts
│   ├── ...
│   └── ObjectTypes.ts  # 对象类型注册
└── CloudDBZone.ts  # 数据库区域配置
```

2. 更新 `AgcConfig.ets` 中的 Cloud DB zone 初始化，导入生成的模型类

### 2.3 配置签名

确保 `build-profile.json5` 中的签名配置使用的是 **发布签名**（非调试签名）：
- 调试签名不具备 AGC 云服务调用权限
- 需要在 [华为开发者联盟](https://developer.huawei.com/) 申请发布证书

### 2.4 配置混淆规则

在 `entry/obfuscation-rules.txt` 中添加：
```
-keep
oh_modules/@hw-agconnect/auth
-keep
oh_modules/@hw-agconnect/clouddb
-keep
oh_modules/@hw-agconnect/cloudstorage
```

---

## 第三阶段：代码集成完善

### 3.1 需要更新的文件清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `entry/oh-package.json5` | ✅ 已升级 | 添加 AGC SDK 依赖 |
| `service/AgcConfig.ets` | ✅ 新建 | AGC 初始化服务 |
| `entryability/EntryAbility.ets` | ✅ 已升级 | 添加 AGC 初始化调用 |
| `service/CloudService.ets` | ✅ 已升级 | 对接 CloudFoundationKit |
| `service/AuthService.ets` | ✅ 已升级 | AGC Auth 关联 |
| `service/ReminderService.ets` | ✅ 已升级 | 系统提醒代理 |
| `module.json5` | ✅ 已升级 | 新增权限声明 |
| `build-profile.json5` | ✅ 已升级 | 新增云开发能力 |

### 3.2 后续需要完善的部分

1. **CloudService.mergeToLocal()** — 需要根据 AGC 控制台生成的模型类实现具体合并逻辑
2. **AuthService.linkAgcAuth()** — 需要根据 `@hw-agconnect/auth` 的实际 API 完成华为账号→AGC Auth 的关联
3. **云函数代码** — 需要在 AGC 控制台编写和部署服务端函数
4. **照片上传流程** — 在 AlbumPage 中集成 CloudService.uploadFile()
5. **到达通知** — 在 LocationPage 中集成地理围栏 + 云函数通知

---

## 第四阶段：测试流程

### 4.1 本地测试（调试签名）

调试签名不支持 AGC 云服务，但本地功能不受影响：
```bash
# 构建调试包
hvigorw assembleHap

# 安装到设备
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

验证项目：
- [ ] 应用正常启动，无崩溃
- [ ] 登录页面正常显示（华为账号登录按钮优雅降级）
- [ ] 本地数据读写正常
- [ ] 系统提醒发布正常（可能因调试签名降级为本地定时器）
- [ ] 页面切换正确，各模块功能正常

### 4.2 云端测试（发布签名）

使用发布签名构建：
```bash
# 确保签名配置正确后构建
hvigorw assembleHap --mode release
```

验证项目：
- [ ] AGC 初始化成功（查看日志 `[AgcConfig] AGC initialization completed`）
- [ ] 华为账号登录成功
- [ ] AGC Auth 关联成功
- [ ] Cloud DB zone 连接成功
- [ ] 数据推送/拉取同步正常
- [ ] 云存储文件上传/下载正常
- [ ] 系统提醒在锁屏状态正常触发
- [ ] 多设备间数据同步正确
- [ ] 冲突解决逻辑正确

### 4.3 集成测试场景

| 场景 | 测试方法 |
|------|---------|
| 单用户创建家庭 | 创建→验证→数据持久化 |
| 邀请码加入家庭 | 设备A创建→设备B用邀请码加入 |
| 实时数据同步 | 设备A写入→设备B拉取→数据一致 |
| 冲突解决 | 两设备同时修改同记录→版本号高的保留 |
| 离线→在线同步 | 离线操作→恢复网络→数据自动同步 |
| 照片上传 | 拍照→上传→其他家庭成员可见 |

---

## 第五阶段：应用发布

### 5.1 发布前检查清单

- [ ] 版本号更新（`app.json5` → `versionCode` / `versionName`）
- [ ] 隐私政策页面已配置
- [ ] AGC 分析服务已启用
- [ ] 应用图标和启动页已设置
- [ ] 所有权限使用说明已填写
- [ ] 混淆规则已配置
- [ ] 发布签名已绑定

### 5.2 提交发布

1. 构建 Release 包
```bash
hvigorw assembleApp --mode release
```

2. 上传到 AppGallery Connect

   **方式 A：控制台手动上传**
   - AGC 控制台 → **分发** → **版本管理**
   - 上传 `.app` 文件
   - 填写版本信息、更新说明
   - 选择分发范围（先选「测试」→ 再选「正式」）

   **方式 B：使用 Publishing API 自动化**
   - API 基地址: `https://connect-api.cloud.huawei.com`
   - 认证: Service Account (JWT) — 适合 CI/CD
   - 核心端点: 创建版本 → 获取上传地址 → 上传包 → 提交审核
   - 详见 [AGC Publishing API 文档](https://developer.huawei.com/consumer/cn/doc/app/agc-help-publish-api-overview-0000002268498114)

3. 审核发布
   - 提交华为应用市场审核
   - 审核周期通常 1-3 个工作日
   - 审核通过后自动发布

### 5.3 版本迭代路线图

| 版本 | 功能 | 状态 |
|------|------|------|
| V1.0 | 纯本地模式，Preferences存储 | ✅ 已完成 |
| V2.0 | AGC 云端同步，系统提醒，云存储 | 🔄 进行中 |
| V2.1 | RelationalStore 替换 Preferences | 📋 计划中 |
| V3.0 | 实时推送通知，地理围栏到达提醒 | 📋 计划中 |

---

## 常见问题

### Q: 调试包能否使用 AGC 云服务？
A: 不能。调试签名缺少 AGC 所需的签名权限。需要使用发布签名构建的包才能调用云服务。

### Q: 如何获取发布签名？
A: 登录 [华为开发者联盟](https://developer.huawei.com/) → 证书管理 → 申请发布证书和 Profile。

### Q: Cloud DB zone 初始化失败怎么办？
A: 确认 AGC 控制台已创建名为 `kabaoHomeZone` 的存储区，且有至少一个对象类型。注意命名规则：以字母开头，只能包含字母和数字，**不能用下划线**。初始化失败时应用自动降级为纯本地模式。

### Q: ohpm install 报错找不到 AGC 包？
A: 确认 ohpm 仓库源已配置华为官方源。检查 `~/.ohpm/.ohpmrc` 中的 registry 配置。

### Q: @agconnect/cli 是否存在？如何自动化部署？
A: **@agconnect/cli 不存在**，npm registry 上没有这个包。华为 AGC 目前没有提供官方 CLI 工具。自动化方案：
- **云函数部署**：使用 `node cloud/deploy.cjs` 自动打包 zip，然后到 AGC 控制台手动上传
- **应用发布**：使用 AGC Publishing REST API（`connect-api.cloud.huawei.com`）实现 CI/CD 自动化
- **云函数管理**：没有公开 API，只能通过 AGC 控制台操作

### Q: 华为账号登录在调试包不工作？
A: 这是正常的。调试包不具备华为账号 API 调用权限，代码已做优雅降级处理。
