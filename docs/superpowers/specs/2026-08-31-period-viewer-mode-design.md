# 姨妈周期「仅查看家人」模式（Period Viewer Mode）设计

日期：2026-08-31
状态：已批准（用户选定「隐藏自己 + 纯查看」方向）

## 背景与问题

男性成员（或不想记录自己的用户）不需要记录自己的姨妈，只想看家里其他人共享的周期信息。

现有代码已具备「归属主体切换」机制：
- [PeriodViewModel.ets](../../../entry/src/main/ets/viewmodel/PeriodViewModel.ets) 所有展示方法都接受 `subjectId`（`getCurrentCycleStatus` / `getCalendarMarks` / `getCycleTrendRows` / `getRecordsBySubject` 等）
- [PeriodPage.ets](../../../entry/src/main/ets/pages/PeriodPage.ets) 已有 `SubjectSwitcher`（我 + 有可见记录的其他成员），切到他人时 `ReadOnlyBanner` 提示只读，`QuickActions` / `ReminderSettings` 按 `isSelfView` 隐藏

缺的三块：
1. 每次打开默认停在「我」（无记录时是空状态卡「尚未记录周期」），男性用户必须手动切换
2. 无记录时「我」chip 与标题「我的姨妈」是噪音
3. 没有「开回来」记录自己的入口

数据侧前置条件已满足：pull-data 按可见性过滤（FAMILY→全员 / PRIVATE→创建者 / SELECTED→创建者+visibleMembers），只要家人把周期设为「家庭可见」或「指定成员」包含本人，记录即同步到本机。

## 方案：查看者模式（Viewer Mode）

### 触发规则（自动 + 可覆盖）

- **自动进入查看者模式**：当前用户**没有自己的经期记录且没有自己的啪啪记录**（归属主体 = 自己，含旧 openID 格式归一化后）时自动进入
- **覆盖开关**：设置里「我要记录自己的姨妈」（默认关）。开启后即使没有记录也显示「我」chip、可开始记录——这是"开回来"的入口

> 判定口径：自己的**归属数据**（经期 + 啪啪任一存在即视为"有自己数据"）。男性用户若记录啪啪（归属自己），应保留「我」chip。

### 页面行为（PeriodPage.ets）

1. **buildSubjectOptions(viewerMode)**：查看者模式下**不加入「我」**，只列有可见记录的家庭成员；非查看者模式维持现状（我 + 成员）
2. **默认视角**：
   - 查看者模式：`selectedSubjectId` 优先取**记忆的 subject**（Preferences），无效/为自己时回退到第一个有可见记录的成员
   - 非查看者模式：维持现状默认「我」，**不应用记忆**（记录者本人行为不变）
3. **隐藏**：查看者模式 `isSelfView` 恒为 false → QuickActions（来了/结束/啪啪）、ReminderSettings 自动隐藏（现有 `isSelfView` 分支已覆盖，零新增）；经期/啪啪列表的编辑删除按钮靠 `isCreator` 判断，查看他人时本就不显示
4. **标题**：查看他人时自动「xx 的姨妈」（现有逻辑已覆盖）
5. **空态**：查看者模式且没有任何成员有可见记录时，状态卡显示「暂无家人共享的姨妈记录」+ 引导（去设置开启记录 / 邀请家人共享），不再显示误导性的「点击下方按钮开始记录」
6. **Banner 快捷入口**：ReadOnlyBanner 增加「我想开始记录自己」点击项，一键置 `recordSelf=true` 并保存（设置里的开关保留，双入口）
7. **切换记忆**：查看者模式下记住上次查看的成员（Preferences key `period_view_subject`），下次打开直接落在该成员视角

### 设置项（SettingsPage.ets）

在「我的姨妈」模块的分享设置弹窗（`SharingDialogContent`，仅 `sharingModuleId === ModuleId.PERIOD` 时显示）加「我的角色」区块：

> **我要记录自己的姨妈** [Toggle]
> 关闭时：没有自己的记录就自动进入"仅查看家人"模式

- Toggle 变更**立即生效**（不经「确定」按钮），复用 `savePeriodReminderSettings` 保存整个 settings blob（展开现有值 + 覆盖 `recordSelf`，不丢其他开关）

### 数据层（纯客户端，零云端/schema 改动）

1. [PeriodRecord.ets](../../../entry/src/main/ets/model/PeriodRecord.ets) `PeriodReminderSettings` 增加可选字段：
   ```typescript
   /** 是否显式记录自己的姨妈（覆盖"无记录自动进入仅查看模式"）。默认 false，兼容已存 JSON */
   recordSelf: boolean;
   ```
2. [LocalDbService.ets](../../../entry/src/main/ets/service/LocalDbService.ets)：
   - `getPeriodReminderSettings` 两个默认返回对象补 `recordSelf: false`（旧 JSON 无此字段时 `undefined` 视为 false）
   - 新增 `savePeriodViewSubject` / `getPeriodViewSubject`（Preferences key `period_view_subject`）
3. [PeriodViewModel.ets](../../../entry/src/main/ets/viewmodel/PeriodViewModel.ets) 新增纯函数（可单测）：
   ```typescript
   export function shouldEnterViewerMode(selfHasRecords: boolean, recordSelf: boolean): boolean {
     return !recordSelf && !selfHasRecords;
   }
   ```

### 关键时序注意

- `aboutToAppear` 中 `loadReminderSettings()` 必须在 `refreshData()` **之前**执行（`refreshData` 读取 `this.recordSelf` 判定查看者模式；当前代码顺序相反需调整）
- [PeriodPage.saveReminderSettings](../../../entry/src/main/ets/pages/PeriodPage.ets#L166-L175) 保存 4 个提醒开关时必须带上 `recordSelf`（展开现有 settings 再覆盖，避免覆盖丢失）

## 影响面

| 文件 | 改动 |
|------|------|
| entry/src/main/ets/pages/PeriodPage.ets | viewer 判定 + buildSubjectOptions + 默认视角 + 空态 + Banner 入口 + subject 记忆 + 保存时带 recordSelf |
| entry/src/main/ets/pages/SettingsPage.ets | 分享弹窗加「我的角色」区块（仅 PERIOD） |
| entry/src/main/ets/model/PeriodRecord.ets | interface 加 `recordSelf` |
| entry/src/main/ets/service/LocalDbService.ets | 默认值补字段 + 两个 subject 记忆方法 |
| entry/src/main/ets/viewmodel/PeriodViewModel.ets | 纯函数 `shouldEnterViewerMode` |

无云函数、无 Cloud DB schema、无权限改动。

## 验证

1. **单元测试**（纯函数）：`shouldEnterViewerMode` 四象限（有无记录 × 开关）；`buildSubjectOptions` 的 viewer 过滤可抽纯函数测试
2. **真机场景**：
   - 男账号无记录 → 打开默认看到第一个有共享记录家人的周期、全页只读、标题「xx 的姨妈」
   - Banner「我想开始记录自己」→ 「我」chip 回来、可记录；设置里开关同步
   - 设置关闭开关 → 回到仅查看模式
   - 家人记录 PRIVATE → 看不到（云端过滤，符合预期）
   - 多个共享成员 → 切换后记忆生效，重开落在上次查看的成员
   - 记录者本人（有自己记录）→ 行为与现状完全一致（默认「我」）

## 边界与不做的事

- 不做服务端角色/性别字段（V1 靠"有无自己数据"自动推断 + 本地开关，各设备独立记忆）
- 不做「仅查看」模式下的写操作（看别人记录时本就只读，由 isCreator 保证）
- 不改通知/提醒逻辑（查看者模式 syncPeriodReminders 对无记录者本就是 no-op）
