/**
 * 卡宝Home - 孩子事项页面（含成长记录）
 */
import { KidEvent, GrowthRecord } from '../model/KidEvent';
import { KidsViewModel } from '../viewmodel/KidsViewModel';
import { FamilyMember } from '../model/FamilyMember';
import { Visibility, FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { generateId } from '../common/Utils';
import { EmptyState } from '../components/EmptyState';
import { CardItem } from '../components/CardItem';
import { LocalDbService } from '../service/LocalDbService';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import router from '@ohos.router';

interface TimeFilterOption {
  key: string;
  label: string;
}

interface EventTypeOption {
  type: string;
  label: string;
}

interface RecurrenceRuleOption {
  rule: string;
  label: string;
}

@Entry
@Component
struct KidsPage {
  @State currentTab: number = 0;
  @State selectedKidIndex: number = 0;
  @State kidMembers: FamilyMember[] = [];
  @State events: KidEvent[] = [];
  @State growthRecords: GrowthRecord[] = [];
  @State showAddEvent: boolean = false;
  @State showAddGrowth: boolean = false;
  @State editingEventId: string = '';
  @State editingGrowthId: string = '';
  @State showEventDetail: boolean = false;
  @State showGrowthDetail: boolean = false;
  @State detailEvent: KidEvent | null = null;
  @State detailGrowth: GrowthRecord | null = null;
  @State timeFilter: string = 'all'; // 'week' | 'month' | 'all'
  @State newEventTitle: string = '';
  @State newEventType: string = 'school';
  @State newEventDate: string = '';
  @State newEventTimeValue: string = '';
  @State newEventLocation: string = '';
  @State newEventRecurring: boolean = false;
  @State newEventRecurrenceRule: string = 'weekly';
  @State newHeight: string = '';
  @State newWeight: string = '';
  @State newMilestone: string = '';
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themeLightBg: string = '#FFF5F0';
  @State themePrimary: string = '#E8654A';
  @State themeBorder: string = '#FFD4C2';

  private kidsVm: KidsViewModel = new KidsViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

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

  private loadData(): void {
    this.kidMembers = this.kidsVm.getKidMembers();
    // 防止 selectedKidIndex 越界（成员被删除后索引可能失效）
    if (this.selectedKidIndex >= this.kidMembers.length) {
      this.selectedKidIndex = 0;
    }
    const memberId = this.kidMembers.length > 0 ? this.kidMembers[this.selectedKidIndex].id : '';
    this.loadKidData(memberId);
  }

  private loadKidData(memberId: string): void {
    this.events = this.kidsVm.getEventsByMember(memberId);
    this.growthRecords = this.kidsVm.getGrowthRecords(memberId);
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Row() {
            Text('<')
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
          }.width(34).height(34).borderRadius(17)
          .backgroundColor(this.themeBorder)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { router.back(); })
          Text('📚 孩子事项').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
          Row() {
            Text('+').fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold)
          }.width(32).height(32).borderRadius(16)
          .backgroundColor(this.themePrimary)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.editingEventId = '';
            this.editingGrowthId = '';
            this.resetEventForm();
            this.resetGrowthForm();
            if (this.currentTab === 0) this.showAddEvent = true;
            else this.showAddGrowth = true;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        if (this.kidMembers.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.kidMembers, (kid: FamilyMember, index: number) => {
                Text(`${kid.avatar} ${kid.name}`)
                  .fontSize(15)
                  .fontColor(this.selectedKidIndex === index ? Color.White : '#333333')
                  .backgroundColor(this.selectedKidIndex === index ? kid.color : '#F5F5F5')
                  .borderRadius(20)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.selectedKidIndex = index as number;
                    this.loadKidData(kid.id);
                  })
              }, (kid: FamilyMember) => kid.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
        }

        Row() {
          Text('事项列表')
            .fontSize(17)
            .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? '#E65100' : '#999999')
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ bottom: 8 })
            .border({ width: { bottom: this.currentTab === 0 ? 2 : 0 }, color: '#E65100' })
            .onClick(() => { this.currentTab = 0; })
          Text('成长记录')
            .fontSize(17)
            .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 1 ? '#E65100' : '#999999')
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ bottom: 8 })
            .border({ width: { bottom: this.currentTab === 1 ? 2 : 0 }, color: '#E65100' })
            .onClick(() => { this.currentTab = 1; })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          if (this.currentTab === 0) {
            this.EventsTab()
          } else {
            this.GrowthTab()
          }
        }
        .layoutWeight(1)
        .padding(16)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.themeLightBg)

      if (this.showAddEvent) {
        this.AddEventOverlay()
      }
      if (this.showAddGrowth) {
        this.AddGrowthOverlay()
      }
      if (this.showEventDetail) {
        this.EventDetailOverlay()
      }
      if (this.showGrowthDetail) {
        this.GrowthDetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
  }

  @Builder
  EventsTab() {
    if (this.events.length === 0) {
      EmptyState({
        icon: '📚',
        title: '暂无事项',
        subtitle: '点击右上角添加孩子的事项',
        actionText: '+ 添加事项',
        buttonColor: this.themePrimary,
        onAction: () => { this.showAddEvent = true; }
      })
    } else {
      Column({ space: 6 }) {
        // 时间筛选
        Row({ space: 6 }) {
          ForEach([
            { key: 'week', label: '本周' },
            { key: 'month', label: '本月' },
            { key: 'all', label: '全部' }
          ], (item: TimeFilterOption) => {
            Text(item.label)
              .fontSize(15)
              .fontColor(this.timeFilter === item.key ? Color.White : '#666666')
              .backgroundColor(this.timeFilter === item.key ? '#E65100' : '#F5F5F5')
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .onClick(() => { this.timeFilter = item.key; })
          }, (item: TimeFilterOption) => item.key)
        }
        .width('100%')
        .margin({ bottom: 4 })

        Text('📋 近期事项').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')

        ForEach(this.getFilteredEvents(), (event: KidEvent) => {
          CardItem({
            icon: this.getTypeIcon(event.eventType),
            title: event.title,
            subtitle: `${this.getTypeLabel(event.eventType)} · ${event.eventTime.slice(0, 16).replace('T', ' ')}${event.location ? ' · ' + event.location : ''}`,
            rightLabel: event.isRecurring ? '🔄' : '',
            rightColor: '#FF9800',
            memberColor: this.getTypeColor(event.eventType),
            cardBackgroundColor: '#FFFFFF',
            onCardClick: () => {
              this.detailEvent = event;
              this.showEventDetail = true;
            },
            onLongPress: () => {
              if (!this.isCreator(event.creatorId)) {
                AlertDialog.show({ message: '只能删除自己创建的记录' });
                return;
              }
              AlertDialog.show({
                title: '确认删除',
                message: `确定要删除"${event.title}"吗？`,
                primaryButton: { value: '取消', action: () => {} },
                secondaryButton: {
                  value: '删除', action: async () => {
                    await this.kidsVm.deleteEvent(event.id);
                    const memberId = this.kidMembers.length > 0 ? this.kidMembers[this.selectedKidIndex].id : '';
                    this.loadKidData(memberId);
                  }
                }
              });
            }
          })
        }, (event: KidEvent) => event.id)

        Button('+ 添加事项')
          .fontSize(16).fontColor(Color.White).backgroundColor(this.themePrimary)
          .borderRadius(20).width('100%').margin({ top: 12 })
          .onClick(() => {
            this.editingEventId = '';
            this.resetEventForm();
            this.showAddEvent = true;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  GrowthTab() {
    if (this.growthRecords.length === 0) {
      EmptyState({
        icon: '📏',
        title: '暂无成长记录',
        subtitle: '记录孩子的身高体重和里程碑',
        actionText: '+ 记录成长',
        buttonColor: this.themePrimary,
        onAction: () => { this.showAddGrowth = true; }
      })
    } else {
      Column({ space: 8 }) {
        Row() {
          Column() {
            Text('最新数据').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333')
            Text(this.latestGrowthRecord.recordDate).fontSize(14).fontColor('#999999').margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.latestGrowthRecord.height > 0) {
            Column() {
              Text(`${this.latestGrowthRecord.height}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#E65100')
              Text('cm').fontSize(13).fontColor('#999999')
            }.margin({ right: 12 })
          }
          if (this.latestGrowthRecord.weight > 0) {
            Column() {
              Text(`${this.latestGrowthRecord.weight}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1565C0')
              Text('kg').fontSize(13).fontColor('#999999')
            }
          }
          if (this.latestGrowthRecord.headCircumference > 0) {
            Column() {
              Text(`${this.latestGrowthRecord.headCircumference}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#6A1B9A')
              Text('cm头围').fontSize(13).fontColor('#999999')
            }.margin({ left: 12 })
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .borderRadius(10)
        .backgroundColor(Color.White)

        // 里程碑
        if (this.growthMilestones.length > 0) {
          Text('🎯 里程碑').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')
          ForEach([...this.growthMilestones].reverse().slice(0, 5), (record: GrowthRecord) => {
            Row() {
              Text(`🎯 ${record.milestone}`).fontSize(16).fontColor('#E65100').layoutWeight(1)
              Text(record.recordDate).fontSize(14).fontColor('#999999')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(10)
            .backgroundColor('#FFF3E0')
          }, (record: GrowthRecord) => record.id)
        }

        Text('📊 历史记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')

        ForEach([...this.growthRecords].reverse(), (record: GrowthRecord) => {
          Row() {
            Text(record.recordDate).fontSize(16).fontColor('#666666').layoutWeight(1)
            if (record.height > 0) Text(`${record.height}cm`).fontSize(16).fontColor('#333333').margin({ right: 10 })
            if (record.weight > 0) Text(`${record.weight}kg`).fontSize(16).fontColor('#333333').margin({ right: 10 })
            if (record.headCircumference > 0) Text(`${record.headCircumference}cm`).fontSize(15).fontColor('#6A1B9A').margin({ right: 10 })
            if (record.milestone) Text(`🎯 ${record.milestone}`).fontSize(15).fontColor('#E65100')
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(10)
          .backgroundColor(Color.White)
          .onClick(() => {
            this.detailGrowth = record;
            this.showGrowthDetail = true;
          })
          .gesture(
            LongPressGesture()
              .onAction(() => {
                if (!this.isCreator(record.creatorId)) {
                  AlertDialog.show({ message: '只能删除自己创建的记录' });
                  return;
                }
                AlertDialog.show({
                  title: '确认删除',
                  message: '确定要删除这条成长记录吗？',
                  primaryButton: { value: '取消', action: () => {} },
                  secondaryButton: {
                    value: '删除', action: async () => {
                      await this.kidsVm.deleteGrowthRecord(record.id);
                      const memberId = this.kidMembers.length > 0 ? this.kidMembers[this.selectedKidIndex].id : '';
                      this.loadKidData(memberId);
                    }
                  }
                });
              })
          )
        }, (record: GrowthRecord) => record.id)

        Button('+ 记录成长')
          .fontSize(16).fontColor(Color.White).backgroundColor(this.themePrimary)
          .borderRadius(20).width('100%').margin({ top: 12 })
          .onClick(() => {
            this.editingGrowthId = '';
            this.resetGrowthForm();
            this.showAddGrowth = true;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  AddEventOverlay() {
    Column() {
      Column() {
        Row() {
          Text(this.editingEventId ? '编辑孩子事项' : '添加孩子事项').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999').onClick(() => {
            this.showAddEvent = false;
            this.editingEventId = '';
            this.resetEventForm();
          })
        }.width('100%').margin({ bottom: 16 })

        TextInput({ placeholder: '事项标题（如：家长会）' })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newEventTitle = v; })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach([
            { type: 'school', label: '🏫 学校' },
            { type: 'activity', label: '🎨 课外' },
            { type: 'medical', label: '🏥 医疗' },
            { type: 'other', label: '📌 其他' }
          ], (item: EventTypeOption) => {
            Text(item.label)
              .fontSize(14)
              .fontColor(this.newEventType === item.type ? Color.White : '#666666')
              .backgroundColor(this.newEventType === item.type ? this.getTypeColor(item.type) : '#F5F5F5')
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin(3)
              .onClick(() => { this.newEventType = item.type; })
          }, (item: EventTypeOption) => item.type)
        }
        .margin({ bottom: 8 })

        Row() {
          Text(this.newEventDate || '选择日期')
            .fontSize(14).fontColor(this.newEventDate ? '#333333' : '#999999').layoutWeight(1)
          Text('🗓️').fontSize(16)
        }.width('100%').padding(10).borderRadius(8).backgroundColor('#F5F5F5').margin({ bottom: 8 })
        .onClick(() => {
          DatePickerDialog.show({
            selected: new Date(),
            onAccept: (value: DatePickerResult) => {
              const m = (value.month ?? 0) + 1;
              const d = value.day ?? 1;
              this.newEventDate = `${value.year}-${m < 10 ? '0' + m : '' + m}-${d < 10 ? '0' + d : '' + d}`;
            }
          })
        })

        Row() {
          Text(this.newEventTimeValue || '选择时间')
            .fontSize(14).fontColor(this.newEventTimeValue ? '#333333' : '#999999').layoutWeight(1)
          Text('🕐').fontSize(16)
        }.width('100%').padding(10).borderRadius(8).backgroundColor('#F5F5F5').margin({ bottom: 8 })
        .onClick(() => {
          TimePickerDialog.show({
            selected: new Date(),
            useMilitaryTime: true,
            onAccept: (value: TimePickerResult) => {
              const h = value.hour as number;
              const min = value.minute as number;
              this.newEventTimeValue = `${h < 10 ? '0' + h : '' + h}:${min < 10 ? '0' + min : '' + min}`;
            }
          })
        })

        TextInput({ placeholder: '地点（可选）' })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newEventLocation = v; })

        Row() {
          Text('重复事项').fontSize(14).fontColor('#333333').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.newEventRecurring })
            .onChange((isOn: boolean) => { this.newEventRecurring = isOn; })
        }
        .width('100%')
        .padding({ top: 4, bottom: 8 })

        if (this.newEventRecurring) {
          Row({ space: 6 }) {
            ForEach([
              { rule: 'weekly', label: '每周' },
              { rule: 'monthly', label: '每月' },
              { rule: 'yearly', label: '每年' }
            ], (item: RecurrenceRuleOption) => {
              Text(item.label)
                .fontSize(12)
                .fontColor(this.newEventRecurrenceRule === item.rule ? Color.White : '#666666')
                .backgroundColor(this.newEventRecurrenceRule === item.rule ? '#E65100' : '#F5F5F5')
                .borderRadius(10)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .onClick(() => { this.newEventRecurrenceRule = item.rule; })
            }, (item: RecurrenceRuleOption) => item.rule)
          }
          .margin({ bottom: 8 })
        }

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
            .borderRadius(20).layoutWeight(1)
            .onClick(() => {
              this.showAddEvent = false;
              this.editingEventId = '';
              this.resetEventForm();
            })
          Button(this.editingEventId ? '保存' : '添加')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .onClick(async () => {
              if (!this.newEventTitle || !this.newEventDate) return;
              try {
                const now = new Date().toISOString();
                const userId = this.db.getCurrentUserId();
                const family = this.db.getCurrentFamily();
                const memberId = this.kidMembers.length > 0 ?
                  this.kidMembers[this.selectedKidIndex].id : '';
                if (this.editingEventId) {
                  const existing = this.events.find(e => e.id === this.editingEventId);
                  if (existing) {
                    const updated: KidEvent = {
                      id: existing.id,
                      familyId: existing.familyId,
                      creatorId: existing.creatorId,
                      visibility: existing.visibility,
                      visibleMembers: existing.visibleMembers,
                      version: existing.version + 1,
                      createdAt: existing.createdAt,
                      updatedAt: now,
                      forMemberId: memberId,
                      title: this.newEventTitle,
                      description: existing.description,
                      eventType: this.newEventType,
                      eventTime: this.newEventDate + 'T' + (this.newEventTimeValue || '00:00'),
                      location: this.newEventLocation,
                      isRecurring: this.newEventRecurring,
                      recurrenceRule: this.newEventRecurring ? this.newEventRecurrenceRule : '',
                      reminderSettings: existing.reminderSettings,
                      isSharedWith: existing.isSharedWith,
                      isCompleted: existing.isCompleted,
                      completedAt: existing.completedAt
                    };
                    await this.kidsVm.updateEvent(updated);
                  }
                } else {
                  const event: KidEvent = {
                    id: generateId('ke'),
                    familyId: family?.id ?? '',
                    creatorId: userId,
                    visibility: Visibility.FAMILY,
                    visibleMembers: [],
                    version: 1,
                    createdAt: now,
                    updatedAt: now,
                    forMemberId: memberId,
                    title: this.newEventTitle,
                    description: '',
                    eventType: this.newEventType,
                    eventTime: this.newEventDate + 'T' + (this.newEventTimeValue || '00:00'),
                    location: this.newEventLocation,
                    isRecurring: this.newEventRecurring,
                    recurrenceRule: this.newEventRecurring ? this.newEventRecurrenceRule : '',
                    reminderSettings: ['1day', '2hour'],
                    isSharedWith: [],
                    isCompleted: false,
                    completedAt: ''
                  };
                  await this.kidsVm.addEvent(event);
                }
                this.showAddEvent = false;
                this.editingEventId = '';
                this.resetEventForm();
                this.loadKidData(memberId);
              } catch (_) {
                this.showAddEvent = false;
              }
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  AddGrowthOverlay() {
    Column() {
      Column() {
        Row() {
          Text(this.editingGrowthId ? '编辑成长记录' : '记录成长').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999').onClick(() => {
            this.showAddGrowth = false;
            this.editingGrowthId = '';
            this.resetGrowthForm();
          })
        }.width('100%').margin({ bottom: 16 })

        TextInput({ placeholder: '身高(cm)' })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 8 })
          .type(InputType.Number)
          .onChange((v: string) => { this.newHeight = v; })

        TextInput({ placeholder: '体重(kg)' })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 8 })
          .type(InputType.Number)
          .onChange((v: string) => { this.newWeight = v; })

        TextInput({ placeholder: '里程碑（如：第一次走路，可选）' })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 12 })
          .onChange((v: string) => { this.newMilestone = v; })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
            .borderRadius(20).layoutWeight(1)
            .onClick(() => {
              this.showAddGrowth = false;
              this.editingGrowthId = '';
              this.resetGrowthForm();
            })
          Button('保存')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .onClick(async () => {
              try {
                const now = new Date().toISOString();
                const userId = this.db.getCurrentUserId();
                const family = this.db.getCurrentFamily();
                const memberId = this.kidMembers.length > 0 ?
                  this.kidMembers[this.selectedKidIndex].id : '';
                if (this.editingGrowthId) {
                  const existing = this.growthRecords.find(r => r.id === this.editingGrowthId);
                  if (existing) {
                    const updated: GrowthRecord = {
                      id: existing.id,
                      familyId: existing.familyId,
                      creatorId: existing.creatorId,
                      visibility: existing.visibility,
                      visibleMembers: existing.visibleMembers,
                      version: existing.version + 1,
                      createdAt: existing.createdAt,
                      updatedAt: now,
                      forMemberId: memberId,
                      height: parseFloat(this.newHeight) || 0,
                      weight: parseFloat(this.newWeight) || 0,
                      headCircumference: existing.headCircumference,
                      milestone: this.newMilestone,
                      recordDate: existing.recordDate,
                      photoUrl: existing.photoUrl,
                      note: existing.note
                    };
                    await this.db.updateGrowthRecord(updated);
                  }
                } else {
                  const record: GrowthRecord = {
                    id: generateId('gr'),
                    familyId: family?.id ?? '',
                    creatorId: userId,
                    visibility: Visibility.FAMILY,
                    visibleMembers: [],
                    version: 1,
                    createdAt: now,
                    updatedAt: now,
                    forMemberId: memberId,
                    height: parseFloat(this.newHeight) || 0,
                    weight: parseFloat(this.newWeight) || 0,
                    headCircumference: 0,
                    milestone: this.newMilestone,
                    recordDate: now.slice(0, 10),
                    photoUrl: '',
                    note: ''
                  };
                  await this.kidsVm.addGrowthRecord(record);
                }
                this.showAddGrowth = false;
                this.editingGrowthId = '';
                this.resetGrowthForm();
                this.loadKidData(memberId);
              } catch (_) {
                this.showAddGrowth = false;
              }
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 事项详情弹窗 ====================
  @Builder
  EventDetailOverlay() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          Text('📋 事项详情').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999').onClick(() => {
            this.showEventDetail = false;
            this.detailEvent = null;
          })
        }.width('100%').margin({ bottom: 16 })

        if (this.detailEvent) {
          // 事项标题
          Text(this.detailEvent.title)
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#333333')
            .width('100%').margin({ bottom: 12 })

          // 信息网格
          Column({ space: 12 }) {
            this.DetailRow('类型', `${this.getTypeIcon(this.detailEvent.eventType)} ${this.getTypeLabel(this.detailEvent.eventType)}`)
            this.DetailRow('时间', this.detailEvent.eventTime.slice(0, 16).replace('T', ' '))
            if (this.detailEvent.location) {
              this.DetailRow('地点', this.detailEvent.location)
            }
            if (this.detailEvent.isRecurring) {
              this.DetailRow('重复', '🔄 ' + (this.detailEvent.recurrenceRule === 'weekly' ? '每周' :
                this.detailEvent.recurrenceRule === 'monthly' ? '每月' : '每年'))
            }
            this.DetailRow('创建时间', this.detailEvent.createdAt.slice(0, 16).replace('T', ' '))
          }
          .width('100%')
          .padding(16)
          .borderRadius(10)
          .backgroundColor('#F8F8F8')
          .margin({ bottom: 16 })

          // 操作按钮
          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
              .borderRadius(20).layoutWeight(1)
              .onClick(() => {
                this.showEventDetail = false;
                this.detailEvent = null;
              })

            if (this.isCreator(this.detailEvent.creatorId)) {
              Button('编辑')
                .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
                .borderRadius(20).layoutWeight(1)
                .onClick(() => {
                  const event = this.detailEvent!;
                  this.editingEventId = event.id;
                  this.newEventTitle = event.title;
                  this.newEventType = event.eventType;
                  this.newEventDate = event.eventTime.slice(0, 10);
                  this.newEventTimeValue = event.eventTime.slice(11, 16);
                  this.newEventLocation = event.location;
                  this.newEventRecurring = event.isRecurring;
                  this.newEventRecurrenceRule = event.recurrenceRule || 'weekly';
                  this.showEventDetail = false;
                  this.detailEvent = null;
                  this.showAddEvent = true;
                })
            }
          }
          .width('100%')
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showEventDetail = false;
      this.detailEvent = null;
    })
  }

  // ==================== 成长记录详情弹窗 ====================
  @Builder
  GrowthDetailOverlay() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          Text('📏 成长记录详情').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999').onClick(() => {
            this.showGrowthDetail = false;
            this.detailGrowth = null;
          })
        }.width('100%').margin({ bottom: 16 })

        if (this.detailGrowth) {
          // 日期
          Text(this.detailGrowth.recordDate)
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#333333')
            .width('100%').margin({ bottom: 12 })

          // 数据指标
          Row({ space: 16 }) {
            if (this.detailGrowth.height > 0) {
              Column() {
                Text(`${this.detailGrowth.height}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#E65100')
                Text('身高 cm').fontSize(13).fontColor('#999999').margin({ top: 2 })
              }
              .padding(12).borderRadius(10).backgroundColor('#FFF3E0').layoutWeight(1)
            }
            if (this.detailGrowth.weight > 0) {
              Column() {
                Text(`${this.detailGrowth.weight}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#1565C0')
                Text('体重 kg').fontSize(13).fontColor('#999999').margin({ top: 2 })
              }
              .padding(12).borderRadius(10).backgroundColor('#E3F2FD').layoutWeight(1)
            }
            if (this.detailGrowth.headCircumference > 0) {
              Column() {
                Text(`${this.detailGrowth.headCircumference}`).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#6A1B9A')
                Text('头围 cm').fontSize(13).fontColor('#999999').margin({ top: 2 })
              }
              .padding(12).borderRadius(10).backgroundColor('#F3E5F5').layoutWeight(1)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          // 里程碑
          if (this.detailGrowth.milestone) {
            Row() {
              Text('🎯 ').fontSize(16)
              Text(this.detailGrowth.milestone).fontSize(15).fontColor('#E65100').layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .backgroundColor('#FFF3E0')
            .margin({ bottom: 12 })
          }

          // 记录时间
          Row() {
            Text('记录时间：').fontSize(13).fontColor('#999999')
            Text(this.detailGrowth.createdAt.slice(0, 16).replace('T', ' ')).fontSize(13).fontColor('#666666')
          }
          .width('100%')
          .margin({ bottom: 16 })

          // 操作按钮
          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
              .borderRadius(20).layoutWeight(1)
              .onClick(() => {
                this.showGrowthDetail = false;
                this.detailGrowth = null;
              })

            if (this.isCreator(this.detailGrowth.creatorId)) {
              Button('编辑')
                .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
                .borderRadius(20).layoutWeight(1)
                .onClick(() => {
                  const record = this.detailGrowth!;
                  this.editingGrowthId = record.id;
                  this.newHeight = record.height > 0 ? record.height.toString() : '';
                  this.newWeight = record.weight > 0 ? record.weight.toString() : '';
                  this.newMilestone = record.milestone;
                  this.showGrowthDetail = false;
                  this.detailGrowth = null;
                  this.showAddGrowth = true;
                })
            }
          }
          .width('100%')
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showGrowthDetail = false;
      this.detailGrowth = null;
    })
  }

  // 详情行辅助组件
  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor('#999999').width(64)
      Text(value).fontSize(14).fontColor('#333333').layoutWeight(1)
    }
    .width('100%')
  }

  private isCreator(creatorId: string): boolean {
    return creatorId === this.db.getCurrentUserId();
  }

  private getFilteredEvents(): KidEvent[] {
    if (this.timeFilter === 'all') return this.events;
    const now = new Date();
    const cutoff = new Date();
    if (this.timeFilter === 'week') {
      cutoff.setDate(now.getDate() - 7);
    } else {
      cutoff.setMonth(now.getMonth() - 1);
    }
    const cutoffStr = cutoff.toISOString();
    return this.events.filter(e => e.eventTime >= cutoffStr);
  }

  private resetEventForm(): void {
    this.newEventTitle = '';
    this.newEventType = 'school';
    this.newEventDate = '';
    this.newEventTimeValue = '';
    this.newEventLocation = '';
    this.newEventRecurring = false;
    this.newEventRecurrenceRule = 'weekly';
  }

  private resetGrowthForm(): void {
    this.newHeight = '';
    this.newWeight = '';
    this.newMilestone = '';
  }

  private getTypeIcon(type: string): string {
    const map: Record<string, string> = { 'school': '🏫', 'activity': '🎨', 'medical': '🏥', 'other': '📌' };
    return map[type] ?? '📌';
  }

  private getTypeLabel(type: string): string {
    const map: Record<string, string> = { 'school': '学校', 'activity': '课外', 'medical': '医疗', 'other': '其他' };
    return map[type] ?? type;
  }

  private getTypeColor(type: string): string {
    const map: Record<string, string> = { 'school': '#1565C0', 'activity': '#E65100', 'medical': '#C62828', 'other': '#2E7D32' };
    return map[type] ?? '#666666';
  }

  private get latestGrowthRecord(): GrowthRecord | undefined {
    if (this.growthRecords.length === 0) return undefined;
    return this.growthRecords[this.growthRecords.length - 1];
  }

  private get growthMilestones(): GrowthRecord[] {
    return this.growthRecords.filter(r => r?.milestone);
  }
}
