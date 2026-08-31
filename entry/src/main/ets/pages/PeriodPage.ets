/**
 * 卡宝Home - 姨妈周期页面（完整日历+周期计算+啪啪记录+提醒设置）
 */
import { PregnancyRisk, FontSizeMode, THEME_PALETTES, PERIOD_MARK_COLORS , PAGE_TRANSITION_DURATION } from '../common/Constants';
import { BG_PAPER, BG_CARD, BG_SUBTLE, CORAL_BG, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY, BORDER_SUBTLE, SHADOW_CARD, RADIUS_MD, RADIUS_LG, FONT_TITLE, FONT_SUBTITLE, FONT_BODY, FONT_CAPTION, BRAND_CORAL, BRAND_CORAL_DARK, BORDER_CORAL, SEMANTIC_ERROR, SEMANTIC_WARNING, SEMANTIC_SUCCESS, ERROR_BG, WARNING_BG, SUCCESS_BG } from '../common/DesignTokens';
import { PeriodRecord, IntimacyRecord } from '../model/PeriodRecord';
import { PeriodViewModel, CycleStatus, CycleTrendRow, checkPeriodRecordConfirm, SubjectOption, shouldEnterViewerMode } from '../viewmodel/PeriodViewModel';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { CalendarView, MarkedDate } from '../components/CalendarView';
import { formatDate } from '../common/Utils';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import router from '@ohos.router';
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct PeriodPage {
  @State cycleStatus: CycleStatus = {
    currentDay: 0, cycleLength: 28, duration: 5, phase: 'unknown', nextPeriodDate: ''
  };
  @State calendarMarks: MarkedDate[] = [];
  @State displayYear: number = new Date().getFullYear();
  @State displayMonth: number = new Date().getMonth() + 1;
  @State selectedDate: string = formatDate(new Date());
  @State isQuickSaving: boolean = false;
  @State recentIntimacyRecords: IntimacyRecord[] = [];
  @State records: PeriodRecord[] = [];
  @State cycleTrendRows: CycleTrendRow[] = [];
  @State showCycleTrendDialog: boolean = false;
  @State periodInProgress: boolean = false;
  @State latestPeriodDate: string = '';
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themeLightBg: string = BG_PAPER;
  @State themePrimary: string = BRAND_CORAL;
  @State themeBorder: string = BORDER_CORAL;

  // Reminder settings states
  @State remind3DaysBefore: boolean = true;
  @State remind1DayBefore: boolean = true;
  @State remindOvulation: boolean = false;
  @State remindFertile: boolean = false;
  @State recordsRefreshTag: number = 0; // 记录列表刷新标记，记录结束时递增强制刷新
  // 归属主体（谁的周期）：默认自己，可切换到有可见记录的其他成员（只读查看）
  @State selectedSubjectId: string = '';
  @State subjectOptions: SubjectOption[] = [];
  @State isSelfView: boolean = true;
  @State subjectDisplayName: string = '我';
  @State recordSelf: boolean = false;    // 是否显式记录自己的姨妈（覆盖自动仅查看模式）
  @State isViewerMode: boolean = false;  // 仅查看家人模式（无自己的归属数据时自动进入）

  private periodVm: PeriodViewModel = new PeriodViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    this.loadReminderSettings();
    this.refreshData();
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themeLightBg = palette.lightBg;
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
    // 注意：周期提醒同步只在 refreshData() 内做一次。
    // 此处不再额外调用 syncPeriodReminders()，并发触发两次会导致重复创建提醒
    // 主动拉取云端经期数据并刷新（绕过 syncAll 5分钟节流）：
    // 其他成员新记录的经期/啪啪记录无需等全局同步即可显示（否则创建者已更新、
    // 本机仍显示旧缓存，出现「她第4天、我第13天」的分歧）；reconcileLocalDirty
    // 同时会把本机未推送成功的记录补推上去（自愈 push 静默失败）
    const family = this.db.getCurrentFamily();
    if (family) {
      CloudService.getInstance().pullPeriodData(family.id).then((merged: number) => {
        if (merged > 0) {
          this.refreshData();
        }
      });
    }
  }

  private refreshData(): void {
    const selfId = this.periodVm.getSelfSubjectId();
    // 查看者模式判定：没有自己的归属数据（经期/啪啪）且未开启"我要记录自己"
    const selfHasRecords = this.periodVm.getRecordsBySubject(selfId).length > 0
      || this.periodVm.getIntimacyRecordsBySubject(selfId).length > 0;
    const prevViewerMode = this.isViewerMode;
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
    // 被动从查看者模式切回非查看者模式（如其他设备开始记录自己的周期，云端同步进来）：
    // 用户已有自己的数据，强制回到自己视角，否则页面仍停留在查看他人、记录入口被隐藏
    if (prevViewerMode && !this.isViewerMode) {
      selected = selfId;
    }
    this.selectedSubjectId = selected;
    // 查看者模式：记住上次查看的成员（fire-and-forget，与 pushToCloud 同风格）
    if (this.isViewerMode && selected) {
      this.db.savePeriodViewSubject(selected);
    }
    this.isSelfView = selected === selfId;
    const current = this.subjectOptions.find(o => o.memberId === selected);
    this.subjectDisplayName = current ? current.name : (this.isViewerMode ? '家人' : '我');

    // 3. 按主体过滤所有数据
    const subjectId = this.selectedSubjectId;
    this.cycleStatus = this.periodVm.getCurrentCycleStatus(subjectId);
    this.records = this.periodVm.getRecordsBySubject(subjectId);
    this.cycleTrendRows = this.periodVm.getCycleTrendRows(subjectId);
    this.recentIntimacyRecords = this.periodVm.getIntimacyRecordsBySubject(subjectId)
      .sort((a, b) => b.date.localeCompare(a.date))
      .slice(0, 5);
    this.calendarMarks = this.periodVm.getCalendarMarks(this.displayYear, this.displayMonth, subjectId);

    // 派生状态：经期是否进行中
    this.periodInProgress = this.periodVm.isPeriodInProgress(subjectId);
    // 派生状态：最近经期开始日期
    if (this.records.length > 0) {
      const sorted = [...this.records].sort((a, b) => b.startDate.localeCompare(a.startDate));
      this.latestPeriodDate = sorted[0].startDate;
    } else {
      this.latestPeriodDate = '';
    }
    // 递增强制刷新标记，确保 ForEach 正确重渲染（修复结束日期不更新的问题）
    this.recordsRefreshTag++;
    // 周期提醒始终基于自己的周期同步（与查看主体无关）
    this.periodVm.syncPeriodReminders();
  }

  private loadReminderSettings(): void {
    const settings = this.db.getPeriodReminderSettings();
    this.remind3DaysBefore = settings.remind3DaysBefore;
    this.remind1DayBefore = settings.remind1DayBefore;
    this.remindOvulation = settings.remindOvulation;
    this.remindFertile = settings.remindFertile;
    this.recordSelf = settings.recordSelf ?? false;
  }

  private async saveReminderSettings(): Promise<void> {
    await this.db.savePeriodReminderSettings({
      remind3DaysBefore: this.remind3DaysBefore,
      remind1DayBefore: this.remind1DayBefore,
      remindOvulation: this.remindOvulation,
      remindFertile: this.remindFertile,
      recordSelf: this.recordSelf
    });
    // 开关变化后立即同步周期提醒（创建/删除对应的 Reminder 记录）
    await this.periodVm.syncPeriodReminders();
  }

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

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

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
  }

  build() {
    Column() {
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { router.back(); })
        Text(`🌸 ${this.subjectDisplayName === '我' ? '我的姨妈' : this.subjectDisplayName + '的姨妈'}`)
          .fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).layoutWeight(1).textAlign(TextAlign.Center)
        Row().width(34).height(34)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 归属主体切换（我 + 有可见记录的其他成员，查看他人为只读）
      Column({ space: 8 }) {
        this.SubjectSwitcher()
        if (!this.isSelfView) {
          this.ReadOnlyBanner()
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 4 })

      Scroll() {
        Column({ space: 12 }) {
          this.StatusCard()
          this.CalendarSection()
          // 记录/设置按钮仅自己可见；查看他人时全页只读
          if (this.isSelfView) {
            this.QuickActions()
          }
          // 排序：经期记录 → 怀孕几率 → 啪啪记录 → 提醒设置
          this.PeriodRecordList()
          this.PregnancyRiskCard()
          this.IntimacyHistory()
          if (this.isSelfView) {
            this.ReminderSettings()
          }
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.themeLightBg)
    .bindContentCover(this.showCycleTrendDialog, this.CycleTrendDialog(), {
      onDisappear: () => {
        this.showCycleTrendDialog = false;
      }
    })
  }

  @Builder
  SubjectSwitcher() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.subjectOptions, (opt: SubjectOption) => {
          Text(opt.name)
            .fontSize(14)
            .fontWeight(opt.memberId === this.selectedSubjectId ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(opt.memberId === this.selectedSubjectId ? Color.White : NEUTRAL_INK)
            .backgroundColor(opt.memberId === this.selectedSubjectId ? BRAND_CORAL_DARK : Color.White)
            .border({ width: 1, color: opt.memberId === this.selectedSubjectId ? BRAND_CORAL_DARK : BORDER_SUBTLE })
            .borderRadius(16)
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .onClick(() => {
              if (this.selectedSubjectId === opt.memberId) return;
              this.selectedSubjectId = opt.memberId;
              this.refreshData();
            })
        }, (opt: SubjectOption) => opt.memberId)
      }
      .padding({ right: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

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

  @Builder
  StatusCard() {
    Column() {
      if (this.cycleStatus.currentDay > 0) {
        Text(`第${this.cycleStatus.currentDay}天`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text(`${this.getPhaseLabel(this.cycleStatus.phase)} · 预计${this.cycleStatus.nextPeriodDate}下次经期`)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .margin({ top: 4 })
        if (this.cycleStatus.earliestPeriodDate && this.cycleStatus.latestPeriodDate) {
          Text(`可能范围 ${this.cycleStatus.earliestPeriodDate} ~ ${this.cycleStatus.latestPeriodDate}`)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .margin({ top: 3 })
          Text(this.cycleStatus.isAdaptive ? `已根据最近${this.cycleStatus.validCycleCount}次有效周期动态预测` : '记录较少，暂按当前周期估算')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .margin({ top: 2 })
        }
        Row({ space: 8 }) {
          // 审核整改： chips 必须显式白字（原缺省字体色在深色模式下翻白）+ 深色半透明底
          Text(`周期: ${this.cycleStatus.cycleLength}天`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0,0,0,0.18)')
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          Text(`持续: ${this.cycleStatus.duration}天`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('rgba(0,0,0,0.18)')
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        }
        .margin({ top: 8 })
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
    }
    .width('100%')
    .padding(16)
    .borderRadius(RADIUS_MD)
    // 审核整改：渐变加深，白字对比度从 2.8:1 提升到 5.1:1 以上
    .linearGradient({ angle: 135, colors: [[BRAND_CORAL_DARK, 0], ['#8E3A4C', 1]] })
    .alignItems(HorizontalAlign.Start)
    .shadow(SHADOW_CARD)
  }

  @Builder
  CalendarSection() {
    Column() {
      // 图例 — 颜色与日历渲染保持一致，增加姨妈开始/结束 emoji 说明
      Row({ space: 10 }) {
        Row({ space: 3 }) { Text('🩸').fontSize(10); Text('开始').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY) }
        Row({ space: 3 }) { Text('🌸').fontSize(10); Text('结束').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill(PERIOD_MARK_COLORS.PERIOD); Text('经期').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY) }
        Row({ space: 3 }) {
          // 第1天 = 经期实心圆 + 中心白点（与日历中「1」白字标记对应）
          Stack() {
            Circle().width(10).height(10).fill(PERIOD_MARK_COLORS.PERIOD)
            Circle().width(4).height(4).fill('#FFFFFF')
          }
          Text('第1天').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY)
        }
        Row({ space: 3 }) { Circle().width(10).height(10).fill(PERIOD_MARK_COLORS.FERTILE).opacity(0.3); Text('易孕期').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill(PERIOD_MARK_COLORS.SAFE).opacity(0.3); Text('安全期').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY) }
        Row({ space: 3 }) { Text('⭐').fontSize(10); Text('排卵日').fontSize(10).fontColor(NEUTRAL_INK_SECONDARY) }
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .padding({ bottom: 8 })

      CalendarView({
        markedDates: this.calendarMarks,
        themePrimary: this.themePrimary,
        themeBorder: this.themeBorder,
        onDateSelected: (date: string) => {
          this.selectedDate = date;
        },
        onMonthChanged: (year: number, month: number) => {
          this.displayYear = year;
          this.displayMonth = month;
          this.calendarMarks = this.periodVm.getCalendarMarks(year, month, this.selectedSubjectId);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  QuickActions() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('🎀 来了')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(PERIOD_MARK_COLORS.PERIOD)
          .borderRadius(20)
          .layoutWeight(1)
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .enabled(!this.isQuickSaving)
          .onClick(async () => {
            if (this.isQuickSaving) return; // 防重复提交
            if (this.selectedDate > formatDate(new Date())) {
              AlertDialog.show({ message: '不能记录未来日期的经期' });
              return;
            }
            const doSave = async () => {
              this.isQuickSaving = true;
              try {
                await this.periodVm.savePeriodRecord(
                  this.selectedDate,
                  this.cycleStatus.duration || 5,
                  this.cycleStatus.cycleLength || 28
                );
                this.refreshData();
              } catch (err) {
                const errMsg = err instanceof Error ? err.message : String(err);
                AlertDialog.show({ message: `保存失败: ${errMsg}` });
              } finally {
                this.isQuickSaving = false;
              }
            };
            // 误触保护：经期进行中或比预计周期提前较多时弹窗确认
            const confirm = checkPeriodRecordConfirm(this.records, this.selectedDate);
            if (confirm.needsConfirm) {
              AlertDialog.show({
                title: '确认记录经期？',
                message: confirm.message,
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '确认记录',
                  action: doSave
                }
              });
              return;
            }
            await doSave();
          })

        Button('✨ 结束')
          .fontSize(14)
          .fontColor(PERIOD_MARK_COLORS.PERIOD)
          .backgroundColor(Color.White)
          .border({ width: 1, color: PERIOD_MARK_COLORS.PERIOD })
          .borderRadius(20)
          .layoutWeight(1)
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .enabled(this.periodInProgress)
          .opacity(this.periodInProgress ? 1.0 : 0.4)
          .onClick(async () => {
            const endDate = this.selectedDate;
            // 不能选择未来日期
            if (endDate > formatDate(new Date())) {
              AlertDialog.show({ message: '结束日期不能是未来日期' });
              return;
            }
            const records = this.periodVm.getRecordsBySubject(this.selectedSubjectId);
            if (records.length === 0) return;
            // 同一天多条记录时（结束后再点来了），按 createdAt 降序确保取到最新创建的
            const sorted = [...records].sort((a, b) => {
              const cmp = b.startDate.localeCompare(a.startDate);
              if (cmp !== 0) return cmp;
              return b.createdAt.localeCompare(a.createdAt);
            });
            // 取最新的未结束记录（endDate 为空）
            const latest = sorted.find(r => !r.endDate || r.endDate === '');
            if (!latest) {
              AlertDialog.show({ message: '当前没有进行中的经期' });
              return;
            }
            if (endDate < latest.startDate) {
              AlertDialog.show({ message: '结束日期不能早于开始日期' });
              return;
            }
            AlertDialog.show({
              title: '确认结束日期',
              message: `经期从 ${latest.startDate} 开始，\n确认 ${endDate} 结束吗？`,
              primaryButton: {
                value: '取消',
                action: () => {}
              },
              secondaryButton: {
                value: '确认',
                action: async () => {
                  try {
                    await this.periodVm.endPeriod(endDate, this.selectedSubjectId);
                    this.refreshData();
                  } catch (err) {
                    const errMsg = err instanceof Error ? err.message : String(err);
                    AlertDialog.show({ message: `保存失败: ${errMsg}` });
                  }
                }
              }
            });
          })

        Button('💕 啪啪')
          .fontSize(14)
          .fontColor(PERIOD_MARK_COLORS.PERIOD)
          .backgroundColor(Color.White)
          .border({ width: 1, color: PERIOD_MARK_COLORS.PERIOD })
          .borderRadius(20)
          .layoutWeight(1)
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .enabled(!this.isQuickSaving)
          .onClick(async () => {
            if (this.isQuickSaving) return; // 防重复提交
            this.isQuickSaving = true;
            try {
              if (this.selectedDate > formatDate(new Date())) {
                AlertDialog.show({ message: '不能记录未来日期的啪啪' });
                return;
              }
              await this.periodVm.saveIntimacyRecord(this.selectedDate, '');
              this.refreshData();
            } finally {
              this.isQuickSaving = false;
            }
          })
      }
      .width('100%')

      // 经期进行中提示
      if (this.periodInProgress && this.latestPeriodDate) {
        Row() {
          Text('🩷 经期进行中')
            .fontSize(13)
            .fontColor(PERIOD_MARK_COLORS.PERIOD)
            .fontWeight(FontWeight.Bold)
          Text(`· 开始于 ${this.latestPeriodDate}`)
            .fontSize(13)
            .fontColor(PERIOD_MARK_COLORS.PERIOD)
          Text('· 点击"记录结束"更新周期')
            .fontSize(13)
            .fontColor(PERIOD_MARK_COLORS.PERIOD)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(CORAL_BG)
      }
    }
    .width('100%')
  }

  @Builder
  CycleTrendDialog() {
    Column() {
      Row() {
        Blank().width(34)
        Text('月经周期')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('×')
          .fontSize(30)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .width(34)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showCycleTrendDialog = false;
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 14 })
      .backgroundColor(Color.White)

      Scroll() {
        Column() {
          Column() {
            Row() {
              Text('月经开始')
                .fontSize(13)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .width(88)
              Text('周期天数')
                .fontSize(13)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .layoutWeight(1)
              Text('是否准时')
                .fontSize(13)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .width(82)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .padding({ left: 8, right: 8, bottom: 8 })

            Stack() {
              Column() {}
                .width('34%')
                .height('100%')
                .backgroundColor(CORAL_BG)
                .position({ x: '47%', y: 0 })
              Column({ space: 14 }) {
                if (this.cycleTrendRows.length === 0) {
                  Text('暂无周期记录')
                    .fontSize(15)
                    .fontColor(NEUTRAL_INK_SECONDARY)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 120 })
                } else {
                  ForEach(this.cycleTrendRows, (row: CycleTrendRow) => {
                    this.CycleTrendRowItem(row)
                  }, (row: CycleTrendRow) => row.startDate + '_' + row.cycleLabel)
                }
              }
              .width('100%')
              .padding({ left: 8, right: 8 })
              Text('正常范围21-35天')
                .fontSize(13)
                .fontColor(PERIOD_MARK_COLORS.PERIOD)
                .position({ x: '54%', y: 2 })
            }
            .width('100%')
            .height(Math.max(360, this.cycleTrendRows.length * 58 + 24))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 16, bottom: 20 })
          .borderRadius(18)
          .backgroundColor(Color.White)
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .backgroundColor(BG_SUBTLE)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_SUBTLE)
  }

  @Builder
  CycleTrendRowItem(row: CycleTrendRow) {
    Row() {
      Text(row.displayDate)
        .fontSize(15)
        .fontColor(NEUTRAL_INK_SECONDARY)
        .width(88)
      Stack({ alignContent: Alignment.Start }) {
        if (row.isCurrentCycle) {
          Text(row.cycleLabel)
            .fontSize(14)
            .fontColor(PERIOD_MARK_COLORS.PERIOD)
            .border({ width: 1, color: PERIOD_MARK_COLORS.PERIOD, style: BorderStyle.Dashed })
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(CORAL_BG)
        } else {
          Row() {
            Blank()
            Text(row.cycleLabel)
              .fontSize(14)
              .fontColor(Color.White)
              .margin({ right: 10 })
          }
          .width(`${row.barWidthPercent}%`)
          .height(34)
          .borderRadius(8)
          .linearGradient({ angle: 0, colors: [[BRAND_CORAL, 0], ['#B55D6E', 1]] })
          .shadow({ radius: 4, color: '#22000000', offsetX: 0, offsetY: 2 })
        }
      }
      .layoutWeight(1)
      .height(36)
      Text(row.punctualityLabel)
        .fontSize(15)
        .fontColor(row.isCurrentCycle ? NEUTRAL_INK_SECONDARY : NEUTRAL_INK)
        .width(82)
    }
    .width('100%')
    .height(44)
  }

  @Builder
  PeriodRecordList() {
    Column({ space: 8 }) {
      Row() {
        Text('🩷 经期记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).layoutWeight(1)
        Text('周期趋势')
          .fontSize(13)
          .fontColor(PERIOD_MARK_COLORS.PERIOD)
          .backgroundColor(CORAL_BG)
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .onClick(() => {
            this.cycleTrendRows = this.periodVm.getCycleTrendRows(this.selectedSubjectId);
            this.showCycleTrendDialog = true;
          })
      }
      .width('100%')

      if (this.records.length === 0) {
        Text('暂无经期记录，点击"🎀 记录来了"开始')
          .fontSize(15).fontColor(NEUTRAL_INK_SECONDARY).width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(Color.White)
      } else {
        // 按开始日期降序展示
        ForEach(
          [...this.records].sort((a, b) => b.startDate.localeCompare(a.startDate)),
          (record: PeriodRecord) => {
            Column({ space: 4 }) {
              Row() {
                Text('🩷')
                  .fontSize(14)
                Text(record.startDate)
                  .fontSize(17).fontColor(NEUTRAL_INK).fontWeight(FontWeight.Bold)
                // 经期进行中标记 — 判断逻辑：endDate 非空且与 startDate 不同才算已结束
                if (!record.endDate || record.endDate === '') {
                  Text('进行中')
                    .fontSize(13).fontColor('#FFFFFF')
                    .backgroundColor(PERIOD_MARK_COLORS.PERIOD)
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .margin({ left: 6 })
                } else {
                  Text(`→ ${record.endDate}`)
                    .fontSize(15).fontColor(NEUTRAL_INK_SECONDARY)
                    .margin({ left: 4 })
                }
                Blank()
                Text(`${record.duration}天`)
                  .fontSize(14).fontColor(PERIOD_MARK_COLORS.PERIOD)
                  .backgroundColor(CORAL_BG)
                  .borderRadius(8)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                Text(`周期${record.cycleLength}天`)
                  .fontSize(14).fontColor(PERIOD_MARK_COLORS.PERIOD)
                  .backgroundColor(CORAL_BG)
                  .borderRadius(8)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .margin({ left: 4 })
              }
              .width('100%')

              // 备注（兼容历史数据）
              if (record.note) {
                Text(record.note)
                  .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              // 操作按钮
              Row({ space: 12 }) {
                if (this.isCreator(record.creatorId)) {
                  if (!record.endDate || record.endDate === '') {
                    Text('结束经期')
                      .fontSize(15).fontColor(PERIOD_MARK_COLORS.PERIOD)
                      .onClick(() => {
                        if (this.selectedDate > formatDate(new Date())) {
                          AlertDialog.show({ message: '结束日期不能是未来日期' });
                          return;
                        }
                        AlertDialog.show({
                          title: '确认结束日期',
                          message: `经期从 ${record.startDate} 开始，\n确认 ${this.selectedDate} 结束吗？`,
                          primaryButton: {
                            value: '取消',
                            action: () => {}
                          },
                          secondaryButton: {
                            value: '确认',
                            action: async () => {
                              try {
                                await this.periodVm.endPeriod(this.selectedDate, this.selectedSubjectId);
                                this.refreshData();
                              } catch (err) {
                                const errMsg = err instanceof Error ? err.message : String(err);
                                AlertDialog.show({ message: `保存失败: ${errMsg}` });
                              }
                            }
                          }
                        });
                      })
                  }
                  Text('删除')
                    .fontSize(15).fontColor(NEUTRAL_INK_SECONDARY)
                    .onClick(() => {
                      AlertDialog.show({
                        title: '确认删除',
                        message: '确定要删除这条经期记录吗？',
                        primaryButton: {
                          value: '取消',
                          action: () => {}
                        },
                        secondaryButton: {
                          value: '删除',
                          action: async () => {
                            await this.db.deletePeriodRecord(record.id);
                            this.refreshData();
                          }
                        }
                      });
                    })
                }
              }
              .width('100%')
              .margin({ top: 2 })
            }
            .width('100%')
            .padding(14)
            .borderRadius(10)
            .backgroundColor(Color.White)
            .alignItems(HorizontalAlign.Start)
          },
          (record: PeriodRecord) => record.id + '_' + this.recordsRefreshTag
        )
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor(Color.White)
    .shadow({ radius: 1, color: '#0A000000', offsetX: 0, offsetY: 1 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ReminderSettings() {
    Column({ space: 12 }) {
      Text('🔔 提醒设置').fontSize(16).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).width('100%')

      Row() {
        Column() {
          Text('经期前3天提醒').fontSize(16).fontColor(NEUTRAL_INK)
          Text('提前3天通知即将来经期').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remind3DaysBefore })
          .onChange(async (isOn: boolean) => {
            this.remind3DaysBefore = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(PERIOD_MARK_COLORS.PERIOD)
      }
      .width('100%')

      Divider().color(BORDER_SUBTLE)

      Row() {
        Column() {
          Text('经期前1天提醒').fontSize(16).fontColor(NEUTRAL_INK)
          Text('提前1天通知即将来经期').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remind1DayBefore })
          .onChange(async (isOn: boolean) => {
            this.remind1DayBefore = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(PERIOD_MARK_COLORS.PERIOD)
      }
      .width('100%')

      Divider().color(BORDER_SUBTLE)

      Row() {
        Column() {
          Text('排卵期提醒').fontSize(16).fontColor(NEUTRAL_INK)
          Text('排卵日当天通知').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remindOvulation })
          .onChange(async (isOn: boolean) => {
            this.remindOvulation = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(PERIOD_MARK_COLORS.PERIOD)
      }
      .width('100%')

      Divider().color(BORDER_SUBTLE)

      Row() {
        Column() {
          Text('易孕期提醒').fontSize(16).fontColor(NEUTRAL_INK)
          Text('易孕窗口开始时通知').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remindFertile })
          .onChange(async (isOn: boolean) => {
            this.remindFertile = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(PERIOD_MARK_COLORS.PERIOD)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor(Color.White)
    .shadow({ radius: 1, color: '#0A000000', offsetX: 0, offsetY: 1 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PregnancyRiskCard() {
    if (this.cycleStatus.currentDay > 0) {
      Column() {
        Text('今日怀孕几率').fontSize(15).fontColor(NEUTRAL_INK_SECONDARY)
        Row({ space: 8 }) {
          Text(this.getRiskIcon(this.getCurrentRisk()))
            .fontSize(28)
          Text(this.getRiskLabel(this.getCurrentRisk()))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getRiskColor(this.getCurrentRisk()))
        }
        .margin({ top: 8 })
        Text(this.getRiskAdvice(this.getCurrentRisk()))
          .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
      }
      .width('100%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(Color.White)
      .shadow({ radius: 1, color: '#0A000000', offsetX: 0, offsetY: 1 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  IntimacyHistory() {
    Column({ space: 8 }) {
      Text('💕 啪啪记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).width('100%')

      if (this.recentIntimacyRecords.length === 0) {
        Text('暂无啪啪记录')
          .fontSize(15).fontColor(NEUTRAL_INK_SECONDARY).width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(Color.White)
      } else {
        ForEach(this.recentIntimacyRecords, (record: IntimacyRecord) => {
          Row() {
            Text(record.date).fontSize(17).fontColor(NEUTRAL_INK).layoutWeight(1)
            Text(`周期第${record.cycleDay}天`).fontSize(15).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 8 })
            Text(this.getRiskLabel(record.pregnancyRisk))
              .fontSize(14)
              .fontColor(this.getRiskColor(record.pregnancyRisk))
              .backgroundColor(this.getRiskBg(record.pregnancyRisk))
              .borderRadius(8)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            if (this.isCreator(record.creatorId)) {
              Text('删除')
                .fontSize(15)
                .fontColor(this.themePrimary)
                .margin({ left: 8 })
                .onClick(() => {
                  AlertDialog.show({
                    title: '确认删除',
                    message: '确定要删除这条啪啪记录吗？',
                    primaryButton: {
                      value: '取消',
                      action: () => {}
                    },
                    secondaryButton: {
                      value: '删除',
                      action: async () => {
                        await this.db.deleteIntimacyRecord(record.id);
                        this.refreshData();
                      }
                    }
                  });
                })
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(Color.White)
        }, (record: IntimacyRecord) => record.id + '_' + record.updatedAt)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor(Color.White)
    .shadow({ radius: 1, color: '#0A000000', offsetX: 0, offsetY: 1 })
    .alignItems(HorizontalAlign.Start)
  }

  private getCurrentRisk(): PregnancyRisk {
    const phase = this.cycleStatus.phase;
    if (phase === 'ovulation' || phase === 'fertile') return PregnancyRisk.HIGH;
    if (phase === 'safe_before' || phase === 'safe_after') return PregnancyRisk.LOW;
    if (phase === 'menstrual') return PregnancyRisk.LOW;
    return PregnancyRisk.MEDIUM;
  }

  private getPhaseLabel(phase: string): string {
    const map: Record<string, string> = {
      'menstrual': '经期中', 'fertile': '易孕期', 'ovulation': '排卵日',
      'safe_before': '安全期', 'safe_after': '安全期'
    };
    return map[phase] ?? '';
  }

  private getRiskIcon(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return '🔴';
    if (risk === PregnancyRisk.MEDIUM) return '🟡';
    return '🟢';
  }

  private getRiskLabel(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return '高';
    if (risk === PregnancyRisk.MEDIUM) return '中';
    return '低';
  }

  private getRiskColor(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return SEMANTIC_ERROR;
    if (risk === PregnancyRisk.MEDIUM) return SEMANTIC_WARNING;
    return SEMANTIC_SUCCESS;
  }

  private getRiskBg(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return ERROR_BG;
    if (risk === PregnancyRisk.MEDIUM) return WARNING_BG;
    return SUCCESS_BG;
  }

  private getRiskAdvice(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return '当前处于易孕期，怀孕几率较高';
    if (risk === PregnancyRisk.MEDIUM) return '当前怀孕几率中等';
    return '当前处于安全期，怀孕几率较低';
  }
}
