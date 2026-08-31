# 姨妈周期「仅查看家人」模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让没有自己经期记录的成员（如男性用户）默认进入「仅查看家人」模式——隐藏自己的「我」chip 与记录入口，直接看到共享家人的周期；设置里可一键「开回来」记录自己。

**Architecture:** 纯客户端改动。在现有 subjectId 归属主体机制上叠加「查看者模式」判定：`PeriodReminderSettings` 增加可选 `recordSelf` 开关 + 自动判定（无自己的归属数据即进入查看模式）。PeriodPage 的 subject 选项构建从页面方法提取为 PeriodViewModel 纯函数（可单测），SettingsPage 分享弹窗加「我的角色」区块。零云端/schema 改动。

**Tech Stack:** ArkTS / ArkUI（HarmonyOS NEXT）、Preferences（@kit.ArkData）、@ohos/hypium（ohosTest 单测）、hvigorw 构建。

**前置知识：**
- 构建命令：`hvigorw assembleHap`（主应用）；ohosTest 编译：`hvigorw --mode module -p module=entry@ohosTest -p isTest=true assembleHap`（**执行**单测需 DevEco Studio Test Runner + 真机/模拟器，本环境只能编译验证）
- 现有单测文件：`entry/src/ohosTest/ets/test/PeriodViewModel.test.ets`（@ohos/hypium 的 describe/it/expect）
- fire-and-forget 惯例：async 方法可不 await 调用（如 `this.pushToCloud(...)` 全项目如此）

---

### Task 1: 模型加 `recordSelf` 字段 + LocalDbService 默认值

**Files:**
- Modify: `entry/src/main/ets/model/PeriodRecord.ets:24-29`
- Modify: `entry/src/main/ets/service/LocalDbService.ets:896,901`

- [ ] **Step 1: 修改 `PeriodReminderSettings` 接口，加可选字段**

`entry/src/main/ets/model/PeriodRecord.ets`，把：
```typescript
export interface PeriodReminderSettings {
  remind3DaysBefore: boolean;
  remind1DayBefore: boolean;
  remindOvulation: boolean;
  remindFertile: boolean;
}
```
改为：
```typescript
export interface PeriodReminderSettings {
  remind3DaysBefore: boolean;
  remind1DayBefore: boolean;
  remindOvulation: boolean;
  remindFertile: boolean;
  /** 是否显式记录自己的姨妈（覆盖"无记录自动进入仅查看模式"）。可选：旧 JSON 无此字段视为 false */
  recordSelf?: boolean;
}
```

> 必须用**可选字段**：`entry/src/ohosTest/ets/test/PeriodViewModel.test.ets:110-117` 的 `DEFAULT_SETTINGS` / `ALL_ON_SETTINGS` 字面量没有此字段，必选字段会编译报错。

- [ ] **Step 2: LocalDbService 两个默认返回补 `recordSelf: false`**

`entry/src/main/ets/service/LocalDbService.ets`，第 896 行和 901 行两处：
```typescript
      return { remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false };
```
都改为：
```typescript
      return { remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false, recordSelf: false };
```

- [ ] **Step 3: 编译验证**

Run: `hvigorw assembleHap`
Expected: BUILD SUCCESSFUL，无 ArkTS 错误

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/model/PeriodRecord.ets entry/src/main/ets/service/LocalDbService.ets
git commit -m "feat: add recordSelf flag to period reminder settings"
```

---

### Task 2: PeriodViewModel 纯函数（判定 + 选项构建）+ 单测

**Files:**
- Modify: `entry/src/main/ets/viewmodel/PeriodViewModel.ets`（文件末尾，`filterRecordsBySubject` 之后）
- Test: `entry/src/ohosTest/ets/test/PeriodViewModel.test.ets`

- [ ] **Step 1: 写失败测试**

在 `entry/src/ohosTest/ets/test/PeriodViewModel.test.ets`：
1. 修改 import（第 6-10 行），加 `shouldEnterViewerMode, buildSubjectOptions`：
```typescript
import {
  PeriodViewModel, CycleStatus, calculateAdaptivePeriodPrediction, calculateCycleTrendRows,
  buildPeriodReminderSpecs, isManagedPeriodReminderId, planPeriodReminderSync, PeriodReminderSpec,
  checkPeriodRecordConfirm, EARLY_PERIOD_CONFIRM_DAYS, normalizeSubjectId, filterRecordsBySubject,
  shouldEnterViewerMode, buildSubjectOptions
} from '../../main/ets/viewmodel/PeriodViewModel';
```
2. 在文件末尾（最后一个 `describe` 之后）追加：
```typescript
describe('shouldEnterViewerMode', () => {
  it('无记录且未开启记录 → 进入仅查看模式', () => {
    expect(shouldEnterViewerMode(false, false)).assertTrue();
  });
  it('有记录 → 不进入仅查看模式', () => {
    expect(shouldEnterViewerMode(true, false)).assertFalse();
  });
  it('开启记录开关 → 即使无记录也不进入', () => {
    expect(shouldEnterViewerMode(false, true)).assertFalse();
  });
  it('有记录且开启开关 → 不进入', () => {
    expect(shouldEnterViewerMode(true, true)).assertFalse();
  });
});

describe('buildSubjectOptions', () => {
  const selfId = 'mem_self';
  const membersById = new Map<string, string>();
  membersById.set('mem_self', '我');
  membersById.set('mem_wife', '老婆');
  const membersByUserId = makeMembersByUserId(); // openid_self->mem_self, openid_wife->mem_wife（文件已有辅助函数）

  it('非查看模式：自己在前，成员在后，名称映射正确', () => {
    const records = [makeRecordWithCreator('2026-08-01', 'openid_wife')];
    const opts = buildSubjectOptions(selfId, records, [], membersById, membersByUserId, false);
    expect(opts.length).assertEqual(2);
    expect(opts[0].memberId).assertEqual('mem_self');
    expect(opts[0].name).assertEqual('我');
    expect(opts[1].memberId).assertEqual('mem_wife');
    expect(opts[1].name).assertEqual('老婆');
  });

  it('查看模式：排除自己，只列有记录的其他成员', () => {
    const records = [makeRecordWithCreator('2026-08-01', 'openid_wife')];
    const opts = buildSubjectOptions(selfId, records, [], membersById, membersByUserId, true);
    expect(opts.length).assertEqual(1);
    expect(opts[0].memberId).assertEqual('mem_wife');
  });

  it('查看模式：没有其他成员记录时返回空列表', () => {
    const opts = buildSubjectOptions(selfId, [], [], membersById, membersByUserId, true);
    expect(opts.length).assertEqual(0);
  });

  it('同一成员多条记录（含啪啪记录）只出现一次', () => {
    const records = [
      makeRecordWithCreator('2026-08-01', 'mem_wife'),
      makeRecordWithCreator('2026-07-01', 'mem_wife')
    ];
    const intimacy = [makeIntimacyRecordWithCreator('2026-08-10', 'openid_wife')];
    const opts = buildSubjectOptions(selfId, records, intimacy, membersById, membersByUserId, false);
    expect(opts.length).assertEqual(2); // mem_self + mem_wife
  });
});
```

- [ ] **Step 2: 运行测试验证失败**

Run: `hvigorw --mode module -p module=entry@ohosTest -p isTest=true assembleHap`
Expected: 编译失败，`Cannot find name 'shouldEnterViewerMode'` / `Cannot find name 'buildSubjectOptions'`

- [ ] **Step 3: 实现纯函数**

在 `entry/src/main/ets/viewmodel/PeriodViewModel.ets` 末尾（`filterRecordsBySubject` 函数之后）追加：
```typescript
// ===== 归属主体选项 + 查看者模式判定 =====

/** 归属主体选项：memberId 为记录归属主体（我或共享成员），name 为展示名 */
export interface SubjectOption {
  memberId: string;
  name: string;
}

/**
 * 判断当前用户是否应进入"仅查看家人"模式（纯函数）：
 * 未开启"我要记录自己的姨妈"（recordSelf=false）且没有自己的归属数据（经期/啪啪）时进入
 */
export function shouldEnterViewerMode(selfHasRecords: boolean, recordSelf: boolean): boolean {
  return !recordSelf && !selfHasRecords;
}

/**
 * 构建归属主体选项（纯函数）：
 * - viewerMode=true：排除自己，只列有可见记录的其他成员（仅查看家人）
 * - viewerMode=false：自己在最前，其后是有可见记录的其他成员
 * membersById：memberId → 成员名；membersByUserId：openID → memberId（旧格式 creatorId 归一化）
 */
export function buildSubjectOptions(selfId: string,
  records: PeriodRecord[],
  intimacyRecords: IntimacyRecord[],
  membersById: Map<string, string>,
  membersByUserId: Map<string, string>,
  viewerMode: boolean): SubjectOption[] {
  const options: SubjectOption[] = [];
  const seen = new Set<string>();
  if (!viewerMode) {
    seen.add(selfId);
    options.push({ memberId: selfId, name: '我' });
  }
  const addSubject = (creatorId: string): void => {
    const s = normalizeSubjectId(creatorId, membersByUserId);
    if (s && !seen.has(s)) {
      seen.add(s);
      options.push({ memberId: s, name: membersById.get(s) ?? '成员' });
    }
  };
  for (const r of records) {
    addSubject(r.creatorId);
  }
  for (const r of intimacyRecords) {
    addSubject(r.creatorId);
  }
  return options;
}
```

- [ ] **Step 4: 编译验证测试通过**

Run: `hvigorw --mode module -p module=entry@ohosTest -p isTest=true assembleHap`
Expected: BUILD SUCCESSFUL（编译通过 = 纯函数签名/类型正确）
> 单测执行需 DevEco Studio Test Runner 连真机/模拟器，本环境编译通过即视为通过；如可连设备请在 DevEco 运行 `PeriodViewModel` 测试组确认 8 条断言全绿。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/viewmodel/PeriodViewModel.ets entry/src/ohosTest/ets/test/PeriodViewModel.test.ets
git commit -m "feat: add viewer-mode helpers with tests"
```

---

### Task 3: LocalDbService 查看成员记忆存取

**Files:**
- Modify: `entry/src/main/ets/service/LocalDbService.ets`（`getPeriodReminderSettings` 之后，约第 903 行）

- [ ] **Step 1: 新增两个方法**

在 `entry/src/main/ets/service/LocalDbService.ets` 的 `getPeriodReminderSettings()` 方法（结束于第 903 行）之后追加：
```typescript
  // ---- 姨妈页查看的归属主体记忆（仅查看家人模式下记住上次看的成员）----
  async savePeriodViewSubject(subjectId: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('period_view_subject', subjectId);
    await p.flush();
  }

  getPeriodViewSubject(): string {
    const p = this.ensurePrefs();
    return p.getSync('period_view_subject', '') as string;
  }
```

- [ ] **Step 2: 编译验证**

Run: `hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/service/LocalDbService.ets
git commit -m "feat: persist last viewed period subject"
```

---

### Task 4: PeriodPage 查看者模式

**Files:**
- Modify: `entry/src/main/ets/pages/PeriodPage.ets`

- [ ] **Step 1: 改 import + 删本地 SubjectOption 接口**

`entry/src/main/ets/pages/PeriodPage.ets`：
1. 第 7 行 import 改为（加 `SubjectOption, shouldEnterViewerMode`）：
```typescript
import { PeriodViewModel, CycleStatus, CycleTrendRow, checkPeriodRecordConfirm, SubjectOption, shouldEnterViewerMode } from '../viewmodel/PeriodViewModel';
```
2. 删除第 16-20 行的本地接口：
```typescript
/** 归属主体选项：memberId 为记录归属主体（我或共享成员），name 为展示名 */
interface SubjectOption {
  memberId: string;
  name: string;
}
```

- [ ] **Step 2: 加两个 @State**

在 `@State subjectDisplayName: string = '我';`（第 56 行）之后追加：
```typescript
  @State recordSelf: boolean = false;    // 是否显式记录自己的姨妈（覆盖自动仅查看模式）
  @State isViewerMode: boolean = false;  // 仅查看家人模式（无自己的归属数据时自动进入）
```

- [ ] **Step 3: 调整 aboutToAppear 顺序 + loadReminderSettings 加载 recordSelf**

第 62-64 行，把：
```typescript
  aboutToAppear(): void {
    this.refreshData();
    this.loadReminderSettings();
```
改为（**loadReminderSettings 必须先执行**——recordSelf 参与 refreshData 的查看者判定）：
```typescript
  aboutToAppear(): void {
    this.loadReminderSettings();
    this.refreshData();
```

`loadReminderSettings()`（第 158-164 行）末尾追加：
```typescript
    this.recordSelf = settings.recordSelf ?? false;
```

`saveReminderSettings()`（第 166-175 行）的保存对象末尾追加（避免覆盖丢失 recordSelf）：
```typescript
      recordSelf: this.recordSelf
```

- [ ] **Step 4: 重写 refreshData 的视角判定与默认选择**

把 `refreshData()`（第 91-125 行）的开头部分（第 92-100 行）：
```typescript
    // 1. 构建归属主体选项（我 + 有可见记录的其他成员）
    this.buildSubjectOptions();
    // 2. 校验当前选择的主体仍有效（记录被删/共享被撤回时回退到自己）
    if (!this.subjectOptions.some(o => o.memberId === this.selectedSubjectId)) {
      this.selectedSubjectId = this.periodVm.getSelfSubjectId();
    }
    this.isSelfView = this.selectedSubjectId === this.periodVm.getSelfSubjectId();
    const current = this.subjectOptions.find(o => o.memberId === this.selectedSubjectId);
    this.subjectDisplayName = current ? current.name : '我';
```
替换为：
```typescript
    const selfId = this.periodVm.getSelfSubjectId();
    // 查看者模式判定：没有自己的归属数据（经期/啪啪）且未开启"我要记录自己"
    const selfHasRecords = this.periodVm.getRecordsBySubject(selfId).length > 0
      || this.periodVm.getIntimacyRecordsBySubject(selfId).length > 0;
    this.isViewerMode = shouldEnterViewerMode(selfHasRecords, this.recordSelf);

    // 1. 构建归属主体选项（查看者模式排除自己，纯函数）
    this.subjectOptions = this.periodVm.getSubjectOptions(this.isViewerMode);

    // 2. 默认/校验当前选择
    let selected = this.selectedSubjectId;
    const valid = this.subjectOptions.some(o => o.memberId === selected);
    if (!valid) {
      if (this.isViewerMode) {
        // 查看者模式：优先取记忆的成员，无效/为空时回退到第一个有可见记录的成员
        selected = this.db.getPeriodViewSubject();
        if (!this.subjectOptions.some(o => o.memberId === selected)) {
          selected = this.subjectOptions.length > 0 ? this.subjectOptions[0].memberId : '';
        }
      } else {
        selected = selfId;
      }
    }
    this.selectedSubjectId = selected;
    // 查看者模式：记住上次查看的成员（fire-and-forget，与 pushToCloud 同风格）
    if (this.isViewerMode && selected) {
      this.db.savePeriodViewSubject(selected);
    }
    this.isSelfView = selected === selfId;
    const current = this.subjectOptions.find(o => o.memberId === selected);
    this.subjectDisplayName = current ? current.name : (this.isViewerMode ? '家人' : '我');
```

- [ ] **Step 5: 删除本地 buildSubjectOptions / getMemberName，改用 ViewModel 方法**

删除 `buildSubjectOptions()`（第 127-148 行）和 `getMemberName()`（第 150-156 行）两个方法。

在 `PeriodViewModel` 类中新增一个包装方法（见下方 Step 6 一并加）。

- [ ] **Step 6: PeriodViewModel 加 getSubjectOptions 包装方法**

`entry/src/main/ets/viewmodel/PeriodViewModel.ets`，在 `getIntimacyRecords()`（第 153-155 行）之后加：
```typescript
  /** 构建归属主体选项（我 + 有可见记录的其他成员；查看者模式排除自己） */
  getSubjectOptions(viewerMode: boolean): SubjectOption[] {
    const membersById = new Map<string, string>();
    for (const m of this.db.getMembers()) {
      if (m.id) {
        membersById.set(m.id, m.name || '');
      }
    }
    return buildSubjectOptions(this.getSelfSubjectId(), this.getRecords(), this.getIntimacyRecords(),
      membersById, this.getMembersUserIdMap(), viewerMode);
  }
```

- [ ] **Step 7: ReadOnlyBanner 加「我想开始记录自己」入口**

把 `ReadOnlyBanner()`（第 278-293 行）整体替换为：
```typescript
  @Builder
  ReadOnlyBanner() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text('👁️')
          .fontSize(13)
        Text(`正在查看「${this.subjectDisplayName}」的周期记录 · 仅可查看`)
          .fontSize(13)
          .fontColor(NEUTRAL_INK)
          .layoutWeight(1)
      }
      .width('100%')
      Text('我想开始记录自己的姨妈 ›')
        .fontSize(12)
        .fontColor(this.themePrimary)
        .onClick(() => {
          this.enableSelfRecording();
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(CORAL_BG)
    .border({ width: 1, color: BORDER_SUBTLE })
  }
```

- [ ] **Step 8: 加 enableSelfRecording 方法**

在 `isCreator()`（第 177-179 行）之后加：
```typescript
  /** 开启"我要记录自己"（仅查看模式的快捷入口），保存后切回自己视角 */
  private async enableSelfRecording(): Promise<void> {
    const s = this.db.getPeriodReminderSettings();
    await this.db.savePeriodReminderSettings({
      remind3DaysBefore: s.remind3DaysBefore,
      remind1DayBefore: s.remind1DayBefore,
      remindOvulation: s.remindOvulation,
      remindFertile: s.remindFertile,
      recordSelf: true
    });
    this.recordSelf = true;
    this.selectedSubjectId = this.periodVm.getSelfSubjectId();
    this.refreshData();
  }
```

- [ ] **Step 9: StatusCard 空态区分查看者模式**

把 `StatusCard()`（第 333-338 行）的 else 分支：
```typescript
      } else {
        Text('尚未记录周期')
          .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        Text('点击下方按钮开始记录')
          .fontSize(15).fontColor('#FFFFFF').margin({ top: 4 })
      }
```
替换为：
```typescript
      } else if (this.isViewerMode) {
        Text('暂无家人共享的姨妈记录')
          .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        Text('家人需将周期设为「家庭可见」或包含你的「指定成员」')
          .fontSize(14).fontColor('#FFFFFF').margin({ top: 4 })
      } else {
        Text('尚未记录周期')
          .fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
        Text('点击下方按钮开始记录')
          .fontSize(15).fontColor('#FFFFFF').margin({ top: 4 })
      }
```

- [ ] **Step 10: 编译验证**

Run: `hvigorw assembleHap`
Expected: BUILD SUCCESSFUL，无 ArkTS 错误（注意：若报 `getSubjectOptions` 未定义，确认 Task 4 Step 6 已加；若报 `SubjectOption` 重复定义，确认本地接口已删）

- [ ] **Step 11: Commit**

```bash
git add entry/src/main/ets/pages/PeriodPage.ets entry/src/main/ets/viewmodel/PeriodViewModel.ets
git commit -m "feat: period page viewer mode (hide self, default to family member)"
```

---

### Task 5: SettingsPage「我的角色」区块

**Files:**
- Modify: `entry/src/main/ets/pages/SettingsPage.ets`

- [ ] **Step 1: 加 @State recordSelf**

在 `@State sharingModuleId: ModuleId = ModuleId.PERIOD;`（第 50 行）附近加：
```typescript
  @State recordSelf: boolean = false; // 「我的姨妈」模块：是否记录自己（仅查看家人时置关）
```

- [ ] **Step 2: openSharingConfig 初始化 recordSelf**

`openSharingConfig()`（第 1361-1363 行）开头加：
```typescript
    this.recordSelf = this.db.getPeriodReminderSettings().recordSelf ?? false;
```
即方法变成：
```typescript
  private openSharingConfig(moduleId: ModuleId): void {
    this.sharingModuleId = moduleId;
    this.recordSelf = this.db.getPeriodReminderSettings().recordSelf ?? false;
    this.tempVisibility = this.db.getModuleVisibility(moduleId);
```
（保留原有 `tempVisibility` 等行不动，只插入 recordSelf 行）

- [ ] **Step 3: SharingDialogContent 加「我的角色」区块（仅 PERIOD）**

在 `SharingDialogContent()` 的 `getSharingHint()` 行（第 1211 行）之后、按钮 Row 之前插入：
```typescript
    if (this.sharingModuleId === ModuleId.PERIOD) {
      Divider().color(BORDER_SUBTLE).margin({ top: 14, bottom: 12 })
      Row() {
        Column() {
          Text('我的角色').fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          Text('关闭时：没有自己的记录就自动进入「仅查看家人」模式')
            .fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.recordSelf })
          .onChange((isOn: boolean) => {
            this.setRecordSelf(isOn);
          })
          .selectedColor(this.getPalette().primary)
      }
      .width('100%')
    }
```

- [ ] **Step 4: 加 setRecordSelf 方法**

在 `saveSharingConfig()` 方法附近加：
```typescript
  /** 「我的姨妈」我的角色开关：立即生效（不经弹窗确定按钮） */
  private async setRecordSelf(isOn: boolean): Promise<void> {
    const s = this.db.getPeriodReminderSettings();
    await this.db.savePeriodReminderSettings({
      remind3DaysBefore: s.remind3DaysBefore,
      remind1DayBefore: s.remind1DayBefore,
      remindOvulation: s.remindOvulation,
      remindFertile: s.remindFertile,
      recordSelf: isOn
    });
    this.recordSelf = isOn;
  }
```

- [ ] **Step 5: 编译验证**

Run: `hvigorw assembleHap`
Expected: BUILD SUCCESSFUL

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/pages/SettingsPage.ets
git commit -m "feat: add self-recording toggle to period sharing settings"
```

---

### Task 6: 端到端验证

**Files:** 无代码改动（真机验证清单）

- [ ] **Step 1: 全量构建**

Run: `hvigorw assembleHap`
Expected: BUILD SUCCESSFUL，产物 `entry/build/default/outputs/default/entry-default-signed.hap`

- [ ] **Step 2: 真机场景验证**（两台设备：男账号 / 女账号；女账号周期设为「家庭可见」）

| # | 场景 | 预期 |
|---|------|------|
| 1 | 男账号无记录打开姨妈页 | 默认显示老婆的周期，标题「xx 的姨妈」，无「我」chip，无记录按钮/提醒设置 |
| 2 | 点击 Banner「我想开始记录自己的姨妈」 | 「我」chip 出现、选中自己、可记录；去设置确认开关已开 |
| 3 | 设置里关闭「我要记录自己的姨妈」 | 回到仅查看模式，默认老婆视角 |
| 4 | 多个共享成员时切换查看 | 重开页面落在上次查看的成员（记忆生效） |
| 5 | 老婆记录 PRIVATE | 男账号看不到（云端过滤，符合预期） |
| 6 | 女账号（有自己记录）打开 | 行为与改前完全一致：默认「我」、记录按钮在 |

- [ ] **Step 3: 回归检查**

Run: `hvigorw --mode module -p module=entry@ohosTest -p isTest=true assembleHap`
Expected: BUILD SUCCESSFUL（确认新增 8 条断言无编译问题）
