/**
 * 卡宝Home - 消息中心 / 提醒中心
 *
 * 定位：跨模块的「未办事项」聚合视图，做快速触达与一键完成。
 * 不负责创建——创建走「家庭提醒」(ReminderPage) 或对应模块页面。
 */
import { Reminder } from '../model/Reminder';
import { Medication, MedicationLog } from '../model/Medication';
import { LocalDbService } from '../service/LocalDbService';
import { FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { EmptyState } from '../components/EmptyState';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { HealthViewModel } from '../viewmodel/HealthViewModel';
import { formatDate } from '../common/Utils';
import router from '@ohos.router';

interface NotifyItem {
  id: string;
  icon: string;
  title: string;
  subtitle: string;
  color: string;
  isUrgent: boolean;
  isDone: boolean;
  category: string; // 'reminder' | 'medication' | 'shopping'
  timeSlot: string;
  routePage: string;
  rawData: Reminder | Medication | null;
  rawDataType: 'reminder' | 'medication' | '';
}

@Entry
@Component
struct NotificationCenterPage {
  @State reminders: Reminder[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State overdueItems: NotifyItem[] = [];
  @State todayItems: NotifyItem[] = [];
  @State upcomingItems: NotifyItem[] = [];
  @State medicationItems: NotifyItem[] = [];
  @State shoppingNotifyItems: NotifyItem[] = [];
  @State completedItems: NotifyItem[] = [];
  @State showCompleted: boolean = false;
  @State untakenMedCount: number = 0;
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themeLightBg: string = '#FFF5F0';
  @State themePrimary: string = '#E8654A';
  @State themeBorder: string = '#FFD4C2';
  @State activeFilter: string = 'all'; // all | overdue | today | medication | shopping

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();
  private healthVm: HealthViewModel = new HealthViewModel();

  aboutToAppear(): void {
    this.loadData();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themeLightBg = palette.lightBg;
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
  }

  onPageShow(): void {
    this.loadData();
  }

  private loadData(): void {
    this.reminders = this.db.getReminders() ?? [];
    this.familyMembers = this.familyVm.getFamilyMembers() ?? [];
    this.buildNotifyItems();
  }

  private buildNotifyItems(): void {
    const now = new Date();
    const todayStr = formatDate(now);
    const nowIso = now.toISOString();

    const weekLater = new Date(now);
    weekLater.setDate(now.getDate() + 7);
    const weekStr = formatDate(weekLater);

    const overdue: NotifyItem[] = [];
    const today: NotifyItem[] = [];
    const upcoming: NotifyItem[] = [];
    const completed: NotifyItem[] = [];
    const medications: NotifyItem[] = [];
    const shopping: NotifyItem[] = [];

    // —— 提醒事项 ——
    for (const r of this.reminders) {
      if (r.reminderType === 'shopping') continue;

      const route = 'pages/ReminderPage';

      if (r.isCompleted) {
        completed.push({
          id: `rem_${r.id}`, icon: this.getTypeIcon(r.reminderType),
          title: r.title, subtitle: r.dueTime ? r.dueTime.slice(0, 16).replace('T', ' ') : '',
          color: '#1565C0', isUrgent: false, isDone: true,
          category: r.reminderType === 'medication' ? 'medication' : 'reminder',
          rawData: r, timeSlot: '', rawDataType: 'reminder', routePage: route
        });
        continue;
      }
      if (!r.dueTime) continue;
      const dateStr = r.dueTime.slice(0, 10);
      const timeStr = r.dueTime.length > 10 ? r.dueTime.slice(11, 16) : '';

      if (r.reminderType === 'medication') {
        medications.push({
          id: `rem_${r.id}`, icon: '💊',
          title: r.title, subtitle: timeStr,
          color: '#FF9800', isUrgent: r.dueTime < nowIso, isDone: false,
          category: 'medication', rawData: r, timeSlot: timeStr,
          rawDataType: 'reminder', routePage: 'pages/HealthPage'
        });
        continue;
      }

      const item: NotifyItem = {
        id: `rem_${r.id}`, icon: this.getTypeIcon(r.reminderType),
        title: r.title, subtitle: timeStr,
        color: '#1565C0', isUrgent: r.dueTime < nowIso, isDone: false,
        category: 'reminder', rawData: r, timeSlot: '',
        rawDataType: 'reminder', routePage: route
      };
      if (dateStr < todayStr) {
        overdue.push(item);
      } else if (dateStr === todayStr) {
        today.push(item);
      } else if (dateStr <= weekStr) {
        upcoming.push(item);
      }
    }

    // —— 今日用药 ——
    const activeMeds = (this.db.getMedications() ?? []).filter((m: Medication) => {
      if (!m.isActive) return false;
      if (m.startDate && todayStr < m.startDate) return false;
      if (m.endDate && todayStr > m.endDate) return false;
      return true;
    });
    const todayLogs = this.db.getTodayLogs() ?? [];
    for (const med of activeMeds) {
      const member = this.familyMembers.find((m: FamilyMember) => m.id === med.forMemberId);
      for (const slot of med.timeSlots) {
        const isTaken = todayLogs.some((l: MedicationLog) =>
          l.medicationId === med.id && l.timeSlot === slot && (l.status === 'taken' || l.status === 'late'));
        const isMissed = !isTaken && (() => {
          const currentMinutes = now.getHours() * 60 + now.getMinutes();
          const parts = slot.split(':');
          const slotMinutes = parseInt(parts[0]) * 60 + (parts.length > 1 ? parseInt(parts[1]) : 0);
          return currentMinutes > slotMinutes + 120;
        })();
        medications.push({
          id: `med_${med.id}_${slot}`, icon: isTaken ? '✅' : (isMissed ? '⚠️' : '💊'),
          title: `${member?.name ?? '家人'} · ${med.medicineName}`,
          subtitle: `${med.dosage} · ${slot}`,
          color: isTaken ? '#4CAF50' : (isMissed ? '#C62828' : '#FF9800'),
          isUrgent: isMissed, isDone: isTaken, category: 'medication',
          rawData: med, timeSlot: slot, rawDataType: 'medication',
          routePage: 'pages/HealthPage'
        });
      }
    }

    // —— 购物提醒 ——
    const shoppingReminders = this.reminders.filter(r => r.reminderType === 'shopping');
    for (const r of shoppingReminders) {
      if (r.isCompleted) {
        completed.push({
          id: `shop_${r.id}`, icon: '🛒',
          title: r.title, subtitle: r.description || '',
          color: '#2E7D32', isUrgent: false, isDone: true,
          category: 'shopping', rawData: r, timeSlot: '',
          rawDataType: 'reminder', routePage: 'pages/ReminderPage'
        });
      } else {
        shopping.push({
          id: `shop_${r.id}`, icon: '🛒',
          title: r.title, subtitle: r.description || '',
          color: '#2E7D32', isUrgent: false, isDone: false,
          category: 'shopping', rawData: r, timeSlot: '',
          rawDataType: 'reminder', routePage: 'pages/ReminderPage'
        });
      }
    }

    this.overdueItems = overdue;
    this.todayItems = today;
    this.upcomingItems = upcoming;
    this.medicationItems = medications;
    this.shoppingNotifyItems = shopping;
    this.completedItems = completed;
    this.untakenMedCount = medications.filter(i => !i.isDone).length;
  }

  private isCreator(creatorId: string): boolean {
    return creatorId === this.db.getCurrentUserId();
  }

  private refreshData(): void {
    this.loadData();
  }

  build() {
    Column() {
      // —— 顶栏 ——
      Row() {
        Row() {
          Text('<').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { router.back(); })

        Column() {
          Text('🔔 消息中心').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold)
          Text('未办事项一站触达').fontSize(11).fontColor('#999999').margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Row() {
          Text('➕').fontSize(18)
        }
        .width(34).height(34).borderRadius(17)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { router.pushUrl({ url: 'pages/ReminderPage' }); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // —— 统计 Chip：可点筛选 ——
      Row() {
        this.StatChip('🔴', this.overdueItems.length, '已过期', '#FFEBEE', '#D32F2F', 'overdue')
        this.StatChip('📅', this.todayItems.length, '今日', '#E3F2FD', '#1565C0', 'today')
        this.StatChip('💊', this.untakenMedCount, '用药', '#FFF8E1', '#FF9800', 'medication')
        this.StatChip('🛒', this.shoppingNotifyItems.length, '购物', '#E8F5E9', '#2E7D32', 'shopping')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 6 })
      .justifyContent(FlexAlign.SpaceBetween)

      // —— 筛选指示条 ——
      if (this.activeFilter !== 'all') {
        Row() {
          Text(`筛选：${this.getFilterLabel(this.activeFilter)}`)
            .fontSize(12).fontColor(this.themePrimary)
          Text(' · 全部')
            .fontSize(12).fontColor('#999999')
            .onClick(() => { this.activeFilter = 'all'; })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })
      }

      // —— 聚合列表 ——
      Scroll() {
        Column({ space: 0 }) {
          if (this.totalActiveCount === 0 && this.completedItems.length === 0) {
            EmptyState({
              icon: '🎉',
              title: '一切都已处理',
              subtitle: '当前没有未办事项',
              actionText: '去创建家庭提醒',
              buttonColor: this.themePrimary,
              onAction: () => { router.pushUrl({ url: 'pages/ReminderPage' }); }
            })
          } else {
            if ((this.activeFilter === 'all' || this.activeFilter === 'overdue') && this.overdueItems.length > 0) {
              this.SectionHeader('🔴 已过期', this.overdueItems.length, '#D32F2F')
              ForEach(this.overdueItems, (item: NotifyItem) => {
                this.NotifyCard(item)
              }, (item: NotifyItem) => item.id)
            }

            if ((this.activeFilter === 'all' || this.activeFilter === 'today') && this.todayItems.length > 0) {
              this.SectionHeader('📅 今日', this.todayItems.length, '#1565C0')
              ForEach(this.todayItems, (item: NotifyItem) => {
                this.NotifyCard(item)
              }, (item: NotifyItem) => item.id)
            }

            if (this.activeFilter === 'all' && this.upcomingItems.length > 0) {
              this.SectionHeader('🔜 近7日', this.upcomingItems.length, '#546E7A')
              ForEach(this.upcomingItems, (item: NotifyItem) => {
                this.NotifyCard(item)
              }, (item: NotifyItem) => item.id)
            }

            if ((this.activeFilter === 'all' || this.activeFilter === 'medication') && this.medicationItems.length > 0) {
              this.SectionHeader('💊 今日用药', this.untakenMedCount, '#FF9800')
              ForEach(this.medicationItems, (item: NotifyItem) => {
                this.NotifyCard(item)
              }, (item: NotifyItem) => item.id)
            }

            if ((this.activeFilter === 'all' || this.activeFilter === 'shopping') && this.shoppingNotifyItems.length > 0) {
              this.SectionHeader('🛒 待买', this.shoppingNotifyItems.length, '#2E7D32')
              ForEach(this.shoppingNotifyItems, (item: NotifyItem) => {
                this.NotifyCard(item)
              }, (item: NotifyItem) => item.id)
            }

            if (this.activeFilter === 'all' && this.completedItems.length > 0) {
              Row() {
                Text('✅ 已完成').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#999999')
                Text(`${this.completedItems.length}项`).fontSize(14).fontColor('#BBBBBB').margin({ left: 6 })
                Text(this.showCompleted ? '▲' : '▼').fontSize(12).fontColor('#BBBBBB').margin({ left: 4 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 4 })
              .onClick(() => { this.showCompleted = !this.showCompleted; })

              if (this.showCompleted) {
                ForEach(this.completedItems, (item: NotifyItem) => {
                  this.NotifyCard(item)
                }, (item: NotifyItem) => item.id)
              }
            }
          }
        }
        .width('100%')
        .padding({ bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.themeLightBg)
  }

  @Builder
  StatChip(icon: string, count: number, label: string, bgColor: string, textColor: string, filterKey: string) {
    Column() {
      Text(icon).fontSize(18)
      Text(`${count}`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(textColor).margin({ top: 2 })
      Text(label).fontSize(10).fontColor(textColor).margin({ top: 2 })
    }
    .width('23%')
    .padding({ top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor(bgColor)
    .alignItems(HorizontalAlign.Center)
    .border({
      width: this.activeFilter === filterKey ? 2 : 0,
      color: textColor
    })
    .onClick(() => {
      this.activeFilter = this.activeFilter === filterKey ? 'all' : filterKey;
    })
  }

  @Builder
  SectionHeader(title: string, count: number, color: string) {
    Row() {
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333')
      if (count > 0) {
        Text(`${count}`)
          .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Bold)
          .backgroundColor(color)
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 4 })
  }

  @Builder
  NotifyCard(item: NotifyItem) {
    Row() {
      Text(item.icon).fontSize(22).margin({ right: 12 })

      Column() {
        Text(item.title)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(item.isDone ? '#999999' : '#333333')
          .decoration({ type: item.isDone ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.subtitle) {
          Text(item.subtitle)
            .fontSize(14).fontColor(item.isUrgent && !item.isDone ? '#D32F2F' : '#888888')
            .margin({ top: 3 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作
      if (item.isDone) {
        Text('撤销')
          .fontSize(13).fontColor('#FF9800').backgroundColor('#FFF8E1')
          .borderRadius(8).padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => { this.handleMarkUndone(item); })
      } else {
        Row() {
          Text('✓').fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Bold)
        }
        .width(32).height(32).borderRadius(16)
        .backgroundColor(item.isUrgent ? '#D32F2F' : this.themePrimary)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.handleMarkDone(item); })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(12)
    .backgroundColor(item.isUrgent && !item.isDone ? '#FFF5F5' : Color.White)
    .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
    .opacity(item.isDone ? 0.6 : 1)
    .margin({ left: 12, right: 12, top: 4, bottom: 4 })
    .onClick(() => {
      // 跳转到对应模块页面（快速触达）
      if (item.routePage) {
        try { router.pushUrl({ url: item.routePage }); } catch (_) {}
      }
    })
  }

  private handleMarkDone(item: NotifyItem): void {
    if (item.category === 'reminder' || item.category === 'shopping') {
      const r = item.rawData as Reminder;
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
        isCompleted: true, completedAt: now, reminderSettings: r.reminderSettings
      };
      this.db.updateReminder(updated).then(() => { this.refreshData(); });
    } else if (item.category === 'medication') {
      if (item.rawDataType === 'reminder') {
        const r = item.rawData as Reminder;
        const now = new Date().toISOString();
        const updated: Reminder = {
          id: r.id, familyId: r.familyId, creatorId: r.creatorId,
          visibility: r.visibility, visibleMembers: r.visibleMembers,
          version: r.version + 1, createdAt: r.createdAt, updatedAt: now,
          title: r.title, description: r.description, reminderType: r.reminderType,
          dueTime: r.dueTime, isRecurring: r.isRecurring, recurrenceRule: r.recurrenceRule,
          isCompleted: true, completedAt: now, reminderSettings: r.reminderSettings
        };
        this.db.updateReminder(updated).then(() => { this.refreshData(); });
      } else if (item.rawDataType === 'medication') {
        const med = item.rawData as Medication;
        const slot = item.timeSlot || (med.timeSlots.length > 0 ? med.timeSlots[0] : '08:00');
        this.healthVm.confirmTaken(med.id, slot).then(() => { this.refreshData(); });
      }
    }
  }

  private handleMarkUndone(item: NotifyItem): void {
    if (item.category === 'reminder' || item.category === 'shopping' ||
        (item.category === 'medication' && item.rawDataType === 'reminder')) {
      const r = item.rawData as Reminder;
      if (!this.isCreator(r.creatorId)) return;
      const updated: Reminder = {
        id: r.id, familyId: r.familyId, creatorId: r.creatorId,
        visibility: r.visibility, visibleMembers: r.visibleMembers,
        version: r.version + 1, createdAt: r.createdAt, updatedAt: new Date().toISOString(),
        title: r.title, description: r.description, reminderType: r.reminderType,
        dueTime: r.dueTime, isRecurring: r.isRecurring, recurrenceRule: r.recurrenceRule,
        isCompleted: false, completedAt: '', reminderSettings: r.reminderSettings
      };
      this.db.updateReminder(updated).then(() => { this.refreshData(); });
    } else if (item.category === 'medication' && item.rawDataType === 'medication') {
      const med = item.rawData as Medication;
      const slot = item.timeSlot || (med.timeSlots.length > 0 ? med.timeSlots[0] : '08:00');
      this.db.deleteTodayMedicationLog(med.id, slot).then(() => { this.refreshData(); });
    }
  }

  private getTypeIcon(type: string): string {
    const map: Record<string, string> = {
      'anniversary': '❤️', 'bill': '💰', 'birthday': '🎂',
      'family': '👨‍👩‍👧', 'shopping': '🛒', 'todo': '📌',
      'medication': '💊', 'other': '📎'
    };
    return map[type] ?? '📌';
  }

  private getFilterLabel(key: string): string {
    const map: Record<string, string> = {
      'overdue': '已过期', 'today': '今日',
      'medication': '用药', 'shopping': '购物'
    };
    return map[key] ?? key;
  }

  private get totalActiveCount(): number {
    return this.overdueItems.length + this.todayItems.length +
      this.upcomingItems.length + this.medicationItems.length + this.shoppingNotifyItems.length;
  }
}
