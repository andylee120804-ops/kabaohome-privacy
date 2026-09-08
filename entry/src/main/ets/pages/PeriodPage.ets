/**
 * 卡宝Home - 姨妈周期页面（方向 C 极简编辑风）
 * flat 编辑风：无卡片阴影、细分隔线、直角、衬线标题
 * 保留全部功能：数据绑定、状态、导航、周期计算、记录弹窗
 */
import { PregnancyRisk, FontSizeMode, PAGE_TRANSITION_DURATION } from '../common/Constants';
import {
  BG_PAPER, DIVIDER, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, BRAND_RED_LG, FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_CAPTION_SM,
  FONT_FAMILY_SERIF, FONT_DISPLAY, FONT_TITLE, FONT_SUBTITLE,
  SEMANTIC_ERROR, SEMANTIC_WARNING, SEMANTIC_SUCCESS, ERROR_BG, WARNING_BG, SUCCESS_BG
} from '../common/DesignTokens';
import { PeriodRecord, IntimacyRecord } from '../model/PeriodRecord';
import { PeriodViewModel, CycleStatus, CycleTrendRow, checkPeriodRecordConfirm, SubjectOption, shouldEnterViewerMode } from '../viewmodel/PeriodViewModel';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { CalendarView, MarkedDate } from '../components/CalendarView';
import { IconButton } from '../components/IconButton';
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

  // Reminder settings states
  @State remind3DaysBefore: boolean = true;
  @State remind1DayBefore: boolean = true;
  @State remindOvulation: boolean = false;
  @State remindFertile: boolean = false;
  @State recordsRefreshTag: number = 0;
  // 归属主体（谁的周期）：默认自己，可切换到有可见记录的其他成员（只读查看）
  @State selectedSubjectId: string = '';
  @State subjectOptions: SubjectOption[] = [];
  @State isSelfView: boolean = true;
  @State subjectDisplayName: string = '我';
  @State recordSelf: boolean = false;
  @State isViewerMode: boolean = false;

  private periodVm: PeriodViewModel = new PeriodViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    this.loadReminderSettings();
    this.refreshData();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
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
    const selfHasRecords = this.periodVm.getRecordsBySubject(selfId).length > 0
      || this.periodVm.getIntimacyRecordsBySubject(selfId).length > 0;
    const prevViewerMode = this.isViewerMode;
    this.isViewerMode = shouldEnterViewerMode(selfHasRecords, this.recordSelf);

    this.subjectOptions = this.periodVm.getSubjectOptions(this.isViewerMode);

    let selected = this.selectedSubjectId;
    const valid = this.subjectOptions.some(o => o.memberId === selected);
    if (!valid) {
      if (this.isViewerMode) {
        selected = this.db.getPeriodViewSubject();
        if (!this.subjectOptions.some(o => o.memberId === selected)) {
          selected = this.subjectOptions.length > 0 ? this.subjectOptions[0].memberId : '';
        }
      } else {
        selected = selfId;
      }
    }
    if (prevViewerMode && !this.isViewerMode) {
      selected = selfId;
    }
    this.selectedSubjectId = selected;
    if (this.isViewerMode && selected) {
      this.db.savePeriodViewSubject(selected);
    }
    this.isSelfView = selected === selfId;
    const current = this.subjectOptions.find(o => o.memberId === selected);
    this.subjectDisplayName = current ? current.name : (this.isViewerMode ? '家人' : '我');

    const subjectId = this.selectedSubjectId;
    this.cycleStatus = this.periodVm.getCurrentCycleStatus(subjectId);
    this.records = this.periodVm.getRecordsBySubject(subjectId);
    this.cycleTrendRows = this.periodVm.getCycleTrendRows(subjectId);
    this.recentIntimacyRecords = this.periodVm.getIntimacyRecordsBySubject(subjectId)
      .sort((a, b) => b.date.localeCompare(a.date))
      .slice(0, 5);
    this.calendarMarks = this.periodVm.getCalendarMarks(this.displayYear, this.displayMonth, subjectId);

    this.periodInProgress = this.periodVm.isPeriodInProgress(subjectId);
    if (this.records.length > 0) {
      const sorted = [...this.records].sort((a, b) => b.startDate.localeCompare(a.startDate));
      this.latestPeriodDate = sorted[0].startDate;
    } else {
      this.latestPeriodDate = '';
    }
    this.recordsRefreshTag++;
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
    await this.periodVm.syncPeriodReminders();
  }

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

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

  /** 计算预计排卵日（Ogino-Knaus：下次经期前14天） */
  private getOvulationDate(): string {
    if (this.cycleStatus.nextPeriodDate) {
      const d = new Date(this.cycleStatus.nextPeriodDate + 'T00:00:00');
      d.setDate(d.getDate() - 14);
      return formatDate(d);
    }
    if (this.latestPeriodDate && this.cycleStatus.cycleLength) {
      const start = new Date(this.latestPeriodDate + 'T00:00:00');
      start.setDate(start.getDate() + this.cycleStatus.cycleLength - 14);
      return formatDate(start);
    }
    return '';
  }

  private getDaysUntil(targetDate: string): number {
    if (!targetDate) return 0;
    const target = new Date(targetDate + 'T00:00:00');
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const diff = Math.round((target.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
    return diff > 0 ? diff : 0;
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
  }

  build() {
    Column() {
      // ---- 顶栏：back SVG + 衬线标题（"姨妈"墨黑 + "周期"红） ----
      Row() {
        IconButton({ icon: 'back', iconSize: 40, activeColor: NEUTRAL_INK, onTap: () => { router.back(); } })
        Row() {
          Text('姨妈')
            .fontSize(this.isLargeFont ? FONT_TITLE + 4 : FONT_TITLE)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
          Text('周期')
            .fontSize(this.isLargeFont ? FONT_TITLE + 4 : FONT_TITLE)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(BRAND_RED)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        Row().width(40).height(40)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })

      // ---- 归属主体切换 ----
      if (this.subjectOptions.length > 1) {
        this.SubjectSwitcher()
      }
      if (!this.isSelfView) {
        this.ReadOnlyBanner()
      }

      // ---- 滚动内容区 ----
      Scroll() {
        Column({ space: 0 }) {
          this.CalendarSection()
          this.StatusCard()
          if (this.isSelfView) {
            this.QuickActions()
          }
          this.PeriodRecordList()
          this.PregnancyRiskCard()
          this.IntimacyHistory()
          if (this.isSelfView) {
            this.ReminderSettings()
          }
        }
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
    .backgroundColor(BG_PAPER)
    .bindContentCover(this.showCycleTrendDialog, this.CycleTrendDialog(), {
      onDisappear: () => {
        this.showCycleTrendDialog = false;
      }
    })
  }

  @Builder
  SubjectSwitcher() {
    Scroll() {
      Row({ space: 0 }) {
        ForEach(this.subjectOptions, (opt: SubjectOption) => {
          Column() {
            Text(opt.name)
              .fontSize(FONT_CAPTION)
              .fontFamily(FONT_FAMILY_SERIF)
              .fontColor(opt.memberId === this.selectedSubjectId ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
              .fontWeight(opt.memberId === this.selectedSubjectId ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: 12, right: 12, top: 8, bottom: 6 })
            // 选中态：底部 2px 红线；未选中：透明
            Row()
              .width('100%')
              .height(2)
              .backgroundColor(opt.memberId === this.selectedSubjectId ? BRAND_RED : Color.Transparent)
          }
          .onClick(() => {
            if (this.selectedSubjectId === opt.memberId) return;
            this.selectedSubjectId = opt.memberId;
            this.refreshData();
          })
        }, (opt: SubjectOption) => opt.memberId)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
  }

  @Builder
  ReadOnlyBanner() {
    Column({ space: 2 }) {
      Text(`正在查看「${this.subjectDisplayName}」的周期记录 · 仅可查看`)
        .fontSize(FONT_CAPTION_SM)
        .fontColor(NEUTRAL_INK_TERTIARY)
      Text('我想开始记录自己的姨妈 ›')
        .fontSize(FONT_CAPTION_SM)
        .fontColor(BRAND_RED)
        .fontFamily(FONT_FAMILY_SERIF)
        .onClick(() => {
          this.enableSelfRecording();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  StatusCard() {
    Column({ space: 4 }) {
      if (this.cycleStatus.currentDay > 0) {
        // 巨大日期数字 96sp 衬线 — 末位红色斜体
        Row() {
          if (this.cycleStatus.currentDay >= 10) {
            Text(`${Math.floor(this.cycleStatus.currentDay / 10)}`)
              .fontSize(96)
              .fontFamily(FONT_FAMILY_SERIF)
              .fontColor(NEUTRAL_INK)
          }
          Text(`${this.cycleStatus.currentDay % 10}`)
            .fontSize(96)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(BRAND_RED)
            .fontStyle(FontStyle.Italic)
        }
        .height(100)

        Text(`周期第 ${this.cycleStatus.currentDay} 天`)
          .fontSize(FONT_CAPTION)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK_TERTIARY)

        Text(this.getPhaseLabel(this.cycleStatus.phase))
          .fontSize(FONT_BODY_LARGE)
          .fontColor(NEUTRAL_INK)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 2 })

        // 预计排卵日 / 下次经期
        if (this.cycleStatus.phase !== 'ovulation' && this.cycleStatus.phase !== 'safe_after') {
          if (this.getOvulationDate()) {
            Row({ space: 4 }) {
              Text('预计排卵日')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              Text('·')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              Text(this.getOvulationDate())
                .fontSize(FONT_CAPTION).fontColor(BRAND_RED).fontFamily(FONT_FAMILY_SERIF)
              Text(`（${this.getDaysUntil(this.getOvulationDate())}天后）`)
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
            }
            .margin({ top: 4 })
          }
        }
        if (this.cycleStatus.nextPeriodDate) {
          Row({ space: 4 }) {
            Text('预计下次经期')
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
            Text('·')
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
            Text(this.cycleStatus.nextPeriodDate)
              .fontSize(FONT_CAPTION).fontColor(BRAND_RED).fontFamily(FONT_FAMILY_SERIF)
            Text(`（${this.getDaysUntil(this.cycleStatus.nextPeriodDate)}天后）`)
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
          }
          .margin({ top: 2 })
        }

        // 可能范围
        if (this.cycleStatus.earliestPeriodDate && this.cycleStatus.latestPeriodDate) {
          Text(`可能范围 ${this.cycleStatus.earliestPeriodDate} ~ ${this.cycleStatus.latestPeriodDate}`)
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
          Text(this.cycleStatus.isAdaptive
            ? `已根据最近${this.cycleStatus.validCycleCount}次有效周期动态预测`
            : '记录较少，暂按当前周期估算')
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
        }

        // 周期/持续（行内文字，无 chip）
        Row({ space: 6 }) {
          Text(`周期 ${this.cycleStatus.cycleLength}天`)
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
          Text('·')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
          Text(`持续 ${this.cycleStatus.duration}天`)
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .margin({ top: 4 })
      } else if (this.isViewerMode) {
        Text('暂无家人共享的姨妈记录')
          .fontSize(FONT_TITLE)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK)
        Text('家人需将周期设为「家庭可见」或包含你的「指定成员」')
          .fontSize(FONT_CAPTION)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .margin({ top: 4 })
      } else {
        Text('尚未记录周期')
          .fontSize(FONT_TITLE)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK)
        Text('点击下方"记录经期"开始')
          .fontSize(FONT_CAPTION)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 24, bottom: 24 })
    .border({ width: { top: 2 }, color: NEUTRAL_INK })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  CalendarSection() {
    Column() {
      CalendarView({
        markedDates: this.calendarMarks,
        themePrimary: BRAND_RED_LG,
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
    Column() {
      Row() {
        // 记录经期（合并原"来了"逻辑）
        Column() {
          Text('记录经期')
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .height(52)
        .onClick(async () => {
          if (this.isQuickSaving) return;
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

        // 1px 竖向分隔线
        Column().width(1).height(28).backgroundColor(DIVIDER)

        // 啪啪记录
        Column() {
          Text('啪啪记录')
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .height(52)
        .onClick(async () => {
          if (this.isQuickSaving) return;
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
      .border({ width: { top: 0.5, bottom: 0.5 }, color: DIVIDER })

      // 经期进行中提示（subtle 行内文字）
      if (this.periodInProgress && this.latestPeriodDate) {
        Text(`经期进行中 · 开始于 ${this.latestPeriodDate} · 下方记录可结束`)
          .fontSize(FONT_CAPTION_SM)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 6 })
      }
    }
    .width('100%')
  }

  @Builder
  CycleTrendDialog() {
    Column() {
      // 弹窗顶栏
      Row() {
        Blank().width(34)
        Text('月经周期')
          .fontSize(FONT_TITLE)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('×')
          .fontSize(28)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .width(34)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showCycleTrendDialog = false;
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 14 })
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      Scroll() {
        Column() {
          Column() {
            // 表头
            Row() {
              Text('月经开始')
                .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY)
                .fontFamily(FONT_FAMILY_SERIF)
                .width(88)
              Text('周期天数')
                .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY)
                .fontFamily(FONT_FAMILY_SERIF)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
              Text('是否准时')
                .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY)
                .fontFamily(FONT_FAMILY_SERIF)
                .width(82)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .padding({ left: 8, right: 8, bottom: 8 })
            .border({ width: { bottom: 0.5 }, color: DIVIDER })

            Stack() {
              // 正常范围底色条
              Column() {}
                .width('34%')
                .height('100%')
                .backgroundColor(BG_PAPER)
                .position({ x: '47%', y: 0 })

              Column({ space: 14 }) {
                if (this.cycleTrendRows.length === 0) {
                  Text('暂无周期记录')
                    .fontSize(FONT_BODY_LARGE)
                    .fontColor(NEUTRAL_INK_TERTIARY)
                    .fontFamily(FONT_FAMILY_SERIF)
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
                .fontSize(FONT_CAPTION_SM)
                .fontColor(BRAND_RED)
                .fontFamily(FONT_FAMILY_SERIF)
                .position({ x: '54%', y: 2 })
            }
            .width('100%')
            .height(Math.max(360, this.cycleTrendRows.length * 58 + 24))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 16, bottom: 20 })
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .backgroundColor(BG_PAPER)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAPER)
  }

  @Builder
  CycleTrendRowItem(row: CycleTrendRow) {
    Row() {
      Text(row.displayDate)
        .fontSize(FONT_BODY)
        .fontColor(NEUTRAL_INK_SECONDARY)
        .fontFamily(FONT_FAMILY_SERIF)
        .width(88)
      Stack({ alignContent: Alignment.Start }) {
        if (row.isCurrentCycle) {
          Text(row.cycleLabel)
            .fontSize(FONT_CAPTION)
            .fontColor(BRAND_RED)
            .fontFamily(FONT_FAMILY_SERIF)
            .border({ width: 1, color: BRAND_RED, style: BorderStyle.Dashed })
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        } else {
          Row() {
            Blank()
            Text(row.cycleLabel)
              .fontSize(FONT_CAPTION)
              .fontColor(Color.White)
              .margin({ right: 10 })
          }
          .width(`${row.barWidthPercent}%`)
          .height(34)
          .backgroundColor(BRAND_RED)
        }
      }
      .layoutWeight(1)
      .height(36)
      Text(row.punctualityLabel)
        .fontSize(FONT_BODY)
        .fontColor(row.isCurrentCycle ? NEUTRAL_INK_SECONDARY : NEUTRAL_INK)
        .fontFamily(FONT_FAMILY_SERIF)
        .width(82)
    }
    .width('100%')
    .height(44)
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
  }

  @Builder
  PeriodRecordList() {
    Column({ space: 0 }) {
      // 区块标题
      Row() {
        Text('经期记录')
          .fontSize(FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK)
          .layoutWeight(1)
        Text('周期趋势')
          .fontSize(FONT_CAPTION)
          .fontColor(BRAND_RED)
          .fontFamily(FONT_FAMILY_SERIF)
          .onClick(() => {
            this.cycleTrendRows = this.periodVm.getCycleTrendRows(this.selectedSubjectId);
            this.showCycleTrendDialog = true;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (this.records.length === 0) {
        Text('暂无经期记录，点击"记录经期"开始')
          .fontSize(FONT_CAPTION)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      } else {
        ForEach(
          [...this.records].sort((a, b) => b.startDate.localeCompare(a.startDate)),
          (record: PeriodRecord) => {
            Column({ space: 4 }) {
              Row() {
                Text(record.startDate)
                  .fontSize(FONT_BODY_LARGE)
                  .fontColor(NEUTRAL_INK)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(FONT_FAMILY_SERIF)
                if (!record.endDate || record.endDate === '') {
                  Text('进行中')
                    .fontSize(FONT_CAPTION_SM)
                    .fontColor(BRAND_RED)
                    .margin({ left: 6 })
                } else {
                  Text(`→ ${record.endDate}`)
                    .fontSize(FONT_CAPTION)
                    .fontColor(NEUTRAL_INK_TERTIARY)
                    .margin({ left: 4 })
                }
                Blank()
                Text(`${record.duration}天`)
                  .fontSize(FONT_CAPTION)
                  .fontColor(NEUTRAL_INK_SECONDARY)
                Text(`· 周期${record.cycleLength}天`)
                  .fontSize(FONT_CAPTION)
                  .fontColor(NEUTRAL_INK_SECONDARY)
                  .margin({ left: 4 })
              }
              .width('100%')

              if (record.note) {
                Text(record.note)
                  .fontSize(FONT_CAPTION)
                  .fontColor(NEUTRAL_INK_TERTIARY)
                  .width('100%')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              // 操作链接
              if (this.isCreator(record.creatorId)) {
                Row({ space: 16 }) {
                  if (!record.endDate || record.endDate === '') {
                    Text('结束经期')
                      .fontSize(FONT_CAPTION)
                      .fontColor(BRAND_RED)
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
                    .fontSize(FONT_CAPTION)
                    .fontColor(NEUTRAL_INK_TERTIARY)
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
                .width('100%')
                .margin({ top: 2 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .border({ width: { bottom: 0.5 }, color: DIVIDER })
            .alignItems(HorizontalAlign.Start)
          },
          (record: PeriodRecord) => record.id + '_' + this.recordsRefreshTag
        )
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .border({ width: { top: 0.5 }, color: DIVIDER })
  }

  @Builder
  PregnancyRiskCard() {
    if (this.cycleStatus.currentDay > 0) {
      Column({ space: 4 }) {
        Text('今日怀孕几率')
          .fontSize(FONT_CAPTION)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .fontFamily(FONT_FAMILY_SERIF)
        Row({ space: 8 }) {
          Text(this.getRiskLabel(this.getCurrentRisk()))
            .fontSize(FONT_DISPLAY)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(this.getRiskColor(this.getCurrentRisk()))
            .fontWeight(FontWeight.Bold)
          Text(this.getRiskAdvice(this.getCurrentRisk()))
            .fontSize(FONT_CAPTION)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .margin({ top: 6 })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .border({ width: { top: 0.5 }, color: DIVIDER })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  IntimacyHistory() {
    Column({ space: 0 }) {
      Text('啪啪记录')
        .fontSize(FONT_SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontFamily(FONT_FAMILY_SERIF)
        .fontColor(NEUTRAL_INK)
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (this.recentIntimacyRecords.length === 0) {
        Text('暂无啪啪记录')
          .fontSize(FONT_CAPTION)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      } else {
        ForEach(this.recentIntimacyRecords, (record: IntimacyRecord) => {
          Row() {
            Text(record.date)
              .fontSize(FONT_BODY)
              .fontColor(NEUTRAL_INK)
              .fontFamily(FONT_FAMILY_SERIF)
              .layoutWeight(1)
            Text(`周期第${record.cycleDay}天`)
              .fontSize(FONT_CAPTION)
              .fontColor(NEUTRAL_INK_TERTIARY)
              .margin({ right: 8 })
            Text(this.getRiskLabel(record.pregnancyRisk))
              .fontSize(FONT_CAPTION)
              .fontColor(this.getRiskColor(record.pregnancyRisk))
              .backgroundColor(this.getRiskBg(record.pregnancyRisk))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            if (this.isCreator(record.creatorId)) {
              Text('删除')
                .fontSize(FONT_CAPTION)
                .fontColor(BRAND_RED)
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
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .border({ width: { bottom: 0.5 }, color: DIVIDER })
        }, (record: IntimacyRecord) => record.id + '_' + record.updatedAt)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .border({ width: { top: 0.5 }, color: DIVIDER })
  }

  @Builder
  ReminderSettings() {
    Column({ space: 0 }) {
      Text('提醒设置')
        .fontSize(FONT_SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontFamily(FONT_FAMILY_SERIF)
        .fontColor(NEUTRAL_INK)
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Row() {
        Column() {
          Text('经期前3天提醒')
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK)
          Text('提前3天通知即将来经期')
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remind3DaysBefore })
          .onChange(async (isOn: boolean) => {
            this.remind3DaysBefore = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(BRAND_RED)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      Row() {
        Column() {
          Text('经期前1天提醒')
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK)
          Text('提前1天通知即将来经期')
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remind1DayBefore })
          .onChange(async (isOn: boolean) => {
            this.remind1DayBefore = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(BRAND_RED)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      Row() {
        Column() {
          Text('排卵期提醒')
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK)
          Text('排卵日当天通知')
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remindOvulation })
          .onChange(async (isOn: boolean) => {
            this.remindOvulation = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(BRAND_RED)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      Row() {
        Column() {
          Text('易孕期提醒')
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK)
          Text('易孕窗口开始时通知')
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remindFertile })
          .onChange(async (isOn: boolean) => {
            this.remindFertile = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor(BRAND_RED)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .border({ width: { top: 0.5 }, color: DIVIDER })
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
