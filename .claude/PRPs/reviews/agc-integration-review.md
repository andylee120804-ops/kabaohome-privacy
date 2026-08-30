# Code Review: AGC Cloud Integration Upgrade

** Reviewed: 2026-06-07
** Branch: master
** Decision: APPROVE WITH COMMENTS (all CRITICAL/HIGH issues fixed)

## Summary

卡宝Home 项目从 V1 纯本地模式升级为"本地优先 + 云端同步"架构。所有 AGC 服务（Auth、CloudDB、CloudFunction、CloudStorage）均已接入框架代码，并包含完善的降级策略。经两轮代码审查修复后，仅剩 MEDIUM/LOW 级别的建议项。

## Findings

### CRITICAL (已修复)

| # | 问题 | 文件 | 修复 |
|---|------|------|------|
| C1 | 签名凭据暴露在 build-profile.json5 | build-profile.json5 | 已添加 .gitignore + 创建 .example 模板 |
| C2 | AGC client_secret/api_key 在 agconnect-services.json 中 | rawfile/agconnect-services.json | 已添加 .gitignore 排除 |

### HIGH (已修复)

| # | 问题 | 文件 | 修复 |
|---|------|------|------|
| H1 | `require()` 在 ArkTS 中不兼容 | EntryAbility.ets:104 | 已替换为静态 import |
| H2 | `buffer.from()` 缺少导入 | AgcConfig.ets:87 | 已添加 `import { buffer } from '@kit.ArkTS'` |
| H3 | Calendar dateTime 年/月/日为0无效 | ReminderService.ets:140 | 已改用下次触发真实日期 |
| H4 | NOTIFICATION_CONTROLLER 是系统权限 | module.json5:100 | 已替换为 NOTIFICATION_ENABLED |
| H5 | 缺少 permission_reminder 等字符串资源 | string.json | 已补充 |
| H6 | deleteFromCloud 死代码 + 编译错误 | CloudService.ets:228 | 已删除死代码 |
| H7 | AgcConfig.init() 竞态条件 | AgcConfig.ets:77 | 已添加 initPromise 复用守卫 |
| H8 | reminderService 异步发布未 await | ReminderService.ets:97 | 已改为 async + 顺序 await |

### MEDIUM (已修复/建议)

| # | 问题 | 文件 | 修复 |
|---|------|------|------|
| M1 | processQueue 迭代中修改队列 | CloudService.ets:355 | 已快照队列再迭代 |
| M3 | loadPublishedReminders 未清理旧ID | ReminderService.ets:306 | 已启动时清理 |
| M4 | 邀请码用 Math.random() 不安全 | AuthService.ets:203 | 已标注 TODO(crypto)，生产前替换 |
| M5 | 每次前台切换触发同步无双抖 | EntryAbility.ets:64 | 已添加 5 分钟最小间隔 |
| M6 | mergeToLocal 静默丢弃数据 | CloudService.ets:440 | 已改为 warn 级别日志 |
| M8 | timeSlot 格式未验证 | ReminderService.ets:126 | 已添加 NaN/范围校验 |
| M9 | AuthService 用 openID 作为 AGC UID | AuthService.ets:421 | 已标记 `pending_` 前缀 |
| M10 | module.json5 硬编码 client_id | module.json5:18 | 建议未来从 AgcConfig 运行读取 |

### LOW (建议)

| # | 问题 | 文件 | 建议 |
|---|------|------|------|
| L1 | ohpm 包版本 ^1.0.5 未验证 | oh-package.json5 | 本地 ohpm install 验证 |
| L2 | pullAll 串行拉取 14 种类型 | CloudService.ets:395 | 可分批并行化 |
| L3 | getAuthInstance 返回 object 类型 | AgcConfig.ets:122 | 应使用 AGConnectAuth 类型 |
| L4 | 缺少公共 API 的 JSDoc | 所有服务文件 | 补充文档 |

## Validation Results

| Check | Result |
|-------|--------|
| ArkTS compatibility | ⚠️ 需 ohpm install 后验证 |
| Security | ✅ .gitignore 已保护凭据文件 |
| Error handling | ✅ 所有云服务调用含降级策略 |
| Build | ⏳ 需在 DevEco Studio 中验证 |

## Files Reviewed

| File | Change Type |
|------|------------|
| entry/oh-package.json5 | Modified |
| entry/src/main/ets/service/AgcConfig.ets | Added |
| entry/src/main/ets/entryability/EntryAbility.ets | Modified |
| entry/src/main/ets/service/CloudService.ets | Modified (rewritten) |
| entry/src/main/ets/service/AuthService.ets | Modified |
| entry/src/main/ets/service/ReminderService.ets | Modified (rewritten) |
| entry/src/main/module.json5 | Modified |
| build-profile.json5 | Modified |
| entry/src/main/resources/base/element/string.json | Modified |
| AGC_SETUP_GUIDE.md | Added |
| build-profile.json5.example | Added |
| .gitignore | Modified |
