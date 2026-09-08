/**
 * 卡宝Home - 家庭提醒
 *
 * 定位：家庭长期事项的「记录与提醒」管理中心。
 * 用于创建：生日、纪念日、缴费、购物、家庭活动、待办……
 *
 * 与「消息中心」(NotificationCenterPage) 的区别：
 *  - 消息中心：跨模块未办事项聚合 + 一键完成 + 快速触达。
 *  - 家庭提醒：本模块专属的 CRUD + 分类浏览 + 时间轴。
 *
 * 方向 C · 极简编辑：纸白底 + 墨黑正文 + flat 分隔线 + 衬线标题 + 文本动作
 */
import { Reminder } from '../model/Reminder';
import {
  BG_PAPER, BG_CARD, BG_SUBTLE, DIVIDER, BORDER_SUBTLE,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, BRAND_RED_LG,
  SEMANTIC_SUCCESS, SEMANTIC_ERROR, SEMANTIC_WARNING, SEMANTIC_INFO,
  MIST_PURPLE, ERROR_BG, WARNING_BG, SUCCESS_BG,
  FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_CAPTION_SM,
  FONT_TITLE, FONT_FAMILY_SERIF, SPACE_MD, SPACE_LG
} from '../common/DesignTokens';
import { SHOPPING_CATEGORIES } from '../model/ShoppingItem';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { Visibility, FontSizeMode, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import { EmptyState } from '../components/EmptyState';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { formatDate, generateId, toDateAtLocalMidnight, creatorDisplayLabel } from '../common/Utils';
import router from '@ohos.router';
import { curves } from '@kit.ArkUI';

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

const REMINDER_TYPES: ReminderTypeOption[] = [
  { type: 'birthday', label: '生日', icon: '🎂', color: BRAND_RED_LG, bgColor: ERROR_BG },
  { type: 'anniversary', label: '纪念日', icon: '❤️', color: SEMANTIC_ERROR, bgColor: ERROR_BG },
  { type: 'family', label: '家庭活动', icon: '👨‍👩‍👧', color: MIST_PURPLE, bgColor: BG_SUBTLE },
  { type: 'shopping', label: '购物', icon: '🛒', color: SEMANTIC_SUCCESS, bgColor: SUCCESS_BG },
  { type: 'bill', label: '缴费', icon: '💰', color: SEMANTIC_WARNING, bgColor: WARNING_BG }
];

const RECURRENCE_OPTIONS: RecurrenceOption[] = [
  { rule: 'daily', label: '每天' },
  { rule: 'weekly', label: '每周' },
  { rule: 'monthly', label: '每月' },
  { rule: 'yearly', label: '每年' }
];

const VISIBILITY_OPTIONS: VisibilityOption[] = [
  { vis: Visibility.PRIVATE, label: '仅自己' },
  { vis: Visibility.SELECTED, label: '指定成员' },
  { vis: Visibility.FAMILY, label: '全家可见' }
];

function getReminderIconRes(type: string): Resource | null {
  switch (type) {
    case 'birthday': return $r('app.media.icon_star');
    case 'anniversary': return $r('app.media.icon_heart');
    case 'shopping': return $r('app.media.icon_cart');
    case 'bill': return $r('app.media.icon_wallet');
    case 'medication': return $r('app.media.icon_pill');
    default: return null;
  }
}

@Entry
@Component
struct ReminderPage {
  @State reminders: Reminder[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State activeFilter: string = 'all';
  @State showCompleted: boolean = false;
  @State isRefreshing: boolean = false;
  @State showAddDialog: boolean = false;
  @State isSavingReminder: boolean = false;
  @State editingReminderId: string = '';
  @State newTitle: string = '';
  @State newDescription: string = '';
  @State newDueDate: string = '';
  @State newDueTimeValue: string = '';
  @State newReminderType: string = 'birthday';
  @State newIsRecurring: boolean = false;
  @State newRecurrenceRule: string = 'yearly';
  @State newVisibility: Visibility = Visibility.FAMILY;
  @State newVisibleUserIds: string[] = [];
  @State newItemCategory: string = '';
  @State newItemQuantity: string = '';
  @State showDetail: boolean = false;
  @State detailReminder: Reminder | null = null;
  @State isLargeFont: boolean = false;

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    this.loadData();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    this.openDetailFromParams();
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
    } catch (_) {}
  }

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
            id: generateId('rm'), familyId: item.familyId, creatorId: item.creatorId,
            visibility: item.visibility, visibleMembers: item.visibleMembers,
            version: 1, createdAt: now, updatedAt: now,
            title: item.itemName, description: `分类:${item.category}·${item.quantity}`,
            reminderType: 'shopping', dueTime: '', isRecurring: false,
            recurrenceRule: '', isCompleted: item.isPurchased,
            completedAt: item.isPurchased ? now : '', reminderSettings: []
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
    const fresh = this.db.getReminders() ?? [];
    this.reminders = [...fresh];
    const members = this.familyVm.getFamilyMembers() ?? [];
    this.familyMembers = [...members];
  }

  private async handlePullRefresh(): Promise<void> {
    try {
      const familyId = this.db.getCurrentFamilyId();
      if (familyId && CloudService.getInstance().isCloudAvailable()) {
        await CloudService.getInstance().syncAll(familyId, true);
      }
    } finally {
      this.isRefreshing = false;
      this.loadData();
    }
  }

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  private recordCreatorLabel(creatorId: string): string {
    if (!creatorId || this.isCreator(creatorId)) return '';
    return creatorDisplayLabel(creatorId, this.familyMembers);
  }

  private resetForm(): void {
    this.newTitle = '';
    this.newDescription = '';
    this.newDueDate = '';
    this.newDueTimeValue = '';
    this.newReminderType = 'birthday';
    this.newIsRecurring = false;
    this.newRecurrenceRule = 'yearly';
    const moduleVis = this.db.resolveModuleVisibilityForRecord(ModuleId.REMINDER);
    this.newVisibility = moduleVis.visibility;
    this.newVisibleUserIds = moduleVis.visibility === Visibility.SELECTED && moduleVis.visibleMembers.length > 0
      ? [...moduleVis.visibleMembers] : [];
    this.newItemCategory = '';
    this.newItemQuantity = '';
  }

  private getShareCandidates(): FamilyMember[] {
    const currentUserId = this.db.getCurrentUserId();
    const currentMemberId = this.db.getCurrentMemberId();
    const result: FamilyMember[] = [];
    for (let i = 0; i < this.familyMembers.length; i++) {
      const m = this.familyMembers[i];
      if (!m || m.isDeleted === true) continue;
      if (!m.userId) continue;
      if (currentMemberId && m.id === currentMemberId) continue;
      if (currentUserId && m.userId === currentUserId) continue;
      result.push(m);
    }
    return result;
  }

  private toggleVisibleMember(userId: string): void {
    const idx = this.newVisibleUserIds.indexOf(userId);
    if (idx >= 0) {
      this.newVisibleUserIds = this.newVisibleUserIds.filter(id => id !== userId);
    } else {
      this.newVisibleUserIds = [...this.newVisibleUserIds, userId];
    }
  }

  private isMemberSelected(userId: string): boolean {
    return this.newVisibleUserIds.indexOf(userId) >= 0;
  }

  private selectVisibility(value: Visibility): void {
    this.newVisibility = value;
    if (value !== Visibility.SELECTED) return;
    if (this.newVisibleUserIds.length > 0) return;
    const moduleVis = this.db.resolveModuleVisibilityForRecord(ModuleId.REMINDER);
    if (moduleVis.visibility === Visibility.SELECTED && moduleVis.visibleMembers.length > 0) {
      this.newVisibleUserIds = [...moduleVis.visibleMembers];
    }
  }

  private closeAddDialog(): void {
    this.showAddDialog = false;
    this.editingReminderId = '';
    this.resetForm();
  }

  private getTypeMeta(type: string): ReminderTypeOption {
    const found = REMINDER_TYPES.find(t => t.type === type);
    if (found) return found;
    return { type: 'other', label: '其他', icon: '📎', color: SEMANTIC_INFO, bgColor: BORDER_SUBTLE };
  }

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

  private getActiveGroups(): ReminderGroup[] {
    const nowMs = Date.now();
    const items = this.getFilteredActive();
    const overdue: Reminder[] = [];
    const upcoming: Reminder[] = [];
    const recurring: Reminder[] = [];
    const undated: Reminder[] = [];
    for (const r of items) {
      if (r.reminderType === 'period') {
        if (r.dueTime && new Date(r.dueTime).getTime() < nowMs) {
          overdue.push(r);
        }
        continue;
      }
      if (r.isRecurring) {
        recurring.push(r);
      } else if (!r.dueTime) {
        undated.push(r);
      } else if (new Date(r.dueTime).getTime() < nowMs) {
        overdue.push(r);
      } else {
        upcoming.push(r);
      }
    }
    upcoming.sort((a, b) => (a.dueTime > b.dueTime ? 1 : -1));
    overdue.sort((a, b) => (a.dueTime > b.dueTime ? -1 : 1));
    const groups: ReminderGroup[] = [];
    if (overdue.length > 0) groups.push({ key: 'overdue', label: '已过期', items: overdue });
    if (upcoming.length > 0) groups.push({ key: 'upcoming', label: '即将到来', items: upcoming });
    if (recurring.length > 0) groups.push({ key: 'recurring', label: '重复事项', items: recurring });
    if (undated.length > 0) groups.push({ key: 'undated', label: '无截止', items: undated });
    return groups;
  }

  private countByType(type: string): number {
    return this.reminders.filter(r => !r.isCompleted && r.reminderType === type).length;
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
  }

  build() {
    Stack() {
      Column() {
        this.TitleBar()

        Scroll() {
          Row({ space: 6 }) {
            this.FilterChip('all', '全部')
            ForEach(REMINDER_TYPES, (t: ReminderTypeOption) => {
              this.FilterChip(t.type, t.label)
            }, (t: ReminderTypeOption) => t.type)
          }
          .padding({ left: SPACE_MD, right: SPACE_MD })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .border({ width: { bottom: 0.5 }, color: DIVIDER })
        .padding({ top: 4, bottom: 4 })

        if (this.activeFilter === 'all') {
          this.TypeOverview()
        }

        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll() {
            Column({ space: 0 }) {
              if (this.getFilteredActive().length === 0 && this.getFilteredCompleted().length === 0) {
                EmptyState({
                  icon: this.activeFilter === 'all' ? '🎯' : this.getTypeMeta(this.activeFilter).icon,
                  title: this.activeFilter === 'all' ? '还没有家庭提醒' : `暂无${this.getTypeMeta(this.activeFilter).label}`,
                  subtitle: '生日、纪念日、缴费、购物……一处管理',
                  actionText: '+ 创建提醒',
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
                ForEach(this.getActiveGroups(), (group: ReminderGroup) => {
                  this.SectionHeader(group.label, group.items.length)
                  ForEach(group.items, (r: Reminder) => {
                    this.ReminderCard(r)
                  }, (r: Reminder) => r.id + '_' + r.updatedAt)
                }, (group: ReminderGroup) => group.key)

                if (this.getFilteredCompleted().length > 0) {
                  Row() {
                    Text('已完成')
                      .fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK_SECONDARY)
                    Text(`${this.getFilteredCompleted().length}`)
                      .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY).margin({ left: 6 })
                    Blank()
                    Text(this.showCompleted ? '收起' : '展开')
                      .fontSize(FONT_CAPTION).fontColor(BRAND_RED)
                  }
                  .width('100%')
                  .padding({ left: SPACE_LG, right: SPACE_LG, top: 14, bottom: 6 })
                  .onClick(() => { this.showCompleted = !this.showCompleted; })

                  if (this.showCompleted) {
                    ForEach(this.getFilteredCompleted(), (r: Reminder) => {
                      this.ReminderCard(r)
                    }, (r: Reminder) => r.id + '_' + r.updatedAt)
                  }
                }

                Button('+ 添加提醒')
                  .fontSize(FONT_BODY)
                  .fontColor(Color.White)
                  .backgroundColor(NEUTRAL_INK)
                  .borderRadius(0)
                  .width('100%')
                  .margin({ top: SPACE_LG })
                  .onClick(() => {
                    this.editingReminderId = '';
                    this.resetForm();
                    if (this.activeFilter !== 'all') {
                      this.newReminderType = this.activeFilter;
                    }
                    this.showAddDialog = true;
                  })
              }
            }
            .width('100%')
            .padding({ bottom: 100 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .layoutWeight(1)
        .onRefreshing(() => { this.handlePullRefresh().catch(() => {}); })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(BG_PAPER)

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
      Image($r('app.media.icon_back'))
        .width(24).height(24)
        .fillColor(NEUTRAL_INK)
        .onClick(() => { router.back(); })

      Column() {
        Text('家庭提醒')
          .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK).fontFamily(FONT_FAMILY_SERIF)
        Text('记录每一件值得被记得的事')
          .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY).margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Text('消息')
        .fontSize(FONT_CAPTION)
        .fontColor(BRAND_RED)
        .onClick(() => {
          try {
            router.pushUrl({ url: 'pages/NotificationCenterPage' });
          } catch (_) {}
        })
    }
    .width('100%')
    .padding({ left: SPACE_MD, right: SPACE_MD, top: 12, bottom: 8 })
  }

  // ==================== 类型概览 ====================
  @Builder
  TypeOverview() {
    Row() {
      this.OverviewMini('生日', this.countByType('birthday'))
      this.OverviewMini('纪念日', this.countByType('anniversary'))
      this.OverviewMini('缴费', this.countByType('bill'))
      this.OverviewMini('购物', this.countByType('shopping'))
    }
    .width('100%')
    .padding({ left: SPACE_LG, right: SPACE_LG, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.SpaceBetween)
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
  }

  @Builder
  OverviewMini(label: string, count: number) {
    Column() {
      Text(`${count}`)
        .fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor(NEUTRAL_INK).fontFamily(FONT_FAMILY_SERIF)
      Text(label)
        .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY)
        .margin({ top: 2 })
    }
    .width('23%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Center)
  }

  // ==================== 筛选 chip ====================
  @Builder
  FilterChip(key: string, label: string) {
    Text(label)
      .fontSize(FONT_CAPTION)
      .fontColor(this.activeFilter === key ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
      .fontWeight(this.activeFilter === key ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: SPACE_SM, right: SPACE_SM, top: 6, bottom: 6 })
      .border({
        width: { bottom: this.activeFilter === key ? 2 : 0 },
        color: NEUTRAL_INK
      })
      .onClick(() => { this.activeFilter = key; })
  }

  // ==================== 分组标题 ====================
  @Builder
  SectionHeader(title: string, count: number) {
    Row() {
      Text(title)
        .fontSize(FONT_BODY_LARGE).fontWeight(FontWeight.Bold)
        .fontColor(NEUTRAL_INK).fontFamily(FONT_FAMILY_SERIF)
      Text(`${count}`)
        .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
        .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: SPACE_LG, right: SPACE_LG, top: 14, bottom: 4 })
  }

  // ==================== 提醒卡片 ====================
  @Builder
  ReminderCard(r: Reminder) {
    Row() {
      if (this.isOverdue(r) && !r.isCompleted) {
        Column().width(3).height('100%').backgroundColor(BRAND_RED)
          .margin({ right: 12 })
      }

      if (getReminderIconRes(r.reminderType) !== null) {
        Image(getReminderIconRes(r.reminderType) as Resource)
          .width(18).height(18)
          .fillColor(this.isOverdue(r) && !r.isCompleted ? SEMANTIC_ERROR : NEUTRAL_INK_TERTIARY)
          .margin({ right: 12 })
      } else {
        Text(this.getTypeMeta(r.reminderType).icon)
          .fontSize(18).fontColor(NEUTRAL_INK_TERTIARY)
          .margin({ right: 12 })
      }

      Column() {
        Row() {
          Text(r.title)
            .fontSize(FONT_BODY_LARGE).fontWeight(FontWeight.Medium)
            .fontColor(r.isCompleted ? NEUTRAL_INK_TERTIARY : NEUTRAL_INK)
            .decoration({ type: r.isCompleted ? TextDecorationType.LineThrough : TextDecorationType.None })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (r.isRecurring) {
            Text('重复')
              .fontSize(FONT_CAPTION_SM)
              .fontColor(NEUTRAL_INK_TERTIARY)
              .margin({ left: 6 })
          }
        }
        .width('100%')

        if (r.dueTime || r.description) {
          Row() {
            if (r.dueTime) {
              Text(this.formatDueTime(r.dueTime))
                .fontSize(FONT_CAPTION)
                .fontColor(this.isOverdue(r) ? SEMANTIC_ERROR : NEUTRAL_INK_SECONDARY)
                .fontFamily(FONT_FAMILY_SERIF)
            }
            if (r.dueTime && r.description) {
              Text(' · ').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
            }
            if (r.description) {
              Text(r.description)
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')
          .margin({ top: 3 })
        }

        if (this.recordCreatorLabel(r.creatorId) !== '') {
          Text(this.recordCreatorLabel(r.creatorId))
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (r.isCompleted) {
        Text('撤销')
          .fontSize(FONT_CAPTION).fontColor(SEMANTIC_WARNING)
          .padding({ left: 12 })
          .border({ width: { left: 0.5 }, color: DIVIDER })
          .onClick(() => { this.toggleCompleteAny(r, false); })
      } else {
        Text('完成')
          .fontSize(FONT_CAPTION)
          .fontColor(this.isOverdue(r) ? SEMANTIC_ERROR : BRAND_RED)
          .padding({ left: 12 })
          .border({ width: { left: 0.5 }, color: DIVIDER })
          .onClick(() => { this.toggleCompleteAny(r, true); })
      }
    }
    .width('100%')
    .padding({ left: SPACE_LG, right: SPACE_LG, top: 16, bottom: 16 })
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
    .backgroundColor(BG_PAPER)
    .opacity(r.isCompleted ? 0.6 : 1)
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
  private async toggleCompleteAny(r: Reminder, complete: boolean): Promise<void> {
    try {
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
    } catch (e) {
      console.error('[ReminderPage] toggleCompleteAny failed:', (e as Error)?.message ?? String(e));
    } finally {
      this.loadData();
    }
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
        fontColor: SEMANTIC_ERROR,
        action: () => {
          this.db.deleteReminder(r.id).then(() => { this.loadData(); }).catch(() => {});
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
    this.newVisibleUserIds = r.visibleMembers ? [...r.visibleMembers] : [];
    if (r.reminderType === 'shopping') {
      const desc = r.description ?? '';
      if (desc.startsWith('分类:')) {
        const parts = desc.substring(3).split('·');
        this.newItemCategory = parts[0] || '';
        this.newItemQuantity = parts[1] || '';
      }
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
        Row() {
          Text(this.editingReminderId ? '编辑提醒' : '新建家庭提醒')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK).fontFamily(FONT_FAMILY_SERIF)
            .layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_TERTIARY)
            .onClick(() => { this.closeAddDialog(); })
        }
        .width('100%')
        .margin({ bottom: 14 })

        Scroll() {
          Column() {
            Text('类型')
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              .width('100%').margin({ bottom: 6 })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(REMINDER_TYPES, (t: ReminderTypeOption) => {
                Text(t.label)
                  .fontSize(FONT_CAPTION)
                  .fontColor(this.newReminderType === t.type ? Color.White : NEUTRAL_INK_SECONDARY)
                  .fontWeight(this.newReminderType === t.type ? FontWeight.Bold : FontWeight.Normal)
                  .backgroundColor(this.newReminderType === t.type ? NEUTRAL_INK : BG_SUBTLE)
                  .borderRadius(0)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .margin(3)
                  .onClick(() => { this.newReminderType = t.type; })
              }, (t: ReminderTypeOption) => t.type)
            }
            .margin({ bottom: 14 })

            if (this.newReminderType === 'shopping') {
              Text('分类（必选）')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
                .width('100%').margin({ bottom: 6 })
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(SHOPPING_CATEGORIES, (cat: string) => {
                  Text(cat)
                    .fontSize(FONT_CAPTION)
                    .fontColor(this.newItemCategory === cat ? Color.White : NEUTRAL_INK)
                    .fontWeight(this.newItemCategory === cat ? FontWeight.Bold : FontWeight.Normal)
                    .backgroundColor(this.newItemCategory === cat ? NEUTRAL_INK : BG_SUBTLE)
                    .borderRadius(0)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .margin(3)
                    .onClick(() => { this.newItemCategory = cat; })
                }, (cat: string) => cat)
              }
              .width('100%')
              .margin({ bottom: 12 })

              Text('具体说明（选填）')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
                .width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newTitle, placeholder: '如：牛奶、鸡蛋、酱油' })
                .width('100%').padding(10).borderRadius(0)
                .backgroundColor(BG_SUBTLE)
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newTitle = v; })

              Text('数量（选填）')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
                .width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newItemQuantity, placeholder: '如：2盒、500g、1瓶' })
                .width('100%').padding(10).borderRadius(0)
                .backgroundColor(BG_SUBTLE)
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newItemQuantity = v; })
            } else {
              Text('标题')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
                .width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newTitle, placeholder: this.getTitlePlaceholder() })
                .width('100%').padding(10).borderRadius(0)
                .backgroundColor(BG_SUBTLE)
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newTitle = v; })

              Text('描述')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
                .width('100%').margin({ bottom: 6 })
              TextInput({ text: this.newDescription, placeholder: '补充信息（可选）' })
                .width('100%').padding(10).borderRadius(0)
                .backgroundColor(BG_SUBTLE)
                .margin({ bottom: 12 })
                .onChange((v: string) => { this.newDescription = v; })
            }
            Text('\u65E5\u671F\u4E0E\u65F6\u95F4')
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              .width('100%').margin({ bottom: 6 })
            Row({ space: 8 }) {
              Row() {
                Image($r('app.media.icon_clock'))
                  .width(16).height(16)
                  .fillColor(NEUTRAL_INK_TERTIARY)
                  .margin({ right: 6 })
                Text(this.newDueDate || '\u9009\u62E9\u65E5\u671F')
                  .fontSize(FONT_BODY)
                  .fontColor(this.newDueDate ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
                  .layoutWeight(1)
              }
              .layoutWeight(1)
              .padding(10).borderRadius(0).backgroundColor(BG_SUBTLE)
              .onClick(() => {
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
                this.getUIContext().showDatePickerDialog({
                  start: new Date('2000-01-01'),
                  end: new Date('2099-12-31'),
                  selected: initialDate,
                  onDateAccept: (value: Date) => {
                    const y = value.getFullYear();
                    const mo = value.getMonth() + 1;
                    const da = value.getDate();
                    this.newDueDate = \;
                  }
                })
              })
              Row() {
                Image($r('app.media.icon_clock'))
                  .width(16).height(16)
                  .fillColor(NEUTRAL_INK_TERTIARY)
                  .margin({ right: 6 })
                Text(this.newDueTimeValue || '\u65F6\u95F4')
                  .fontSize(FONT_BODY)
                  .fontColor(this.newDueTimeValue ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
                  .layoutWeight(1)
              }
              .layoutWeight(1)
              .padding(10).borderRadius(0).backgroundColor(BG_SUBTLE)
              .onClick(() => {
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
                    this.newDueTimeValue = \;
                  }
                })
              })
            }
            .width('100%').margin({ bottom: 12 })
            Text('日期与时间')
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              .width('100%').margin({ bottom: 6 })
            Row({ space: 8 }) {
              Row() {
                Image($r('app.media.icon_clock'))
                  .width(16).height(16)
                  .fillColor(NEUTRAL_INK_TERTIARY)
                  .margin({ right: 6 })
                Text(this.newDueDate || '选择日期')
                  .fontSize(FONT_BODY)
                  .fontColor(this.newDueDate ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
                  .layoutWeight(1)
              }
              .layoutWeight(1)
              .padding(10).borderRadius(0).backgroundColor(BG_SUBTLE)
              .onClick(() => {
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
                Image($r('app.media.icon_clock'))
                  .width(16).height(16)
                  .fillColor(NEUTRAL_INK_TERTIARY)
                  .margin({ right: 6 })
                Text(this.newDueTimeValue || '时间')
                  .fontSize(FONT_BODY)
                  .fontColor(this.newDueTimeValue ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
                  .layoutWeight(1)
              }
              .layoutWeight(1)
              .padding(10).borderRadius(0).backgroundColor(BG_SUBTLE)
              .onClick(() => {
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

            Row() {
              Text('重复提醒')
                .fontSize(FONT_BODY).fontColor(NEUTRAL_INK).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.newIsRecurring })
                .onChange((isOn: boolean) => { this.newIsRecurring = isOn; })
            }
            .width('100%').padding({ top: 4, bottom: 8 })

            if (this.newIsRecurring) {
              Row({ space: 6 }) {
                ForEach(RECURRENCE_OPTIONS, (item: RecurrenceOption) => {
                  Text(item.label)
                    .fontSize(FONT_CAPTION)
                    .fontColor(this.newRecurrenceRule === item.rule ? Color.White : NEUTRAL_INK_SECONDARY)
                    .backgroundColor(this.newRecurrenceRule === item.rule ? NEUTRAL_INK : BG_SUBTLE)
                    .borderRadius(0)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .onClick(() => { this.newRecurrenceRule = item.rule; })
                }, (item: RecurrenceOption) => item.rule)
              }
              .margin({ bottom: 12 })
            }

            Text('可见范围')
              .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              .width('100%').margin({ bottom: 6 })
            Row({ space: 6 }) {
              ForEach(VISIBILITY_OPTIONS, (item: VisibilityOption) => {
                Text(item.label)
                  .fontSize(FONT_CAPTION)
                  .fontColor(this.newVisibility === item.vis ? Color.White : NEUTRAL_INK_SECONDARY)
                  .backgroundColor(this.newVisibility === item.vis ? NEUTRAL_INK : BG_SUBTLE)
                  .borderRadius(0)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .onClick(() => { this.selectVisibility(item.vis); })
              }, (item: VisibilityOption) => `${item.vis}`)
            }
            .margin({ bottom: this.newVisibility === Visibility.SELECTED ? 10 : 18 })

            if (this.newVisibility === Visibility.SELECTED) {
              if (this.getShareCandidates().length === 0) {
                Text('家庭暂无其他成员，请先邀请家人加入，或选择家庭可见')
                  .fontSize(FONT_CAPTION).fontColor(SEMANTIC_WARNING)
                  .width('100%').margin({ bottom: 18 })
              } else {
                Text('选择可见成员（可多选，本人始终可见）')
                  .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
                  .width('100%').margin({ bottom: 6 })
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.getShareCandidates(), (m: FamilyMember) => {
                    Text(`${m.avatar} ${m.name}`)
                      .fontSize(FONT_CAPTION)
                      .fontColor(this.isMemberSelected(m.userId) ? Color.White : NEUTRAL_INK_SECONDARY)
                      .backgroundColor(this.isMemberSelected(m.userId) ? NEUTRAL_INK : BG_SUBTLE)
                      .borderRadius(0)
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .margin(3)
                      .onClick(() => { this.toggleVisibleMember(m.userId); })
                  }, (m: FamilyMember) => m.id)
                }
                .width('100%')
                .margin({ bottom: 12 })
              }
            }
          }
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY)
            .backgroundColor(Color.Transparent)
            .border({ width: 0.5, color: DIVIDER })
            .borderRadius(0).layoutWeight(1)
            .onClick(() => { this.closeAddDialog(); })
          Button(this.isSavingReminder ? '保存中...' : (this.editingReminderId ? '保存' : '添加'))
            .fontSize(FONT_BODY).fontColor(Color.White)
            .backgroundColor(NEUTRAL_INK)
            .borderRadius(0).layoutWeight(1)
            .enabled(!this.isSavingReminder)
            .onClick(async () => {
              if (this.isSavingReminder) return;
              this.isSavingReminder = true;
              try {
                if (this.newReminderType === 'shopping') {
                  if (!this.newItemCategory) {
                    AlertDialog.show({ message: '请选择购物分类' });
                    return;
                  }
                } else if (!this.newTitle) {
                  AlertDialog.show({ message: '请填写标题' });
                  return;
                }
                if (this.newVisibility === Visibility.SELECTED && this.newVisibleUserIds.length === 0) {
                  AlertDialog.show({
                    title: '提示',
                    message: this.getShareCandidates().length === 0
                      ? '家庭暂无其他成员可共享，请先邀请家人，或选择家庭可见'
                      : '请选择要共享的成员（可多选）'
                  });
                  return;
                }
                await this.saveReminder();
              } finally {
                this.isSavingReminder = false;
              }
            })
        }
        .margin({ top: 6 })
      }
      .width('92%')
      .constraintSize({ maxHeight: '85%' })
      .padding(20)
      .borderRadius(0)
      .backgroundColor(BG_CARD)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.closeAddDialog(); })
  }
