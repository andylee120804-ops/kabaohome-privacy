/**
 * 卡宝Home - 首页（家庭总览）
 */
import { curves } from '@kit.ArkUI';
import { APP_NAME, MEMBER_COLORS, ModuleId, ThemeColor, THEME_PALETTES, Visibility, FontSizeMode , PAGE_TRANSITION_DURATION } from '../common/Constants';
import { BRAND_CORAL, BG_PAPER, BG_CARD, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY, BORDER_SUBTLE, SEMANTIC_ERROR, SHADOW_CARD, RADIUS_MD, RADIUS_PILL, FONT_TITLE, FONT_SUBTITLE, FONT_BODY, FONT_CAPTION, FONT_CAPTION_SM } from '../common/DesignTokens';
import { formatDate, generateId, addDaysToDateStr, toDateAtLocalMidnight } from '../common/Utils';
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
import { hilog } from '@kit.PerformanceAnalysisKit';
import router from '@ohos.router';

const DOMAIN = 0x0000;
const TAG = 'Index';

interface TodoItem {
  id: string;
  moduleIcon: string;
  moduleName: string;
  title: string;
  subtitle: string;
  memberName: string;
  memberColor: string;
  action: string;
  routePage: string;
  dateKey: string;
  medId: string;
  medTimeSlot: string;
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
  @State themeColor: string = BRAND_CORAL;
  @State themeLightBg: string = BG_PAPER;
  @State notificationCount: number = 0;
  @State listRefreshId: string = '0';
  @State showMemberPicker: boolean = false;
  @State pendingMedItem: TodoItem | null = null;
  @State defaultMemberId: string = '';
  // 字体模式：大字体时放大首页各级文字（切换在「我的-字体模式」，首页此前不响应导致「切换无变化」）
  @State isLargeFont: boolean = false;
  @State fontTitle: number = FONT_TITLE;
  @State fontSubtitle: number = FONT_SUBTITLE;
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
      return; // LocalDbService 未初始化，不加载
    }
    try {
      this.familyMembers = this.familyVm.getFamilyMembers();
      this.enabledModules = this.db.getEnabledModules().filter(id =>
        ALL_MODULES.some(m => m.id === id && m.isAvailable)
      );
      if (this.enabledModules.length === 0) {
        this.enabledModules = [ModuleId.PERIOD, ModuleId.REMINDER, ModuleId.ACCOUNTING];
      }
      const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
      this.themeColor = palette.primary;
      this.themeLightBg = palette.lightBg;
      const member = this.familyVm.getCurrentMember();
      this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
      if (this.isLargeFont) {
        this.fontTitle = FONT_TITLE + 4;
        this.fontSubtitle = FONT_SUBTITLE + 4;
        this.fontBody = FONT_BODY + 3;
        this.fontCaption = FONT_CAPTION + 2;
        this.fontCaptionSm = FONT_CAPTION_SM + 2;
      } else {
        this.fontTitle = FONT_TITLE;
        this.fontSubtitle = FONT_SUBTITLE;
        this.fontBody = FONT_BODY;
        this.fontCaption = FONT_CAPTION;
        this.fontCaptionSm = FONT_CAPTION_SM;
      }
      this.notificationCount = this.computeNotificationCount();
      this.loadTodoList();
      this.listRefreshId = Date.now().toString();
    } catch (err) {
      // 首页数据加载失败必须降级而不是崩溃（应用无法进入 = 审核致命问题）。
      // 记录现场（数据形态/来源）便于后续排查，同时保证首页壳层仍可渲染。
      const e = err as Error;
      hilog.error(DOMAIN, TAG, 'loadData failed, fallback to empty home: %{public}s', e.message);
      try {
        // 兜底：渲染空首页，保证应用可进入
        this.todoList = [];
        this.dateGroups = [];
        this.notificationCount = 0;
        this.listRefreshId = Date.now().toString();
      } catch (_) { /* 兜底赋值也不应再抛 */ }
    }
    // 初始化推送服务（获取 Push Kit 令牌 + 注册到云端），best-effort
    PushService.getInstance().init();
    this.pullFreshPeriodData();
  }

  /** 成员颜色安全取值：云端/本地记录可能缺失 color，兜底用默认色，避免渲染崩溃 */
  private safeMemberColor(member: FamilyMember): string {
    const c = member.color;
    return (typeof c === 'string' && c.length > 0 && c.startsWith('#')) ? c : MEMBER_COLORS[1];
  }

  // 首页展示「姨妈周期第X天」，打开页面时主动拉取云端最新周期数据，
  // 否则其他设备新增的记录要等前后台切换同步才会到达，天数会显示不一致
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

    // 已过期 + 今日到期的未完成提醒
    const reminders = this.db.getReminders().filter(r => {
      if (r.isCompleted || !r.dueTime) return false;
      const dateStr = r.dueTime.slice(0, 10);
      return dateStr <= todayStr;
    });
    count += reminders.length;

    // 今日未服药物（有效期内）- 仅统计我有权限确认的
    const medications = this.db.getMedications().filter(m => {
      if (!m.isActive) return false;
      if (m.startDate && todayStr < m.startDate) return false;
      if (m.endDate && todayStr > m.endDate) return false;
      if (!this.healthVm.canConfirmMedication(m)) return false;
      return true;
    });
    const todayLogs = this.db.getTodayLogs();
    const untaken = medications.filter(m => {
      // timeSlots 可能为缺失/空串/非数组（旧版本记录或异常数据），一律视为无待服时段
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

    // 计算近7日日期范围
    const weekDates: string[] = [];
    for (let i = 0; i < 7; i++) {
      weekDates.push(addDaysToDateStr(todayStr, i));
    }

    // 计算过去7天的日期（用于显示过期提醒）
    const past7Dates: string[] = [];
    for (let i = 7; i > 0; i--) {
      past7Dates.push(addDaysToDateStr(todayStr, -i));
    }

    // 从周期数据生成待办（当天）
    const cycleStatus = this.periodVm.getCurrentCycleStatus();
    if (cycleStatus.currentDay > 0 && !dismissedIds.includes('period_1')) {
      items.push({
        id: 'period_1', moduleIcon: '🌸', moduleName: '周期',
        title: `姨妈周期第${cycleStatus.currentDay}天`,
        subtitle: `${this.getPhaseLabel(cycleStatus.phase)} · 预计${cycleStatus.nextPeriodDate}`,
        memberName: '妈妈', memberColor: MEMBER_COLORS[0],
        action: '知道了', routePage: 'pages/PeriodPage', dateKey: todayStr,
        medId: '', medTimeSlot: ''
      });
    }

    // 从周期提醒（reminderType === 'period'）生成临近提醒卡片
    const periodReminders = this.db.getReminders().filter(r =>
      r.reminderType === 'period' && !r.isCompleted && r.dueTime
    );
    for (const pr of periodReminders) {
      const prDateKey = pr.dueTime.slice(0, 10);
      // 只显示已过期（最多7天前）和当天的周期提醒卡片；未到期不上屏，等到期当天才弹出
      const inPast7 = past7Dates.includes(prDateKey);
      if (inPast7 || prDateKey === todayStr) {
        const dismissedId = `periodrem_${pr.id}`;
        if (dismissedIds.includes(dismissedId)) continue;
        // 根据提醒标题判断图标
        const prTitle = pr.title ?? '';
        let icon = '🌸';
        if (prTitle.includes('排卵')) icon = '⭐';
        else if (prTitle.includes('易孕')) icon = '🔶';
        items.push({
          id: dismissedId, moduleIcon: icon, moduleName: '周期',
          title: prTitle,
          subtitle: (pr.description ?? '') + (prDateKey < todayStr ? ' · 已过期' : ''),
          memberName: '妈妈', memberColor: MEMBER_COLORS[0],
          action: '知道了', routePage: 'pages/PeriodPage',
          dateKey: prDateKey < todayStr ? todayStr : prDateKey,
          medId: '', medTimeSlot: ''
        });
      }
    }

    // 从用药数据生成待办（当天有效期内、按时段展示）
    const todayLogs = this.db.getTodayLogs();
    const medications = this.db.getMedications().filter(m => {
      if (!m.isActive) return false;
      // 过滤有效期：startDate <= 今天 <= endDate（无endDate表示长期有效）
      if (m.startDate && todayStr < m.startDate) return false;
      if (m.endDate && todayStr > m.endDate) return false;
      return true;
    });
    for (const med of medications) {
      const member = this.familyMembers.find(m => m.id === med.forMemberId);
      // 当前用户是否有权限确认（创建人或被指派的服药人）
      const canConfirm = this.healthVm.canConfirmMedication(med);
      // timeSlots 可能为缺失/空串/非数组（旧版本记录或异常数据），防御性跳过
      const medSlots = Array.isArray(med.timeSlots) ? med.timeSlots : [];
      for (const slot of medSlots) {
        const isTaken = todayLogs.some(l => l.medicationId === med.id &&
          l.timeSlot === slot && (l.status === 'taken' || l.status === 'late'));
        // 已服药物不再显示在首页待办列表
        if (isTaken) continue;
        items.push({
          id: `med_${med.id}_${slot}`, moduleIcon: '💊', moduleName: '用药',
          title: `${med.medicineName} ${med.dosage}`,
          subtitle: `${member?.name ?? '家人'} · ${slot}`,
          memberName: member?.name ?? '', memberColor: member?.color ?? MEMBER_COLORS[1],
          action: canConfirm ? '待服' : '查看', routePage: 'pages/HealthPage', dateKey: todayStr,
          medId: med.id, medTimeSlot: slot
        });
      }
    }

    // 从提醒数据生成待办（已过期 + 未来7天，排除周期类型，包含购物）
    const reminders = this.db.getReminders().filter(r =>
      !r.isCompleted && r.dueTime && r.reminderType !== 'period'
    );
    for (const r of reminders) {
      if (dismissedIds.includes(`rem_${r.id}`)) continue;
      const dateKey = r.dueTime.slice(0, 10);
      // 显示已过期（最多7天前）和未来7天内的提醒
      const inPast7 = past7Dates.includes(dateKey);
      const inNext7 = dateKey >= weekDates[0] && dateKey <= weekDates[6];
      if (inPast7 || inNext7) {
        const isShopping = r.reminderType === 'shopping';
        items.push({
          id: `rem_${r.id}`,
          moduleIcon: isShopping ? '🛒' : '📋',
          moduleName: isShopping ? '购物' : '家庭提醒',
          title: r.title,
          subtitle: r.dueTime.slice(11, 16) + (dateKey < todayStr ? ' · 已过期' : ''),
          memberName: '', memberColor: isShopping ? MEMBER_COLORS[4] : MEMBER_COLORS[1],
          action: '完成', routePage: 'pages/ReminderPage',
          dateKey: dateKey < todayStr ? todayStr : dateKey,
          medId: '', medTimeSlot: ''
        });
      }
    }

    // 额外显示无日期的待办提醒（归入今天，排除周期类型，包含购物）
    const noDateReminders = this.db.getReminders().filter(r =>
      !r.isCompleted && (!r.dueTime || r.dueTime === '') && r.reminderType !== 'period'
    );
    for (const r of noDateReminders) {
      if (dismissedIds.includes(`rem_${r.id}`)) continue;
      const isShopping = r.reminderType === 'shopping';
      items.push({
        id: `rem_${r.id}`,
        moduleIcon: isShopping ? '🛒' : '📋',
        moduleName: isShopping ? '购物' : '家庭提醒',
        title: r.title,
        subtitle: '待安排时间',
        memberName: '', memberColor: isShopping ? MEMBER_COLORS[4] : MEMBER_COLORS[1],
        action: '完成', routePage: 'pages/ReminderPage', dateKey: todayStr,
        medId: '', medTimeSlot: ''
      });
    }

    // 从孩子事项生成待办（近7日 + 过期事项归入今天，排除已完成）
    const kidEvents = this.db.getKidEvents().filter(e => !e.isCompleted);
    for (const event of kidEvents) {
      if (dismissedIds.includes(`kid_${event.id}`)) continue;
      const eventDate = event.eventTime.slice(0, 10);
      const inPast7 = past7Dates.includes(eventDate);
      const inNext7 = eventDate >= todayStr && eventDate <= weekDates[6];
      if (inPast7 || inNext7) {
        const member = this.familyMembers.find(m => m.id === event.forMemberId);
        items.push({
          id: `kid_${event.id}`, moduleIcon: '📚', moduleName: '事项',
          title: `${member?.name ?? '孩子'} · ${event.title}`,
          subtitle: event.eventTime.slice(0, 16).replace('T', ' ') + (eventDate < todayStr ? ' · 已过期' : ''),
          memberName: member?.name ?? '', memberColor: member?.color ?? MEMBER_COLORS[2],
          action: '完成', routePage: 'pages/KidsPage',
          dateKey: eventDate < todayStr ? todayStr : eventDate,
          medId: '', medTimeSlot: ''
        });
      }
    }

    // 从记账数据生成待办（当天）
    const accountingRecords = this.db.getAccountingRecords();
    const todayRecords = accountingRecords.filter(r => r.date === todayStr);
    if (todayRecords.length > 0 && !dismissedIds.includes('accounting_today')) {
      const todayExpense = todayRecords.filter(r => r.type === AccountType.EXPENSE).reduce((sum, r) => sum + r.amount, 0);
      items.push({
        id: 'accounting_today', moduleIcon: '💰', moduleName: '记账',
        title: `今日支出 ¥${todayExpense.toFixed(0)}`,
        subtitle: `${todayRecords.length}笔记录`,
        memberName: '', memberColor: MEMBER_COLORS[1],
        action: '知道了', routePage: 'pages/AccountingPage', dateKey: todayStr,
        medId: '', medTimeSlot: ''
      });
    }

    // 按日期分组，只保留有事的日子
    const groups: DateGroup[] = [];
    const weekDayLabels: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    for (let i = 0; i < 7; i++) {
      const dk = weekDates[i];
      const dayItems = items.filter(it => it.dateKey === dk);
      if (dayItems.length === 0) continue;
      const labelDate = toDateAtLocalMidnight(dk);
      let label = `${weekDayLabels[labelDate.getDay()]} ${dk.slice(5)}`;
      if (i === 0) label = `今天 ${dk.slice(5)}`;
      else if (i === 1) label = `明天 ${dk.slice(5)}`;
      groups.push({ dateKey: dk, label, isToday: i === 0, items: dayItems });
    }

    // 如果没有数据且欢迎卡未关闭则展示默认引导
    if (groups.length === 0 && !this.db.isWelcomeDismissed()) {
      items.push({
        id: 'welcome', moduleIcon: '🏠', moduleName: '',
        title: '欢迎使用卡宝Home！', subtitle: '点击各模块开始记录家庭生活',
        memberName: '', memberColor: MEMBER_COLORS[1],
        action: '开始', routePage: 'pages/SettingsPage', dateKey: todayStr,
        medId: '', medTimeSlot: ''
      });
      groups.push({ dateKey: todayStr, label: `今天 ${todayStr.slice(5)}`, isToday: true, items });
    }

    this.todoList = items;
    this.dateGroups = groups;
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
          themeColor: this.themeColor,
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
      .backgroundColor(this.themeLightBg)

      if (this.showMemberPicker) {
        this.MemberPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      // 组件可见时刷新数据（从子页面返回时也会触发）
      if (this.db.isInitialized() && this.auth.isLoggedIn() && this.auth.hasFamily()) {
        this.loadData();
      }
    })
  }

  @Builder
  TitleBar() {
    Row() {
      Text(APP_NAME)
        .fontSize(this.fontTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themeColor)
      Blank()
      if (this.lastSyncTime) {
        Text(`同步 ${this.lastSyncTime.slice(11, 16)}`)
          .fontSize(this.fontCaptionSm).fontColor(NEUTRAL_INK_TERTIARY).margin({ right: 12 })
      }
      Stack() {
        Text('🔔').fontSize(20)
        if (this.notificationCount > 0) {
          Row() {
            Text(this.notificationCount > 99 ? '99+' : `${this.notificationCount}`)
              .fontSize(9).fontColor(Color.White).fontWeight(FontWeight.Bold)
          }
          .backgroundColor(SEMANTIC_ERROR)
          .borderRadius(8)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .position({ x: 16, y: -4 })
        }
      }
      .width(28).height(24)
      .onClick(() => {
        this.db.saveLastNotificationAckTime(new Date().toISOString());
        router.pushUrl({ url: 'pages/NotificationCenterPage' });
      })
      .gesture(
        LongPressGesture().onAction(() => {
          router.pushUrl({ url: 'pages/IconPreviewPage' });
        })
      )
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 8 })
    .backgroundColor(BG_CARD)
  }

  @Builder
  MemberTabs() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.familyMembers, (member: FamilyMember, index: number) => {
          Row({ space: 7 }) {
            if (this.currentMemberIndex === index) {
              Text(member.avatar).fontSize(13).fontColor(Color.White)
            }
            Text(member.name)
              .fontSize(this.fontCaption)
              .fontColor(this.currentMemberIndex === index ? Color.White : NEUTRAL_INK_SECONDARY)
          }
          .backgroundColor(this.currentMemberIndex === index ? this.safeMemberColor(member) : BG_PAPER)
          .borderRadius(RADIUS_PILL)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .shadow(this.currentMemberIndex === index ? { radius: 8, color: '#33' + this.safeMemberColor(member).replace('#', ''), offsetX: 0, offsetY: 2 } : { radius: 0, color: Color.Transparent })
          .onClick(() => { this.currentMemberIndex = index as number; })
        }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .padding({ left: 20, right: 20, top: 4, bottom: 10 })
    .backgroundColor(BG_CARD)
  }

  @Builder
  TodoList() {
    Scroll() {
      Column({ space: 0 }) {
        // 分隔
        Row()
          .width('88%')
          .height(0.5)
          .backgroundColor(BORDER_SUBTLE)
          .margin({ left: 20 })
          .opacity(0.8)

        // 标题
        Row() {
          Text('📌 近7日事项')
            .fontSize(this.fontTitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
          Text(`${this.todoList.length}项`)
            .fontSize(this.fontCaption)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

        // 按日期分组渲染（空日期不显示）
        ForEach(this.dateGroups, (group: DateGroup) => {
          Column({ space: 6 }) {
            // 日期标签
            Row() {
              Text(group.label)
                .fontSize(this.fontCaption)
                .fontWeight(FontWeight.Medium)
                .fontColor(group.isToday ? this.themeColor : NEUTRAL_INK_TERTIARY)
              if (group.isToday) {
                Row()
                  .width(6).height(6).borderRadius(3)
                  .backgroundColor(this.themeColor)
                  .margin({ left: 6 })
              }
            }

            // 该日事项卡片
            ForEach(group.items, (item: TodoItem) => {
              this.TodoCard(item)
            }, (item: TodoItem) => item.id + '_' + (item.updatedAt ?? ''))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 8 })
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
      title: item.title,
      subtitle: item.subtitle,
      action: item.action,
      primaryColor: this.themeColor,
      disableSwipe: item.action === '查看' || item.action === '开始',
      // 所有可确认动作都支持左滑自动触发
      // 待服药也启用：action='待服' 本身意味着当前用户是创建人或被指派服药人（见 canConfirmMedication）
      // 服药人直接取 med.forMemberId，无需再弹选择器
      autoTriggerOnSwipe: true,
      onTap: () => {
        if (!item.routePage) return;
        // 提醒类卡片：携带 reminderId，直接打开目标页详情弹窗
        if (item.id.startsWith('rem_')) {
          const rid = item.id.replace('rem_', '');
          router.pushUrl({ url: item.routePage, params: { reminderId: rid, openDetail: true } });
          return;
        }
        router.pushUrl({ url: item.routePage });
      },
      onComplete: () => {
        // 左滑触发完成 - 所有动作直接确认，无弹窗
        // 服药：直接以 med.forMemberId 为服药人确认（权限已在生成卡片时校验）
        if (item.action === '待服') {
          this.confirmMedicationDirect(item);
          return;
        }
        this.confirmAction(item);
      },
      onPrimaryAction: () => {
        // 右侧按钮点击：行为与左滑一致
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

  /** 统一确认入口：包装 async 错误处理，吞错误以避免 UI 阻塞 */
  private confirmAction(item: TodoItem): void {
    this.handleQuickConfirm(item).catch((e: Error) => {
      console.error('handleQuickConfirm failed:', e?.message);
    });
  }

  @Builder
  MemberPickerOverlay() {
    Column() {
      Column() {
        Text('谁服了药？')
          .fontSize(this.fontTitle).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).margin({ bottom: 4 })
        Text(this.pendingMedItem?.title ?? '')
          .fontSize(this.fontBody).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 12 })

        // 一键按默认服药人确认
        if (this.defaultMemberId) {
          ForEach(this.familyMembers.filter((member: FamilyMember) => member.id === this.defaultMemberId), (defaultMember: FamilyMember) => {
            Row() {
              Text(defaultMember.avatar).fontSize(22).margin({ right: 10 })
              Column() {
                Row() {
                  Text(defaultMember.name)
                    .fontSize(this.fontSubtitle).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text(' 默认')
                    .fontSize(this.fontCaptionSm).fontColor(this.themeColor)
                    .backgroundColor(BG_CARD)
                    .borderRadius(6)
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    .margin({ left: 6 })
                }
                Text('该用药的服药人，点这里直接确认')
                  .fontSize(this.fontCaption).fontColor('#FFFFFF').margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('✓').fontSize(20).fontColor(Color.White)
            }
            .width('100%')
            .padding(16)
            .borderRadius(RADIUS_MD)
            .backgroundColor(this.themeColor)
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
          // 默认成员已经在上面独立卡片显示过，这里只列其他成员
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
          .borderRadius(RADIUS_MD)
          .backgroundColor(BG_PAPER)
          .margin({ bottom: 8 })
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

        Button('取消')
          .fontSize(this.fontBody).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
          .borderRadius(RADIUS_PILL).width('100%').margin({ top: 4 })
          .onClick(() => {
            this.showMemberPicker = false;
            this.pendingMedItem = null;
            this.defaultMemberId = '';
          })
      }
      .width('85%')
      .padding(20)
      .borderRadius(RADIUS_MD + 4)
      .backgroundColor(BG_CARD)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
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
    // 欢迎引导卡：点击"开始"跳转到设置页开启模块，同时永久标记已阅
    if (item.id === 'welcome') {
      await this.db.setWelcomeDismissed();
      await this.db.addDismissedTodayId('welcome');
      if (item.routePage) {
        router.pushUrl({ url: item.routePage });
      }
      return;
    }
    if (item.id.startsWith('med_') && item.medId && item.medTimeSlot) {
      // 无权限确认者（action === '查看'）：直接忽略
      if (item.action !== '待服') return;
      // 服药直接确认：服药人=Medication.forMemberId（不再弹选人器）
      this.confirmMedicationDirect(item);
      return;
    } else if (item.id.startsWith('rem_')) {
      // 提醒完成确认
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
      // 孩子事项完成确认
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
      // 其他事项（周期、记账等）→ 今日忽略，不再显示
      await this.db.addDismissedTodayId(item.id);
      this.loadData();
    }
  }

  private navigateByTab(index: number): void {
    if (index === 0) return; // 首页

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
