/**
 * 卡宝Home - 家庭提醒
 *
 * 定位：家庭长期事项的「记录与提醒」管理中心。
 * 用于创建：生日、纪念日、缴费、购物、家庭活动、待办……
 *
 * 与「消息中心」(NotificationCenterPage) 的区别：
 *  - 消息中心：跨模块未办事项聚合 + 一键完成 + 快速触达。
 *  - 家庭提醒：本模块专属的 CRUD + 分类浏览 + 时间轴。
 */
import { Reminder } from '../model/Reminder';
import { SHOPPING_CATEGORIES } from '../model/ShoppingItem';
import { LocalDbService } from '../service/LocalDbService';
import { Visibility, FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { EmptyState } from '../components/EmptyState';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { formatDate, generateId } from '../common/Utils';
import router from '@ohos.router';

interface ReminderTypeOption {
  type: string;
  label: string;
  icon: string;
  color: string;
  bgColor: string;
}

interface RecurrenceOption {
  rule: string;
  label: string;
}

interface VisibilityOption {
  vis: Visibility;
  label: string;
}

interface FilterTab {
  key: string;
  label: string;
  icon: string;
}

interface ReminderGroup {
  key: string;
  label: string;
  items: Reminder[];
}

// 家庭提醒可选类型——精简至 5 类（生日 / 纪念日 / 家庭活动 / 购物 / 缴费）
// 注：未选中时统一灰色，选中时才显示主题色，避免视觉过载
const REMINDER_TYPES: ReminderTypeOption[] = [
  { type: 'birthday', label: '生日', icon: '🎂', color: '#E91E63', bgColor: '#FCE4EC' },
  { type: 'anniversary', label: '纪念日', icon: '❤️', color: '#D32F2F', bgColor: '#FFEBEE' },
  { type: 'family', label: '家庭活动', icon: '👨‍👩‍👧', color: '#7B1FA2', bgColor: '#F3E5F5' },
  { type: 'shopping', label: '购物', icon: '🛒', color: '#2E7D32', bgColor: '#E8F5E9' },
  { type: 'bill', label: '缴费', icon: '💰', color: '#F57C00', bgColor: '#FFF3E0' }
];

// 重复规则选项（提到顶层，避免 ForEach 用内联字面量在严格模式下崩）
const RECURRENCE_OPTIONS: RecurrenceOption[] = [
  { rule: 'daily', label: '每天' },
  { rule: 'weekly', label: '每周' },
  { rule: 'monthly', label: '每月' },
  { rule: 'yearly', label: '每年' }
];

// 可见范围选项（同上）
const VISIBILITY_OPTIONS: VisibilityOption[] = [
  { vis: Visibility.PRIVATE, label: '🔒 仅自己' },
  { vis: Visibility.SELECTED, label: '👥 指定成员' },
  { vis: Visibility.FAMILY, label: '👨‍👩‍👧‍👦 全家可见' }
];

@Entry
@Component
struct ReminderPage {
  @State reminders: Reminder[] = [];
  @State familyMembers: FamilyMember[] = [];

  // —— 视图状态 ——
  @State activeFilter: string = 'all';     // all | birthday | anniversary | family | shopping | bill
  @State showCompleted: boolean = false;

  // —— 表单状态 ——
  @State showAddDialog: boolean = false;
  @State editingReminderId: string = '';
  @State newTitle: string = '';
  @State newDescription: string = '';
  @State newDueDate: string = '';
  @State newDueTimeValue: string = '';
  @State newReminderType: string = 'birthday';
  @State newIsRecurring: boolean = false;
  @State newRecurrenceRule: string = 'yearly';
  @State newVisibility: Visibility = Visibility.FAMILY;
  @State newItemCategory: string = '';
  @State newItemQuantity: string = '';

  // —— 详情弹窗 ——
  @State showDetail: boolean = false;
  @State detailReminder: Reminder | null = null;

  // —— 主题 / 字号 ——
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themeLightBg: string = '#FFF5F0';
  @State themePrimary: string = '#E8654A';
  @State themeBorder: string = '#FFD4C2';
  @State themeGradStart: string = '#E8654A';
  @State themeGradEnd: string = '#F28B6E';

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    // 先加载数据让页面立即可见，再异步执行迁移
    this.loadData();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themeLightBg = palette.lightBg;
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    this.themeGradStart = palette.gradientStart;
    this.themeGradEnd = palette.gradientEnd;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
    // 若从首页直接传入 reminderId，自动打开详情弹窗
    this.openDetailFromParams();
    // 延迟到下一帧执行迁移，避免阻塞首次渲染，并捕获所有异常
    setTimeout(() => {
      this.migrateOldShoppingItems().catch((e: Error) => {
        console.error('[ReminderPage] migrate shopping items failed:', e?.message ?? String(e));
      });
    }, 0);
  }

  onPageShow(): void {
    this.loadData();
    this.openDetailFromParams();
  }

  /**
   * 处理路由参数：首页直接跳详情时携带 { reminderId, openDetail: true }
   */
  private openDetailFromParams(): void {
    try {
      const params = router.getParams() as Record<string, Object> | undefined;
      if (!params) return;
      const shouldOpen = params['openDetail'] === true;
      const rid = params['reminderId'] as string | undefined;
      if (!shouldOpen || !rid) return;
      const target = this.reminders.find(r => r.id === rid);
      if (target) {
        this.detailReminder = target;
        this.showDetail = true;
      }
    } catch (_) {
      // 路由参数不存在或解析失败时忽略
    }
  }

  /**
   * 迁移旧版购物清单 -> 提醒事项（与原实现一致，保留以保护历史数据）
   * 改为标准 async 方法 + try/catch，避免 unhandled promise rejection 触发 ability 崩溃
   */
  private async migrateOldShoppingItems(): Promise<void> {
    try {
      const oldItems = this.db.getShoppingItems() ?? [];
      if (oldItems.length === 0) return;

      const existingReminders = this.db.getReminders() ?? [];

      for (const item of oldItems) {
        const exists = existingReminders.some(r => r.title === item.itemName && r.reminderType === 'shopping');
        const now = new Date().toISOString();

        if (!exists) {
          const reminder: Reminder = {
            id: generateId('rm'),
            familyId: item.familyId,
            creatorId: item.creatorId,
            visibility: item.visibility,
            visibleMembers: item.visibleMembers,
            version: 1,
            createdAt: now,
            updatedAt: now,
            title: item.itemName,
            description: `分类:${item.category}·${item.quantity}`,
            reminderType: 'shopping',
            dueTime: '',
            isRecurring: false,
            recurrenceRule: '',
            isCompleted: item.isPurchased,
            completedAt: item.isPurchased ? now : '',
            reminderSettings: []
          };
          await this.db.saveReminder(reminder);
        }
        await this.db.deleteShoppingItem(item.id);
      }
      this.loadData();
    } catch (e) {
      console.error('[ReminderPage] migrateOldShoppingItems error:', JSON.stringify(e));
    }
  }

  private loadData(): void {
    // 显式构造新数组引用，确保 @State 能稳定触发 UI 刷新
    // （JSON.parse 已返回新数组，但额外的浅拷贝可避免某些 ArkTS 版本对引用变化的判断歧义）
    const fresh = this.db.getReminders() ?? [];
    this.reminders = [...fresh];
    const members = this.familyVm.getFamilyMembers() ?? [];
    this.familyMembers = [...members];
  }

  private isCreator(creatorId: string): boolean {
    return creatorId === this.db.getCurrentUserId();
  }

  private resetForm(): void {
    this.newTitle = '';
    this.newDescription = '';
    this.newDueDate = '';
    this.newDueTimeValue = '';
    this.newReminderType = 'birthday';
    this.newIsRecurring = false;
    this.newRecurrenceRule = 'yearly';
    this.newVisibility = Visibility.FAMILY;
    this.newItemCategory = '';
    this.newItemQuantity = '';
  }

  /**
   * 关闭添加/编辑对话框时统一清理状态，
   * 避免 editingReminderId 残留导致下一次"新建"误写入旧记录
   */
  private closeAddDialog(): void {
    this.showAddDialog = false;
    this.editingReminderId = '';
    this.resetForm();
  }

  /**
   * 类型 -> 元数据
   */
  private getTypeMeta(type: string): ReminderTypeOption {
    const found = REMINDER_TYPES.find(t => t.type === type);
    if (found) return found;
    return { type: 'other', label: '其他', icon: '📎', color: '#546E7A', bgColor: '#ECEFF1' };
  }

  /**
   * 当前筛选条件下的活跃提醒
   * 注意：ArkTS @Component struct 不支持 get 属性，必须用普通方法
   */
  private getFilteredActive(): Reminder[] {
    return this.reminders.filter(r => {
      if (r.isCompleted) return false;
      if (this.activeFilter === 'all') return true;
      return r.reminderType === this.activeFilter;
    });
  }

  private getFilteredCompleted(): Reminder[] {
    return this.reminders.filter(r => {
      if (!r.isCompleted) return false;
      if (this.activeFilter === 'all') return true;
      return r.reminderType === this.activeFilter;
    });
  }

  /**
   * 把活跃提醒分组：即将到来（有 dueTime 且未过期）/ 永久（recurring yearly 等）/ 无日期
   */
  private getActiveGroups(): ReminderGroup[] {
    const nowIso = new Date().toISOString();
    const items = this.getFilteredActive();

    const overdue: Reminder[] = [];
    const upcoming: Reminder[] = [];
    const recurring: Reminder[] = [];
    const undated: Reminder[] = [];

    for (const r of items) {
      if (r.isRecurring) {
        recurring.push(r);
      } else if (!r.dueTime) {
        undated.push(r);
      } else if (r.dueTime < nowIso) {
        overdue.push(r);
      } else {
        upcoming.push(r);
      }
    }

    // 即将到来按时间升序
    upcoming.sort((a, b) => (a.dueTime > b.dueTime ? 1 : -1));
    overdue.sort((a, b) => (a.dueTime > b.dueTime ? -1 : 1));

    const groups: ReminderGroup[] = [];
    if (overdue.length > 0) groups.push({ key: 'overdue', label: '🔴 已过期', items: overdue });
    if (upcoming.length > 0) groups.push({ key: 'upcoming', label: '📅 即将到来', items: upcoming });
    if (recurring.length > 0) groups.push({ key: 'recurring', label: '🔂 重复事项', items: recurring });
    if (undated.length > 0) groups.push({ key: 'undated', label: '📝 无截止', items: undated });

    return groups;
  }

  /**
   * 各类型计数（用于顶部 chip）
   */
  private countByType(type: string): number {
    return this.reminders.filter(r => !r.isCompleted && r.reminderType === type).length;
  }

  build() {
    Stack() {
      Column() {
        // —— 顶栏 ——
        this.TitleBar()

        // —— 类型筛选 chip 横向滚动 ——
        Scroll() {
          Row({ space: 8 }) {
            this.FilterChip('all', '全部', '✨')
            ForEach(REMINDER_TYPES, (t: ReminderTypeOption) => {
              this.FilterChip(t.type, t.label, t.icon)
            }, (t: ReminderTypeOption) => t.type)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ top: 4, bottom: 8 })

        // —— 类型概览卡（仅在「全部」筛选时显示）——
        if (this.activeFilter === 'all') {
          this.TypeOverview()
        }

        // —— 主列表 ——
        Scroll() {
          Column({ space: 0 }) {
            if (this.getFilteredActive().length === 0 && this.getFilteredCompleted().length === 0) {
              EmptyState({
                icon: this.activeFilter === 'all' ? '🎯' : this.getTypeMeta(this.activeFilter).icon,
                title: this.activeFilter === 'all' ? '还没有家庭提醒' : `暂无${this.getTypeMeta(this.activeFilter).label}`,
                subtitle: '生日、纪念日、缴费、购物……一处管理',
                actionText: '+ 创建提醒',
                buttonColor: this.themePrimary,
                onAction: () => {
                  this.editingReminderId = '';
                  this.resetForm();
                  if (this.activeFilter !== 'all') {
                    this.newReminderType = this.activeFilter;
                  }
                  this.showAddDialog = true;
                }
              })
            } else {
              // 分组渲染
              ForEach(this.getActiveGroups(), (group: ReminderGroup) => {
                this.SectionHeader(group.label, group.items.length)
                ForEach(group.items, (r: Reminder) => {
                  this.ReminderCard(r)
                }, (r: Reminder) => r.id)
              }, (group: ReminderGroup) => group.key)

              // 已完成 - 折叠
              if (this.getFilteredCompleted().length > 0) {
                Row() {
                  Text('✅ 已完成').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#999999')
                  Text(`${this.getFilteredCompleted().length}项`).fontSize(14).fontColor('#BBBBBB').margin({ left: 6 })
                  Text(this.showCompleted ? '▲' : '▼').fontSize(12).fontColor('#BBBBBB').margin({ left: 4 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 4 })
                .onClick(() => { this.showCompleted = !this.showCompleted; })

                if (this.showCompleted) {
                  ForEach(this.getFilteredCompleted(), (r: Reminder) => {
                    this.ReminderCard(r)
                  }, (r: Reminder) => r.id)
                }
              }
            }
          }
          .width('100%')
          .padding({ bottom: 100 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.themeLightBg)

      // —— 悬浮 + 按钮 ——
      Column() {
        Text('✚')
          .fontSize(30)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .linearGradient({
        angle: 135,
        colors: [[this.themeGradStart, 0.0], [this.themeGradEnd, 1.0]]
      })
      .justifyContent(FlexAlign.Center)
      .shadow({
        radius: 16,
        color: '#66000000',
        offsetX: 0,
        offsetY: 6
      })
      .position({ x: '82%', y: '88%' })
      .onClick(() => {
        this.editingReminderId = '';
        this.resetForm();
        if (this.activeFilter !== 'all') {
          this.newReminderType = this.activeFilter;
        }
        this.showAddDialog = true;
      })

      // —— 对话框覆盖层（用条件渲染替代多个 bindContentCover）——
      if (this.showAddDialog) {
        this.AddReminderOverlay()
      }
      if (this.showDetail) {
        this.DetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 顶栏 ====================
  @Builder
  TitleBar() {
    Row() {
      Row() {
        Text('<')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
      }
      .width(34).height(34).borderRadius(17)
      .backgroundColor(this.themeBorder)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { router.back(); })

      Column() {
        Text('📋 家庭提醒').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold)
        Text('记录每一件值得被记得的事').fontSize(11).fontColor('#999999').margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      // 跳到消息中心
      Row() {
        Text('📥').fontSize(18)
      }
      .width(34).height(34).borderRadius(17)
      .backgroundColor(this.themeBorder)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        try {
          router.pushUrl({ url: 'pages/NotificationCenterPage' });
        } catch (_) {}
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  // ==================== 类型概览卡 ====================
  @Builder
  TypeOverview() {
    Row() {
      this.OverviewMini('🎂', '生日', this.countByType('birthday'), '#E91E63')
      this.OverviewMini('❤️', '纪念日', this.countByType('anniversary'), '#D32F2F')
      this.OverviewMini('💰', '缴费', this.countByType('bill'), '#F57C00')
      this.OverviewMini('🛒', '购物', this.countByType('shopping'), '#2E7D32')
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  OverviewMini(icon: string, label: string, count: number, color: string) {
    Column() {
      Text(icon).fontSize(20)
      Text(`${count}`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(color).margin({ top: 2 })
      Text(label).fontSize(10).fontColor('#666666').margin({ top: 2 })
    }
    .width('23%')
    .padding({ top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
  }

  // ==================== 筛选 chip ====================
  @Builder
  FilterChip(key: string, label: string, icon: string) {
    Row() {
      Text(icon).fontSize(14).margin({ right: 4 })
      Text(label).fontSize(13)
        .fontColor(this.activeFilter === key ? Color.White : '#666666')
        .fontWeight(this.activeFilter === key ? FontWeight.Bold : FontWeight.Normal)
    }
    .backgroundColor(this.activeFilter === key ? this.themePrimary : Color.White)
    .borderRadius(16)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .shadow(this.activeFilter === key
      ? { radius: 4, color: '#33000000', offsetX: 0, offsetY: 2 }
      : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
    .onClick(() => { this.activeFilter = key; })
  }

  // ==================== 分组标题 ====================
  @Builder
  SectionHeader(title: string, count: number) {
    Row() {
      Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#333333')
      Text(`${count}`)
        .fontSize(12).fontColor('#999999')
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 4 })
  }

  // ==================== 提醒卡片 ====================
  @Builder
  ReminderCard(r: Reminder) {
    Row() {
      // 类型图标方块
      Column() {
        Text(this.getTypeMeta(r.reminderType).icon).fontSize(20)
      }
      .width(44).height(44).borderRadius(12)
      .backgroundColor(this.getTypeMeta(r.reminderType).bgColor)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 12 })

      Column() {
        Row() {
          Text(r.title)
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(r.isCompleted ? '#999999' : '#333333')
            .decoration({ type: r.isCompleted ? TextDecorationType.LineThrough : TextDecorationType.None })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (r.isRecurring) {
            Text('🔂')
              .fontSize(12)
              .margin({ left: 4 })
          }
        }
        .width('100%')

        if (r.dueTime || r.description) {
          Row() {
            if (r.dueTime) {
              Text(this.formatDueTime(r.dueTime))
                .fontSize(13)
                .fontColor(this.isOverdue(r) ? '#D32F2F' : '#888888')
            }
            if (r.dueTime && r.description) {
              Text(' · ').fontSize(13).fontColor('#CCCCCC')
            }
            if (r.description) {
              Text(r.description)
                .fontSize(13).fontColor('#888888')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')
          .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作（左侧 margin 防止与标题中的 🔂 重复图标贴边）
      if (r.isCompleted) {
        Text('撤销')
          .fontSize(13).fontColor('#FF9800').backgroundColor('#FFF8E1')
          .borderRadius(8).padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 10 })
          .onClick(() => { this.toggleComplete(r, false); })
      } else {
        Row() {
          Text('✓').fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Bold)
        }
        .width(32).height(32).borderRadius(16)
        .backgroundColor(this.isOverdue(r) ? '#D32F2F' : this.themePrimary)
        .justifyContent(FlexAlign.Center)
        .margin({ left: 10 })
        .onClick(() => { this.toggleComplete(r, true); })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(this.isOverdue(r) && !r.isCompleted ? '#FFF5F5' : Color.White)
    .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
    .margin({ left: 12, right: 12, top: 4, bottom: 4 })
    .opacity(r.isCompleted ? 0.65 : 1)
    .onClick(() => {
      this.detailReminder = r;
      this.showDetail = true;
    })
    .gesture(
      LongPressGesture()
        .onAction(() => { this.handleLongPress(r); })
    )
  }

  // ==================== 状态切换 ====================
  private async toggleComplete(r: Reminder, complete: boolean): Promise<void> {
    if (!this.isCreator(r.creatorId)) {
      AlertDialog.show({ message: '只能操作自己创建的记录' });
      return;
    }
    const now = new Date().toISOString();
    const updated: Reminder = {
      id: r.id, familyId: r.familyId, creatorId: r.creatorId,
      visibility: r.visibility, visibleMembers: r.visibleMembers,
      version: r.version + 1, createdAt: r.createdAt, updatedAt: now,
      title: r.title, description: r.description, reminderType: r.reminderType,
      dueTime: r.dueTime, isRecurring: r.isRecurring, recurrenceRule: r.recurrenceRule,
      isCompleted: complete, completedAt: complete ? now : '',
      reminderSettings: r.reminderSettings
    };
    await this.db.updateReminder(updated);
    this.loadData();
  }

  /**
   * 完成/撤销提醒——不限创建者，家庭成员均可操作
   * （用于详情弹窗的"完成"按钮，符合 PRD：无编辑权限的成员仍可标记完成）
   */
  private async toggleCompleteAny(r: Reminder, complete: boolean): Promise<void> {
    const now = new Date().toISOString();
    const updated: Reminder = {
      id: r.id, familyId: r.familyId, creatorId: r.creatorId,
      visibility: r.visibility, visibleMembers: r.visibleMembers,
      version: r.version + 1, createdAt: r.createdAt, updatedAt: now,
      title: r.title, description: r.description, reminderType: r.reminderType,
      dueTime: r.dueTime, isRecurring: r.isRecurring, recurrenceRule: r.recurrenceRule,
      isCompleted: complete, completedAt: complete ? now : '',
      reminderSettings: r.reminderSettings
    };
    await this.db.updateReminder(updated);
    this.loadData();
  }

  private handleLongPress(r: Reminder): void {
    if (!this.isCreator(r.creatorId)) {
      AlertDialog.show({ message: '只能操作自己创建的记录' });
      return;
    }
    AlertDialog.show({
      title: '操作',
      message: `「${r.title}」`,
      primaryButton: {
        value: '删除',
        fontColor: '#D32F2F',
        action: () => {
          this.db.deleteReminder(r.id).then(() => { this.loadData(); });
        }
      },
      secondaryButton: {
        value: '编辑',
        action: () => { this.startEdit(r); }
      }
    });
  }

  private startEdit(r: Reminder): void {
    this.editingReminderId = r.id;
    this.newTitle = r.title ?? '';
    this.newDescription = r.description ?? '';
    this.newReminderType = r.reminderType ?? 'birthday';
    const dueTime = r.dueTime ?? '';
    this.newDueDate = dueTime.slice(0, 10);
    this.newDueTimeValue = dueTime.length > 10 ? dueTime.slice(11, 16) : '';
    this.newIsRecurring = r.isRecurring ?? false;
    this.newRecurrenceRule = r.recurrenceRule || 'yearly';
    this.newVisibility = r.visibility;
    // 购物附加字段
    if (r.reminderType === 'shopping') {
      const desc = r.description ?? '';
      if (desc.startsWith('分类:')) {
        const parts = desc.substring(3).split('·');
        this.newItemCategory = parts[0] || '';
        this.newItemQuantity = parts[1] || '';
      }
      // 若标题等于分类名（自动派生），则清空"具体说明"输入框，避免误回显
      if (this.newTitle && this.newTitle === this.newItemCategory) {
        this.newTitle = '';
      }
    } else {
      this.newItemCategory = '';
      this.newItemQuantity = '';
    }
    this.showAddDialog = true;
  }

  // ==================== 表单弹窗 ====================
  @Builder
  AddReminderOverlay() {
    Column() {
      Column() {
        // 标题
        Row() {
          Text(this.editingReminderId ? '编辑提醒' : '新建家庭提醒')
            .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999')
            .onClick(() => { this.closeAddDialog(); })
        }
        .width('100%')
        .margin({ bottom: 14 })

        Scroll() {
          Column() {
            // —— 类型选择（在最顶端，作为分类核心）——
            // 未选中：统一灰色底；选中：才高亮该类型主题色
            Text('类型').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(REMINDER_TYPES, (t: ReminderTypeOption) => {
                Row() {
                  Text(t.icon).fontSize(14).margin({ right: 4 })
                  Text(t.label).fontSize(12)
                    .fontColor(this.newReminderType === t.type ? Color.White : '#666666')
                    .fontWeight(this.newReminderType === t.type ? FontWeight.Bold : FontWeight.Normal)
                }
                .backgroundColor(this.newReminderType === t.type ? t.color : '#F5F5F5')
                .borderRadius(14)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .margin(3)
                .onClick(() => { this.newReminderType = t.type; })
              }, (t: ReminderTypeOption) => t.type)
            }
            .margin({ bottom: 14 })

            // —— 购物类型：分类前置 + 具体说明(选填) + 数量 ——
            if (this.newReminderType === 'shopping') {
              // 分类（必选，grid 排布更易点选）
              Text('分类（必选）').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(SHOPPING_CATEGORIES, (cat: string) => {
                  Row() {
                    Text(cat)
                      .fontSize(13)
                      .fontColor(this.newItemCategory === cat ? Color.White : '#333333')
                      .fontWeight(this.newItemCategory === cat ? FontWeight.Bold : FontWeight.Normal)
                  }
                  .backgroundColor(this.newItemCategory === cat ? '#2E7D32' : '#F0F0F0')
                  .borderRadius(16)
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .margin(3)
                  .onClick(() => { this.newItemCategory = cat; })
                }, (cat: string) => cat)
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 具体说明（选填，替代"标题"）
              Text('具体说明（选填）').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newTitle, placeholder: '如：牛奶、鸡蛋、酱油' })
                .width('100%').padding(10).borderRadius(8)
                .backgroundColor('#F5F5F5')
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newTitle = v; })

              // 数量（选填）
              Text('数量（选填）').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newItemQuantity, placeholder: '如：2盒、500g、1瓶' })
                .width('100%').padding(10).borderRadius(8)
                .backgroundColor('#F5F5F5')
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newItemQuantity = v; })
            } else {
              // —— 非购物类型：标题 + 描述 ——
              Text('标题').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newTitle, placeholder: this.getTitlePlaceholder() })
                .width('100%').padding(10).borderRadius(8)
                .backgroundColor('#F5F5F5')
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newTitle = v; })

              Text('描述').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newDescription, placeholder: '补充信息（可选）' })
                .width('100%').padding(10).borderRadius(8)
                .backgroundColor('#F5F5F5')
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newDescription = v; })
            }

            // —— 日期 + 时间 ——
            Text('日期与时间').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
            Row({ space: 8 }) {
              Row() {
                Text('🗓️').fontSize(15).margin({ right: 6 })
                Text(this.newDueDate || '选择日期')
                  .fontSize(14).fontColor(this.newDueDate ? '#333333' : '#999999').layoutWeight(1)
              }
              .layoutWeight(1)
              .padding(10).borderRadius(8).backgroundColor('#F5F5F5')
              .onClick(() => {
                // 编辑场景下 dialog 应以已填日期为初始值；否则展示今天
                let initialDate: Date = new Date();
                if (this.newDueDate) {
                  const parts = this.newDueDate.split('-');
                  if (parts.length === 3) {
                    const y = parseInt(parts[0], 10);
                    const mo = parseInt(parts[1], 10);
                    const da = parseInt(parts[2], 10);
                    if (!isNaN(y) && !isNaN(mo) && !isNaN(da)) {
                      initialDate = new Date(y, mo - 1, da);
                    }
                  }
                }
                // 使用现代 API（返回 Date 对象），避免 DatePickerResult.month 索引歧义
                this.getUIContext().showDatePickerDialog({
                  start: new Date('2000-01-01'),
                  end: new Date('2099-12-31'),
                  selected: initialDate,
                  onDateAccept: (value: Date) => {
                    const y = value.getFullYear();
                    const mo = value.getMonth() + 1;
                    const da = value.getDate();
                    this.newDueDate = `${y}-${mo < 10 ? '0' + mo : '' + mo}-${da < 10 ? '0' + da : '' + da}`;
                  }
                })
              })

              Row() {
                Text('🕐').fontSize(15).margin({ right: 6 })
                Text(this.newDueTimeValue || '时间')
                  .fontSize(14).fontColor(this.newDueTimeValue ? '#333333' : '#999999').layoutWeight(1)
              }
              .layoutWeight(1)
              .padding(10).borderRadius(8).backgroundColor('#F5F5F5')
              .onClick(() => {
                // 编辑场景下，picker 应展示已填时间；否则展示当前时间
                let initialTime: Date = new Date();
                if (this.newDueTimeValue) {
                  const parts = this.newDueTimeValue.split(':');
                  if (parts.length === 2) {
                    const hh = parseInt(parts[0], 10);
                    const mm = parseInt(parts[1], 10);
                    if (!isNaN(hh) && !isNaN(mm)) {
                      initialTime = new Date();
                      initialTime.setHours(hh, mm, 0, 0);
                    }
                  }
                }
                TimePickerDialog.show({
                  selected: initialTime,
                  useMilitaryTime: true,
                  onAccept: (value: TimePickerResult) => {
                    const h = value.hour as number;
                    const min = value.minute as number;
                    this.newDueTimeValue = `${h < 10 ? '0' + h : '' + h}:${min < 10 ? '0' + min : '' + min}`;
                  }
                })
              })
            }
            .width('100%').margin({ bottom: 12 })

            // —— 重复 ——
            Row() {
              Text('🔂 重复提醒').fontSize(14).fontColor('#333333').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.newIsRecurring })
                .onChange((isOn: boolean) => { this.newIsRecurring = isOn; })
            }
            .width('100%').padding({ top: 4, bottom: 8 })

            if (this.newIsRecurring) {
              Row({ space: 6 }) {
                ForEach(RECURRENCE_OPTIONS, (item: RecurrenceOption) => {
                  Text(item.label)
                    .fontSize(12)
                    .fontColor(this.newRecurrenceRule === item.rule ? Color.White : '#666666')
                    .backgroundColor(this.newRecurrenceRule === item.rule ? this.themePrimary : '#F5F5F5')
                    .borderRadius(10)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .onClick(() => { this.newRecurrenceRule = item.rule; })
                }, (item: RecurrenceOption) => item.rule)
              }
              .margin({ bottom: 12 })
            }

            // —— 可见范围 ——
            Text('可见范围').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 6 })
            Row({ space: 6 }) {
              ForEach(VISIBILITY_OPTIONS, (item: VisibilityOption) => {
                Text(item.label)
                  .fontSize(12)
                  .fontColor(this.newVisibility === item.vis ? Color.White : '#666666')
                  .backgroundColor(this.newVisibility === item.vis ? this.themePrimary : '#F5F5F5')
                  .borderRadius(12)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .onClick(() => { this.newVisibility = item.vis; })
              }, (item: VisibilityOption) => `${item.vis}`)
            }
            .margin({ bottom: 18 })
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // —— 底部按钮 ——
        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
            .borderRadius(20).layoutWeight(1)
            .onClick(() => { this.closeAddDialog(); })
          Button(this.editingReminderId ? '保存' : '添加')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .onClick(async () => {
              if (this.newReminderType === 'shopping') {
                if (!this.newItemCategory) {
                  AlertDialog.show({ message: '请选择购物分类' });
                  return;
                }
              } else if (!this.newTitle) {
                AlertDialog.show({ message: '请填写标题' });
                return;
              }
              await this.saveReminder();
            })
        }
        .margin({ top: 6 })
      }
      .width('92%')
      .constraintSize({ maxHeight: '85%' })
      .padding(18)
      .borderRadius(18)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.closeAddDialog(); })
  }

  private getTitlePlaceholder(): string {
    const map: Record<string, string> = {
      'birthday': '如：妈妈的生日',
      'anniversary': '如：结婚纪念日',
      'family': '如：家庭聚餐',
      'bill': '如：电费缴费',
      'shopping': '如：牛奶'
    };
    return map[this.newReminderType] ?? '请输入标题';
  }

  private async saveReminder(): Promise<void> {
    const now = new Date().toISOString();
    // 购物类型：分类必选，具体说明可选 → 标题优先使用具体说明，否则用分类名兜底
    const effectiveTitle = this.newReminderType === 'shopping'
      ? (this.newTitle?.trim() || this.newItemCategory || '购物项')
      : this.newTitle;
    const effectiveDesc = this.newReminderType === 'shopping'
      ? `分类:${this.newItemCategory || '其他'}·${this.newItemQuantity}`
      : this.newDescription;
    const newDueTime = this.newDueDate ? this.newDueDate + 'T' + (this.newDueTimeValue || '00:00') : '';

    if (this.editingReminderId) {
      // 编辑场景：在「所有」reminder 中按 id 查找原记录，避免被可见性过滤掉时找不到
      const allReminders = this.db.getReminders();
      const existing = allReminders.find(rm => rm.id === this.editingReminderId);
      if (!existing) {
        console.warn('[ReminderPage] saveReminder: editing reminder not found, id=' + this.editingReminderId);
        AlertDialog.show({ message: '原记录未找到，保存失败' });
        return;
      }
      const updated: Reminder = {
        id: existing.id, familyId: existing.familyId, creatorId: existing.creatorId,
        visibility: this.newVisibility, visibleMembers: existing.visibleMembers,
        version: existing.version + 1, createdAt: existing.createdAt, updatedAt: now,
        title: effectiveTitle, description: effectiveDesc, reminderType: this.newReminderType,
        dueTime: newDueTime,
        isRecurring: this.newIsRecurring,
        recurrenceRule: this.newIsRecurring ? this.newRecurrenceRule : '',
        isCompleted: existing.isCompleted, completedAt: existing.completedAt,
        reminderSettings: existing.reminderSettings
      };
      await this.db.updateReminder(updated);
    } else {
      const userId = this.db.getCurrentUserId();
      const family = this.db.getCurrentFamily();
      const reminder: Reminder = {
        id: generateId('rm'), familyId: family?.id ?? '', creatorId: userId,
        visibility: this.newVisibility, visibleMembers: [], version: 1,
        createdAt: now, updatedAt: now,
        title: effectiveTitle, description: effectiveDesc, reminderType: this.newReminderType,
        dueTime: newDueTime,
        isRecurring: this.newIsRecurring,
        recurrenceRule: this.newIsRecurring ? this.newRecurrenceRule : '',
        isCompleted: false, completedAt: '', reminderSettings: []
      };
      await this.db.saveReminder(reminder);
    }
    // 先刷新数据，再关闭弹窗，避免「关闭→重渲染→数据未更新」的视觉延迟
    this.loadData();
    this.closeAddDialog();
  }

  // ==================== 详情弹窗 ====================
  @Builder
  DetailOverlay() {
    Column() {
      Column() {
        Row() {
          Text(`${this.getTypeMeta(this.detailReminder?.reminderType ?? 'other').icon} ${this.getTypeMeta(this.detailReminder?.reminderType ?? 'other').label}`)
            .fontSize(14)
            .fontColor(this.getTypeMeta(this.detailReminder?.reminderType ?? 'other').color)
            .backgroundColor(this.getTypeMeta(this.detailReminder?.reminderType ?? 'other').bgColor)
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999')
            .onClick(() => { this.showDetail = false; })
        }
        .width('100%')
        .margin({ bottom: 14 })

        if (this.detailReminder) {
          Text(this.detailReminder.title)
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(this.detailReminder.isCompleted ? '#999999' : '#333333')
            .decoration({ type: this.detailReminder.isCompleted ? TextDecorationType.LineThrough : TextDecorationType.None })
            .width('100%').margin({ bottom: 14 })

          Column({ space: 10 }) {
            if (this.detailReminder.dueTime) {
              this.DetailRow('🕐 时间', this.formatDueTime(this.detailReminder.dueTime))
            }
            if (this.detailReminder.description) {
              this.DetailRow('📝 描述', this.detailReminder.description)
            }
            if (this.detailReminder.isRecurring) {
              this.DetailRow('🔂 重复', this.getRecurrenceLabel(this.detailReminder.recurrenceRule))
            }
            this.DetailRow('👁 可见', this.getVisibilityLabel(this.detailReminder.visibility))
            this.DetailRow('📌 状态', this.getDueStatus(this.detailReminder.dueTime, this.detailReminder.isCompleted))
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor(this.themeLightBg)
          .margin({ bottom: 16 })

          Row({ space: 10 }) {
            Button('关闭')
              .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
              .borderRadius(20).layoutWeight(1)
              .onClick(() => { this.showDetail = false; })

            // 编辑：仅创建者可见
            if (this.isCreator(this.detailReminder.creatorId)) {
              Button('编辑')
                .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
                .borderRadius(20).layoutWeight(1)
                .onClick(() => {
                  const r = this.detailReminder!;
                  this.showDetail = false;
                  this.startEdit(r);
                })
            }

            // 完成/撤销：所有家庭成员都可标记
            Button(this.detailReminder.isCompleted ? '撤销' : '完成')
              .fontSize(14).fontColor(Color.White)
              .backgroundColor(this.detailReminder.isCompleted ? '#FF9800' : '#2E7D32')
              .borderRadius(20).layoutWeight(1)
              .onClick(async () => {
                const r = this.detailReminder!;
                await this.toggleCompleteAny(r, !r.isCompleted);
                // 关闭弹窗并刷新引用
                this.showDetail = false;
                this.detailReminder = null;
              })
          }
          .width('100%')
        }
      }
      .width('92%')
      .padding(18)
      .borderRadius(18)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.showDetail = false; })
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor('#999999').width(70)
      Text(value).fontSize(14).fontColor('#333333').layoutWeight(1)
    }
    .width('100%')
  }

  // ==================== 工具 ====================
  private isOverdue(r: Reminder): boolean {
    if (r.isCompleted || !r.dueTime) return false;
    return r.dueTime < new Date().toISOString();
  }

  private formatDueTime(dueTime: string): string {
    if (!dueTime) return '';
    if (dueTime.length <= 10) return dueTime;
    return dueTime.slice(0, 16).replace('T', ' ');
  }

  private getRecurrenceLabel(rule: string): string {
    const map: Record<string, string> = {
      'daily': '每天', 'weekly': '每周', 'monthly': '每月', 'yearly': '每年'
    };
    return map[rule] ?? rule;
  }

  private getVisibilityLabel(v: Visibility): string {
    if (v === Visibility.PRIVATE) return '🔒 仅自己';
    if (v === Visibility.SELECTED) return '👥 指定成员';
    return '👨‍👩‍👧‍👦 全家可见';
  }

  private getDueStatus(dueTime: string | undefined, isCompleted: boolean): string {
    if (isCompleted) return '✅ 已完成';
    if (!dueTime) return '📌 进行中';
    return dueTime < new Date().toISOString() ? '🔴 已过期' : '🟢 待提醒';
  }
}
