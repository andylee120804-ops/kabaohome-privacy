/**
 * 卡宝Home - 首页（家庭总览）— 方向 C 极简编辑
 * 纸白底 + 墨黑正文 + 卡宝红（仅 CTA）。flat 编辑风：无卡片阴影、细分隔线、锐利直角。
 */
import { curves } from '@kit.ArkUI';
import { MEMBER_COLORS, ModuleId, FontSizeMode, PAGE_TRANSITION_DURATION } from '../common/Constants';
import {
  BG_PAPER, BG_CARD, DIVIDER, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, BRAND_RED_LG,
  FONT_DISPLAY, FONT_SUBTITLE, FONT_BODY_LARGE, FONT_BODY, FONT_CAPTION, FONT_CAPTION_SM,
  FONT_FAMILY_SERIF, SPACE_MD, SPACE_LG, getModuleIconRes
} from '../common/DesignTokens';
import { formatDate, addDaysToDateStr, toDateAtLocalMidnight } from '../common/Utils';
import { FamilyMember } from '../model/FamilyMember';
import { KidEvent } from '../model/KidEvent';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { PeriodViewModel } from '../viewmodel/PeriodViewModel';
import { HealthViewModel } from '../viewmodel/HealthViewModel';
import { ALL_MODULES } from '../viewmodel/ModuleManager';
import { LocalDbService } from '../service/LocalDbService';
import { AccountType } from '../model/AccountingRecord';
import { Medication } from '../model/Medication';
import { Reminder } from '../model/Reminder';
import { AuthService } from '../service/AuthService';
import { PushService } from '../service/PushService';
import { CloudService } from '../service/CloudService';
import { TabBar } from '../components/TabBar';
import { SwipeableTodoCard } from '../components/SwipeableTodoCard';
import { IconButton } from '../components/IconButton';
import { MemberTag } from '../components/MemberTag';
import { hilog } from '@kit.PerformanceAnalysisKit';
import router from '@ohos.router';

const DOMAIN = 0x0000;
const TAG = 'Index';

interface TodoItem {
  id: string;
  moduleIcon: string;
  moduleId: string;
  moduleName: string;
  title: string;
  subtitle: string;
  timeLabel: string;
  memberName: string;
  memberColor: string;
  action: string;
  routePage: string;
  dateKey: string;
  medId: string;
  medTimeSlot: string;
  accent: boolean;
  updatedAt?: string;
}

interface DateGroup {
  dateKey: string;
  label: string;
  isToday: boolean;
  items: TodoItem[];
}

@Entry
@Component
struct Index {
  @State currentMemberIndex: number = 0;
  @State todoList: TodoItem[] = [];
  @State dateGroups: DateGroup[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State enabledModules: ModuleId[] = [];
  @State currentTab: number = 0;
  @State lastSyncTime: string = '';
  @State notificationCount: number = 0;
  @State listRefreshId: string = '0';
  @State showMemberPicker: boolean = false;
  @State pendingMedItem: TodoItem | null = null;
  @State defaultMemberId: string = '';
  @State isLargeFont: boolean = false;
  @State fontDisplay: number = FONT_DISPLAY;
  @State fontSubtitle: number = FONT_SUBTITLE;
  @State fontBodyLarge: number = FONT_BODY_LARGE;
  @State fontBody: number = FONT_BODY;
  @State fontCaption: number = FONT_CAPTION;
  @State fontCaptionSm: number = FONT_CAPTION_SM;

  private familyVm: FamilyViewModel = new FamilyViewModel();
  private periodVm: PeriodViewModel = new PeriodViewModel();
  private healthVm: HealthViewModel = new HealthViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private auth: AuthService = AuthService.getInstance();

  private ensureAuthAndRoute(): boolean {
    if (!this.db.isInitialized()) return false;
    if (!this.auth.isLoggedIn()) {
      try { router.replaceUrl({ url: 'pages/LoginPage' }); } catch (_) {}
      return false;
    }
    if (!this.auth.hasFamily()) {
      try { router.replaceUrl({ url: 'pages/FamilySetupPage' }); } catch (_) {}
      return false;
    }
    return true;
  }

  aboutToAppear(): void {
    if (this.ensureAuthAndRoute()) {
      this.loadData();
    }
  }

  onPageShow(): void {
    if (this.ensureAuthAndRoute()) {
      this.loadData();
    }
  }

  private loadData(): void {
    if (!this.db.isInitialized()) {
      return;
    }
    try {
      this.familyMembers = this.familyVm.getFamilyMembers();
      this.enabledModules = this.db.getEnabledModules().filter(id =>
        ALL_MODULES.some(m => m.id === id && m.isAvailable)
      );
      if (this.enabledModules.length === 0) {
        this.enabledModules = [ModuleId.PERIOD, ModuleId.REMINDER, ModuleId.ACCOUNTING];
      }
      const member = this.familyVm.getCurrentMember();
      this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
      if (this.isLargeFont) {
        this.fontDisplay = FONT_DISPLAY + 4;
        this.fontSubtitle = FONT_SUBTITLE + 4;
        this.fontBodyLarge = FONT_BODY_LARGE + 3;
        this.fontBody = FONT_BODY + 3;
        this.fontCaption = FONT_CAPTION + 2;
        this.fontCaptionSm = FONT_CAPTION_SM + 2;
      } else {
        this.fontDisplay = FONT_DISPLAY;
        this.fontSubtitle = FONT_SUBTITLE;
        this.fontBodyLarge = FONT_BODY_LARGE;
        this.fontBody = FONT_BODY;
        this.fontCaption = FONT_CAPTION;
        this.fontCaptionSm = FONT_CAPTION_SM;
      }
      this.notificationCount = this.computeNotificationCount();
      this.loadTodoList();
      this.listRefreshId = Date.now().toString();
    } catch (err) {
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadData failed, fallback to empty home: %{public}s', e.message);
      try {
        this.todoList = [];
        this.dateGroups = [];
        this.notificationCount = 0;
        this.listRefreshId = Date.now().toString();
      } catch (_) { }
    }
    PushService.getInstance().init();
    this.pullFreshPeriodData();
  }

  private pullFreshPeriodData(): void {
    const family = this.db.getCurrentFamily();
    if (!family) return;
    CloudService.getInstance().pullPeriodData(family.id).then((merged: number) => {
      if (merged > 0) {
        this.loadTodoList();
        this.listRefreshId = Date.now().toString();
      }
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'pullFreshPeriodData failed (non-blocking): %{public}s', err.message);
    });
  }

  private computeNotificationCount(): number {
    const todayStr = formatDate(new Date());
    let count = 0;

    const reminders = this.db.getReminders().filter(r => {
      if (r.isCompleted || !r.dueTime) return false;
      const dateStr = r.dueTime.slice(0, 10);
      return dateStr <= todayStr;
    });
    count += reminders.length;

    const medications = this.db.getMedications().filter(m => {
      if (!m.isActive) return false;
      if (m.startDate && todayStr < m.startDate) return false;
      if (m.endDate && todayStr > m.endDate) return false;
      if (!this.healthVm.canConfirmMedication(m)) return false;
      return true;
    });
    const todayLogs = this.db.getTodayLogs();
    const untaken = medications.filter(m => {
      const slots = Array.isArray(m.timeSlots) ? m.timeSlots : [];
      return !slots.every(slot =>
        todayLogs.some(l => l.medicationId === m.id && l.timeSlot === slot && (l.status === 'taken' || l.status === 'late'))
      );
    });
    count += untaken.length;

    return count;
  }

  private loadTodoList(): void {
    const today = new Date();
    const todayStr = formatDate(today);
    const items: TodoItem[] = [];
    const dismissedIds = this.db.getDismissedTodayIds();

    const weekDates: string[] = [];
    for (let i = 0; i < 7; i++) {
      weekDates.push(addDaysToDateStr(todayStr, i));
    }

    const past7Dates: string[] = [];
    for (let i = 7; i > 0; i--) {
      past7Dates.push(addDaysToDateStr(todayStr, -i));
    }

    // 周期数据 → 当天待办
    const cycleStatus = this.periodVm.getCurrentCycleStatus();
    if (cycleStatus.currentDay > 0 && !dismissedIds.includes('period_1')) {
      items.push({
        id: 'period_1', moduleIcon: '🌸', moduleId: 'period', moduleName: '周期',
        title: `姨妈周期第${cycleStatus.currentDay}天`,
        subtitle: `${this.getPhaseLabel(cycleStatus.phase)} · 预计${cycleStatus.nextPeriodDate}`,
        timeLabel: `D${cycleStatus.currentDay}`,
        memberName: '妈妈', memberColor: MEMBER_COLORS[0],
        action: '知道了', routePage: 'pages/PeriodPage', dateKey: todayStr,
        medId: '', medTimeSlot: '', accent: true
      });
    }

    // 周期提醒（reminderType === 'period'）
    const periodReminders = this.db.getReminders().filter(r =>
      r.reminderType === 'period' && !r.isCompleted && r.dueTime
    );
    for (const pr of periodReminders) {
      const prDateKey = pr.dueTime.slice(0, 10);
      const inPast7 = past7Dates.includes(prDateKey);
      if (inPast7 || prDateKey === todayStr) {
        const dismissedId = `periodrem_${pr.id}`;
        if (dismissedIds.includes(dismissedId)) continue;
        const prTitle = pr.title ?? '';
        let icon = '🌸';
        if (prTitle.includes('排卵')) icon = '⭐';
        else if (prTitle.includes('易孕')) icon = '🔶';
        const isOverdue = prDateKey < todayStr;
        items.push({
          id: dismissedId, moduleIcon: icon, moduleId: 'period', moduleName: '周期',
          title: prTitle,
          subtitle: (pr.description ?? '') + (isOverdue ? ' · 已过期' : ''),
          timeLabel: pr.dueTime ? pr.dueTime.slice(11, 16) : '',
          memberName: '妈妈', memberColor: MEMBER_COLORS[0],
          action: '知道了', routePage: 'pages/PeriodPage',
          dateKey: isOverdue ? todayStr : prDateKey,
          medId: '', medTimeSlot: '', accent: isOverdue
        });
      }
    }

    // 用药数据 → 当天待办
    const todayLogs = this.db.getTodayLogs();
    const medications = this.db.getMedications().filter(m => {
      if (!m.isActive) return false;
      if (m.startDate && todayStr < m.startDate) return false;
      if (m.endDate && todayStr > m.endDate) return false;
      return true;
    });
    for (const med of medications) {
      const member = this.familyMembers.find(m => m.id === med.forMemberId);
      const canConfirm = this.healthVm.canConfirmMedication(med);
      const medSlots = Array.isArray(med.timeSlots) ? med.timeSlots : [];
      for (const slot of medSlots) {
        const isTaken = todayLogs.some(l => l.medicationId === med.id &&
          l.timeSlot === slot && (l.status === 'taken' || l.status === 'late'));
        if (isTaken) continue;
        const slotShort = slot.length > 2 ? slot.slice(0, 2) : slot;
        items.push({
          id: `med_${med.id}_${slot}`, moduleIcon: '💊', moduleId: 'health', moduleName: '用药',
          title: `${med.medicineName} ${med.dosage}`,
          subtitle: `${member?.name ?? '家人'} · ${slot}`,
          timeLabel: slotShort,
          memberName: member?.name ?? '', memberColor: member?.color ?? MEMBER_COLORS[1],
          action: canConfirm ? '待服' : '查看', routePage: 'pages/HealthPage', dateKey: todayStr,
          medId: med.id, medTimeSlot: slot, accent: true
        });
      }
    }

    // 提醒数据（排除周期类型，包含购物）
    const reminders = this.db.getReminders().filter(r =>
      !r.isCompleted && r.dueTime && r.reminderType !== 'period'
    );
    for (const r of reminders) {
      if (dismissedIds.includes(`rem_${r.id}`)) continue;
      const dateKey = r.dueTime.slice(0, 10);
      const inPast7 = past7Dates.includes(dateKey);
      const inNext7 = dateKey >= weekDates[0] && dateKey <= weekDates[6];
      if (inPast7 || inNext7) {
        const isShopping = r.reminderType === 'shopping';
        const isOverdue = dateKey < todayStr;
        items.push({
          id: `rem_${r.id}`,
          moduleIcon: isShopping ? '🛒' : '📋',
          moduleId: isShopping ? 'shopping' : 'reminder',
          moduleName: isShopping ? '购物' : '家庭提醒',
          title: r.title,
          subtitle: isOverdue ? '已过期' : (r.description ?? ''),
          timeLabel: r.dueTime.slice(11, 16),
          memberName: '', memberColor: isShopping ? MEMBER_COLORS[4] : MEMBER_COLORS[1],
          action: '完成', routePage: 'pages/ReminderPage',
          dateKey: isOverdue ? todayStr : dateKey,
          medId: '', medTimeSlot: '', accent: isOverdue
        });
      }
    }

    // 无日期的待办提醒（归入今天）
    const noDateReminders = this.db.getReminders().filter(r =>
      !r.isCompleted && (!r.dueTime || r.dueTime === '') && r.reminderType !== 'period'
    );
    for (const r of noDateReminders) {
      if (dismissedIds.includes(`rem_${r.id}`)) continue;
      const isShopping = r.reminderType === 'shopping';
      items.push({
        id: `rem_${r.id}`,
        moduleIcon: isShopping ? '🛒' : '📋',
        moduleId: isShopping ? 'shopping' : 'reminder',
        moduleName: isShopping ? '购物' : '家庭提醒',
        title: r.title,
        subtitle: '待安排时间',
        timeLabel: '',
        memberName: '', memberColor: isShopping ? MEMBER_COLORS[4] : MEMBER_COLORS[1],
        action: '完成', routePage: 'pages/ReminderPage', dateKey: todayStr,
        medId: '', medTimeSlot: '', accent: false
      });
    }

    // 孩子事项（近7日 + 过期归入今天）
    const kidEvents = this.db.getKidEvents().filter(e => !e.isCompleted);
    for (const event of kidEvents) {
      if (dismissedIds.includes(`kid_${event.id}`)) continue;
      const eventDate = event.eventTime.slice(0, 10);
      const inPast7 = past7Dates.includes(eventDate);
      const inNext7 = eventDate >= todayStr && eventDate <= weekDates[6];
      if (inPast7 || inNext7) {
        const member = this.familyMembers.find(m => m.id === event.forMemberId);
        const isOverdue = eventDate < todayStr;
        items.push({
          id: `kid_${event.id}`, moduleIcon: '📚', moduleId: 'kids', moduleName: '事项',
          title: `${member?.name ?? '孩子'} · ${event.title}`,
          subtitle: eventDate.slice(5) + (isOverdue ? ' · 已过期' : ''),
          timeLabel: event.eventTime.slice(11, 16),
          memberName: member?.name ?? '', memberColor: member?.color ?? MEMBER_COLORS[2],
          action: '完成', routePage: 'pages/KidsPage',
          dateKey: isOverdue ? todayStr : eventDate,
          medId: '', medTimeSlot: '', accent: isOverdue
        });
      }
    }

    // 记账数据（当天）
    const accountingRecords = this.db.getAccountingRecords();
    const todayRecords = accountingRecords.filter(r => r.date === todayStr);
    if (todayRecords.length > 0 && !dismissedIds.includes('accounting_today')) {
      const todayExpense = todayRecords.filter(r => r.type === AccountType.EXPENSE).reduce((sum, r) => sum + r.amount, 0);
      items.push({
        id: 'accounting_today', moduleIcon: '💰', moduleId: 'accounting', moduleName: '记账',
        title: `今日支出 ¥${todayExpense.toFixed(0)}`,
        subtitle: `${todayRecords.length}笔记录`,
        timeLabel: '',
        memberName: '', memberColor: MEMBER_COLORS[1],
        action: '知道了', routePage: 'pages/AccountingPage', dateKey: todayStr,
        medId: '', medTimeSlot: '', accent: false
      });
    }

    // 按日期分组
    const groups: DateGroup[] = [];
    const weekDayLabels: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    for (let i = 0; i < 7; i++) {
      const dk = weekDates[i];
      const dayItems = items.filter(it => it.dateKey === dk);
      if (dayItems.length === 0) continue;
      const labelDate = toDateAtLocalMidnight(dk);
      const weekday = weekDayLabels[labelDate.getDay()];
      let label: string;
      if (i === 0) label = `TODAY · ${weekday}`;
      else if (i === 1) label = `TOMORROW · ${weekday}`;
      else label = `${weekday} · ${dk.slice(5)}`;
      groups.push({ dateKey: dk, label, isToday: i === 0, items: dayItems });
    }

    // 空数据引导
    if (groups.length === 0 && !this.db.isWelcomeDismissed()) {
      items.push({
        id: 'welcome', moduleIcon: '🏠', moduleId: '', moduleName: '',
        title: '欢迎使用卡宝Home！', subtitle: '点击各模块开始记录家庭生活',
        timeLabel: '',
        memberName: '', memberColor: MEMBER_COLORS[1],
        action: '开始', routePage: 'pages/SettingsPage', dateKey: todayStr,
        medId: '', medTimeSlot: '', accent: false
      });
      groups.push({ dateKey: todayStr, label: `TODAY · ${weekDayLabels[new Date().getDay()]}`, isToday: true, items });
    }

    this.todoList = items;
    this.dateGroups = groups;
  }

  private getTodayWeekday(): string {
    const labels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return labels[new Date().getDay()];
  }

  private getTodayDateStr(): string {
    const today = new Date();
    return `${today.getMonth() + 1}月 ${today.getDate()}日`;
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionEnter({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).opacity(1)
    PageTransitionExit({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).opacity(0)
  }

  build() {
    Stack() {
      Column() {
        this.TitleBar()
        this.MemberTabs()
        this.TodoList()
        TabBar({
          enabledModules: this.enabledModules,
          currentTab: this.currentTab,
          onTabChange: (index: number) => {
            this.currentTab = index;
            this.navigateByTab(index);
          }
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(BG_PAPER)

      if (this.showMemberPicker) {
        this.MemberPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      if (this.db.isInitialized() && this.auth.isLoggedIn() && this.auth.hasFamily()) {
        this.loadData();
      }
    })
  }

  @Builder
  TitleBar() {
    Row() {
      // 日期块（编辑风：小标签 + 大衬线日期）
      Column() {
        Text(this.getTodayWeekday())
          .fontSize(this.fontCaptionSm)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .fontFamily(FONT_FAMILY_SERIF)
          .letterSpacing(2)
        Text(this.getTodayDateStr())
          .fontSize(this.fontDisplay)
          .fontColor(NEUTRAL_INK)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      if (this.lastSyncTime) {
        Text(`同步 ${this.lastSyncTime.slice(11, 16)}`)
          .fontSize(this.fontCaptionSm)
          .fontColor(NEUTRAL_INK_TERTIARY)
          .margin({ right: SPACE_MD })
      }

      // 铃铛图标 + 角标（长按进入图标预览页）
      Column() {
        IconButton({
          icon: 'bell',
          badge: this.notificationCount,
          onTap: () => {
            this.db.saveLastNotificationAckTime(new Date().toISOString());
            router.pushUrl({ url: 'pages/NotificationCenterPage' });
          }
        })
      }
      .gesture(
        LongPressGesture().onAction(() => {
          router.pushUrl({ url: 'pages/IconPreviewPage' });
        })
      )
    }
    .width('100%')
    .padding({ left: SPACE_LG, right: SPACE_LG, top: 16, bottom: 12 })
    .backgroundColor(BG_PAPER)
  }

  @Builder
  MemberTabs() {
    Scroll() {
      Row({ space: SPACE_LG }) {
        ForEach(this.familyMembers, (member: FamilyMember, index: number) => {
          MemberTag({
            member: member,
            isSelected: this.currentMemberIndex === index,
            size: 'normal',
            onSelected: () => { this.currentMemberIndex = index as number; }
          })
        }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .padding({ left: SPACE_LG, right: SPACE_LG, top: 4, bottom: 0 })
    .backgroundColor(BG_PAPER)
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
  }

  @Builder
  TodoList() {
    Scroll() {
      Column({ space: 0 }) {
        // 区块标题
        Row() {
          Text('近7日事项')
            .fontSize(this.fontSubtitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
          Blank()
          Text(`${this.todoList.length} 项`)
            .fontSize(this.fontCaption)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .fontFamily(FONT_FAMILY_SERIF)
        }
        .width('100%')
        .padding({ left: SPACE_LG, right: SPACE_LG, top: 20, bottom: 8 })

        // 按日期分组渲染
        ForEach(this.dateGroups, (group: DateGroup) => {
          Column({ space: 0 }) {
            // 日期标签（小号衬线大写）
            Text(group.label)
              .fontSize(this.fontCaptionSm)
              .fontColor(group.isToday ? BRAND_RED : NEUTRAL_INK_TERTIARY)
              .fontFamily(FONT_FAMILY_SERIF)
              .fontWeight(FontWeight.Medium)
              .letterSpacing(1)
              .padding({ left: SPACE_LG, right: SPACE_LG, top: 16, bottom: 4 })

            // 该日事项
            ForEach(group.items, (item: TodoItem) => {
              this.TodoCard(item)
            }, (item: TodoItem) => item.id + '_' + (item.updatedAt ?? ''))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (group: DateGroup) => group.dateKey + '_' + this.listRefreshId)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 16 })
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  TodoCard(item: TodoItem) {
    SwipeableTodoCard({
      moduleIcon: item.moduleIcon,
      iconRes: item.moduleId ? getModuleIconRes(item.moduleId) : null,
      title: item.title,
      subtitle: item.subtitle,
      timeLabel: item.timeLabel,
      action: item.action,
      primaryColor: BRAND_RED,
      accent: item.accent,
      disableSwipe: item.action === '查看' || item.action === '开始',
      autoTriggerOnSwipe: true,
      onTap: () => {
        if (!item.routePage) return;
        if (item.id.startsWith('rem_')) {
          const rid = item.id.replace('rem_', '');
          router.pushUrl({ url: item.routePage, params: { reminderId: rid, openDetail: true } });
          return;
        }
        router.pushUrl({ url: item.routePage });
      },
      onComplete: () => {
        if (item.action === '待服') {
          this.confirmMedicationDirect(item);
          return;
        }
        this.confirmAction(item);
      },
      onPrimaryAction: () => {
        if (item.action === '待服') {
          this.confirmMedicationDirect(item);
          return;
        }
        if (item.action === '查看') {
          if (item.routePage) {
            router.pushUrl({ url: item.routePage });
          }
          return;
        }
        this.confirmAction(item);
      }
    })
  }

  /** 打开服药人选择器（保留：长按等高级路径仍可用） */
  private openMedicationPicker(item: TodoItem): void {
    this.pendingMedItem = item;
    const med = this.db.getMedications().find((m: Medication) => m.id === item.medId);
    this.defaultMemberId = med?.forMemberId ?? '';
    this.showMemberPicker = true;
  }

  /** 服药直接确认：服药人=Medication.forMemberId，无需弹窗 */
  private confirmMedicationDirect(item: TodoItem): void {
    if (!item.medId || !item.medTimeSlot) return;
    const med = this.db.getMedications().find((m: Medication) => m.id === item.medId);
    if (!med) return;
    this.healthVm.confirmTaken(item.medId, item.medTimeSlot, med.forMemberId)
      .then(() => { this.loadData(); })
      .catch((e: Error) => { console.error('confirmMedicationDirect failed:', e?.message); });
  }

  private getOtherMedicationMembers(): FamilyMember[] {
    return this.familyMembers.filter((member: FamilyMember) => member.id !== this.defaultMemberId);
  }

  /** 统一确认入口 */
  private confirmAction(item: TodoItem): void {
    this.handleQuickConfirm(item).catch((e: Error) => {
      console.error('handleQuickConfirm failed:', e?.message);
    });
  }

  @Builder
  MemberPickerOverlay() {
    Column() {
      Column() {
        // 标题
        Text('谁服了药？')
          .fontSize(this.fontSubtitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(NEUTRAL_INK)
          .fontFamily(FONT_FAMILY_SERIF)
        Text(this.pendingMedItem?.title ?? '')
          .fontSize(this.fontBody)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .margin({ bottom: 16, top: 4 })

        // 默认服药人
        if (this.defaultMemberId) {
          ForEach(this.familyMembers.filter((member: FamilyMember) => member.id === this.defaultMemberId), (defaultMember: FamilyMember) => {
            Row() {
              Text(defaultMember.avatar).fontSize(22).margin({ right: 10 })
              Column() {
                Row() {
                  Text(defaultMember.name)
                    .fontSize(this.fontBodyLarge)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                  Text(' 默认')
                    .fontSize(this.fontCaptionSm)
                    .fontColor(BRAND_RED_LG)
                    .border({ width: 0.5, color: BRAND_RED_LG })
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    .margin({ left: 6 })
                }
                Text('该用药的服药人，点这里直接确认')
                  .fontSize(this.fontCaption).fontColor(Color.White).margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('✓').fontSize(20).fontColor(Color.White)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(NEUTRAL_INK)
            .margin({ bottom: 12 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(async () => {
              if (!this.pendingMedItem) return;
              await this.healthVm.confirmTaken(
                this.pendingMedItem.medId,
                this.pendingMedItem.medTimeSlot,
                defaultMember.id
              );
              this.showMemberPicker = false;
              this.pendingMedItem = null;
              this.defaultMemberId = '';
              this.loadData();
            })
          }, (defaultMember: FamilyMember) => defaultMember.id + '_' + defaultMember.updatedAt)
        }

        if (this.familyMembers.length > 1) {
          Text('或选择其他人')
            .fontSize(this.fontCaption).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 8 })
        }

        ForEach(this.getOtherMedicationMembers(), (member: FamilyMember) => {
          Row() {
            Text(member.avatar).fontSize(20).margin({ right: 10 })
            Column() {
              Text(member.name)
                .fontSize(this.fontBody).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
              Text('点击确认是此人所服')
                .fontSize(this.fontCaption).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(BG_PAPER)
          .border({ width: { bottom: 0.5 }, color: DIVIDER })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(async () => {
            if (!this.pendingMedItem) return;
            await this.healthVm.confirmTaken(
              this.pendingMedItem.medId,
              this.pendingMedItem.medTimeSlot,
              member.id
            );
            this.showMemberPicker = false;
            this.pendingMedItem = null;
            this.defaultMemberId = '';
            this.loadData();
          })
        }, (member: FamilyMember) => member.id + '_' + member.updatedAt)

        // 取消
        Text('取消')
          .fontSize(this.fontBody)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .padding({ top: 16, bottom: 8 })
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showMemberPicker = false;
            this.pendingMedItem = null;
            this.defaultMemberId = '';
          })
      }
      .width('85%')
      .padding(SPACE_LG)
      .backgroundColor(BG_CARD)
      .border({ width: 0.5, color: DIVIDER })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showMemberPicker = false;
      this.pendingMedItem = null;
      this.defaultMemberId = '';
    })
  }

  /** 首页快捷确认：所有待办/提醒事项通用 */
  private async handleQuickConfirm(item: TodoItem): Promise<void> {
    if (item.id === 'welcome') {
      await this.db.setWelcomeDismissed();
      await this.db.addDismissedTodayId('welcome');
      if (item.routePage) {
        router.pushUrl({ url: item.routePage });
      }
      return;
    }
    if (item.id.startsWith('med_') && item.medId && item.medTimeSlot) {
      if (item.action !== '待服') return;
      this.confirmMedicationDirect(item);
      return;
    } else if (item.id.startsWith('rem_')) {
      const remId = item.id.replace('rem_', '');
      const reminders = this.db.getReminders();
      const r = reminders.find(rem => rem.id === remId);
      if (r) {
        const now = new Date().toISOString();
        const updated: Reminder = {
          id: r.id, familyId: r.familyId, creatorId: r.creatorId,
          visibility: r.visibility, visibleMembers: r.visibleMembers,
          version: r.version + 1, createdAt: r.createdAt, updatedAt: now,
          title: r.title, description: r.description, reminderType: r.reminderType,
          dueTime: r.dueTime, isRecurring: r.isRecurring, recurrenceRule: r.recurrenceRule,
          isCompleted: true, completedAt: now, reminderSettings: r.reminderSettings
        };
        await this.db.updateReminder(updated);
        this.loadData();
      }
    } else if (item.id.startsWith('kid_')) {
      const eventId = item.id.replace('kid_', '');
      const events = this.db.getKidEvents();
      const e = events.find(ev => ev.id === eventId);
      if (e) {
        const now = new Date().toISOString();
        const updated: KidEvent = {
          id: e.id, familyId: e.familyId, creatorId: e.creatorId,
          visibility: e.visibility, visibleMembers: [...e.visibleMembers],
          version: e.version + 1, createdAt: e.createdAt, updatedAt: now,
          forMemberId: e.forMemberId, title: e.title, description: e.description,
          eventType: e.eventType, eventTime: e.eventTime, location: e.location,
          isRecurring: e.isRecurring, recurrenceRule: e.recurrenceRule,
          reminderSettings: [...e.reminderSettings], isSharedWith: [...e.isSharedWith],
          isCompleted: true, completedAt: now
        };
        await this.db.updateKidEvent(updated);
        this.loadData();
      }
    } else {
      await this.db.addDismissedTodayId(item.id);
      this.loadData();
    }
  }

  private navigateByTab(index: number): void {
    if (index === 0) return;

    const lastTab = this.enabledModules.length + 1;
    if (index === lastTab) {
      router.pushUrl({ url: 'pages/SettingsPage' });
      return;
    }

    const moduleIndex = index - 1;
    if (moduleIndex < this.enabledModules.length) {
      const moduleId = this.enabledModules[moduleIndex];
      const pageMap: Record<string, string> = {
        [ModuleId.PERIOD]: 'pages/PeriodPage',
        [ModuleId.HEALTH]: 'pages/HealthPage',
        [ModuleId.KIDS]: 'pages/KidsPage',
        [ModuleId.REMINDER]: 'pages/ReminderPage',
        [ModuleId.LOCATION]: 'pages/LocationPage',
        [ModuleId.ALBUM]: 'pages/AlbumPage',
        [ModuleId.MEMO]: 'pages/MemoPage',
        [ModuleId.ACCOUNTING]: 'pages/AccountingPage'
      };
      const url = pageMap[moduleId];
      if (url) {
        router.pushUrl({ url });
      }
    }
  }

  private getPhaseLabel(phase: string): string {
    const map: Record<string, string> = {
      'menstrual': '经期中', 'fertile': '易孕期', 'ovulation': '排卵日',
      'safe_before': '安全期', 'safe_after': '安全期', 'unknown': ''
    };
    return map[phase] ?? '';
  }
}
