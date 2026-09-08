/**
 * 卡宝Home - 孩子事项页面（含成长记录）
 * 方向 C · 极简编辑：纸白底 + 墨黑正文 + flat 列表 + 衬线标题 + 文本动作
 */
import { KidEvent, GrowthRecord } from '../model/KidEvent';
import {
  BG_PAPER, BG_CARD, BG_SUBTLE, DIVIDER,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, BRAND_RED_LG,
  SEMANTIC_SUCCESS, SEMANTIC_WARNING, SEMANTIC_ERROR, SEMANTIC_INFO, MIST_PURPLE,
  WARNING_BG, INFO_BG,
  FONT_FAMILY_SERIF, FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_CAPTION_SM,
  FONT_TITLE, FONT_SUBTITLE, SPACE_MD, SPACE_LG,
  getModuleIconRes
} from '../common/DesignTokens';
import { KidsViewModel } from '../viewmodel/KidsViewModel';
import { FamilyMember } from '../model/FamilyMember';
import { FontSizeMode, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import { generateId, formatIsoToLocal, creatorDisplayLabel } from '../common/Utils';
import { EmptyState } from '../components/EmptyState';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import router from '@ohos.router';
import { curves } from '@kit.ArkUI';

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
  @State isRefreshing: boolean = false;
  @State selectedKidIndex: number = 0;
  @State kidMembers: FamilyMember[] = [];
  /** 家庭成员（解析记录创建人显示名用） */
  @State familyMembers: FamilyMember[] = [];
  @State events: KidEvent[] = [];
  @State growthRecords: GrowthRecord[] = [];
  @State showAddEvent: boolean = false;
  @State isSavingEvent: boolean = false;
  @State showAddGrowth: boolean = false;
  @State isSavingGrowth: boolean = false;
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

  private kidsVm: KidsViewModel = new KidsViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    this.loadData();
    this.familyMembers = this.familyVm.getFamilyMembers();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
  }

  /**
   * 下拉刷新：先从云端强制拉取合并（家人新记录/编辑即时可见），再重载本地列表。
   * 无家庭或云端不可用时仅重载本地，不做无谓请求。
   */
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

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
  }

  build() {
    Stack() {
      Column() {
        // —— 顶栏 ——
        Row() {
          Row() {
            Image($r('app.media.icon_back'))
              .width(18).height(18)
              .fillColor(NEUTRAL_INK)
          }
          .width(40).height(40)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { router.back(); })

          Row() {
            Image(getModuleIconRes('kids'))
              .width(16).height(16)
              .fillColor(BRAND_RED_LG)
              .margin({ right: 6 })
            Text('孩子事项')
              .fontFamily(FONT_FAMILY_SERIF)
              .fontSize(this.titleFontSize)
              .fontWeight(FontWeight.Bold)
              .fontColor(NEUTRAL_INK)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)

          Text('+')
            .fontSize(20)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
          }
          .width(32).height(32)
          .borderRadius(0)
          .backgroundColor(NEUTRAL_INK)
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
      .padding({ left: SPACE_MD, right: SPACE_MD, top: 12, bottom: 8 })

        if (this.kidMembers.length > 0) {
          Scroll() {
            Row({ space: 0 }) {
              ForEach(this.kidMembers, (kid: FamilyMember, index: number) => {
                Text(kid.name)
                  .fontSize(FONT_BODY)
                  .fontColor(this.selectedKidIndex === index ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
                  .fontWeight(this.selectedKidIndex === index ? FontWeight.Bold : FontWeight.Normal)
                  .padding({ left: 0, right: SPACE_MD, top: 8, bottom: 8 })
                  .border({ width: { bottom: this.selectedKidIndex === index ? 2 : 0 }, color: NEUTRAL_INK })
                  .onClick(() => {
                    this.selectedKidIndex = index as number;
                    this.loadKidData(kid.id);
                  })
              }, (kid: FamilyMember) => kid.id + '_' + kid.updatedAt)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: SPACE_MD, right: SPACE_MD, bottom: 8 })
        }

        Row() {
          Text('事项列表')
            .fontSize(FONT_SUBTITLE)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ bottom: 8 })
            .border({ width: { bottom: this.currentTab === 0 ? 2 : 0.5 }, color: this.currentTab === 0 ? NEUTRAL_INK : DIVIDER })
            .onClick(() => { this.currentTab = 0; })
          Text('成长记录')
            .fontSize(FONT_SUBTITLE)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 1 ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ bottom: 8 })
            .border({ width: { bottom: this.currentTab === 1 ? 2 : 0.5 }, color: this.currentTab === 1 ? NEUTRAL_INK : DIVIDER })
            .onClick(() => { this.currentTab = 1; })
        }
        .width('100%')
        .padding({ left: SPACE_MD, right: SPACE_MD })

        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll() {
            if (this.currentTab === 0) {
              this.EventsTab()
            } else {
              this.GrowthTab()
            }
          }
          .layoutWeight(1)
          .padding(SPACE_MD)
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
        buttonColor: BRAND_RED,
        onAction: () => { this.showAddEvent = true; }
      })
    } else {
      Column({ space: 0 }) {
        // 时间筛选 — flat text tabs
        Row({ space: SPACE_MD }) {
          ForEach([
            { key: 'week', label: '本周' },
            { key: 'month', label: '本月' },
            { key: 'all', label: '全部' }
          ], (item: TimeFilterOption) => {
            Text(item.label)
              .fontSize(FONT_CAPTION)
              .fontColor(this.timeFilter === item.key ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
              .fontWeight(this.timeFilter === item.key ? FontWeight.Bold : FontWeight.Normal)
              .onClick(() => { this.timeFilter = item.key; })
          }, (item: TimeFilterOption) => item.key)
        }
        .width('100%')
        .margin({ bottom: 8 })

        Text('近期事项')
          .fontSize(FONT_SUBTITLE)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .width('100%')
          .margin({ bottom: 4 })

        ForEach(this.getFilteredEvents(), (event: KidEvent) => {
          Row() {
            Column() {
              Text(event.title)
                .fontSize(FONT_BODY_LARGE)
                .fontWeight(FontWeight.Medium)
                .fontColor(NEUTRAL_INK)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.getTypeLabel(event.eventType)} · ${event.eventTime.slice(0, 16).replace('T', ' ')}${event.location ? ' · ' + event.location : ''}`)
                .fontSize(FONT_BODY)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .margin({ top: 3 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 家人共享的事项标注创建人，便于看出谁创建的（本人创建的记录不标注）
              if (this.recordCreatorLabel(event.creatorId) !== '') {
                Text(this.recordCreatorLabel(event.creatorId))
                  .fontSize(FONT_CAPTION_SM)
                  .fontColor(NEUTRAL_INK_TERTIARY)
                  .margin({ top: 3 })
              }
              if (event.isRecurring) {
                Text('重复')
                  .fontSize(FONT_CAPTION_SM)
                  .fontColor(NEUTRAL_INK_TERTIARY)
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 0, right: 0, top: 14, bottom: 14 })
          .border({ width: { bottom: 0.5 }, color: DIVIDER })
          .backgroundColor(BG_PAPER)
          .onClick(() => {
            this.detailEvent = event;
            this.showEventDetail = true;
          })
          .gesture(
            LongPressGesture()
              .onAction(() => {
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
              })
          )
        }, (event: KidEvent) => event.id + '_' + event.updatedAt)

        Button('+ 添加事项')
          .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
          .borderRadius(0).width('100%').margin({ top: SPACE_LG })
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
        buttonColor: BRAND_RED,
        onAction: () => { this.showAddGrowth = true; }
      })
    } else {
      Column({ space: 0 }) {
        // 最新数据 — flat, serif numbers
        Row() {
          Column() {
            Text('最新数据')
              .fontSize(FONT_SUBTITLE)
              .fontFamily(FONT_FAMILY_SERIF)
              .fontWeight(FontWeight.Bold)
              .fontColor(NEUTRAL_INK)
            Text(this.getLatestGrowthRecord().recordDate)
              .fontSize(FONT_CAPTION)
              .fontColor(NEUTRAL_INK_SECONDARY)
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.getLatestGrowthRecord().height > 0) {
            Column() {
              Text(`${this.getLatestGrowthRecord().height}`)
                .fontSize(22).fontWeight(FontWeight.Bold)
                .fontFamily(FONT_FAMILY_SERIF)
                .fontColor(SEMANTIC_WARNING)
              Text('cm').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
            }.margin({ right: 12 })
          }
          if (this.getLatestGrowthRecord().weight > 0) {
            Column() {
              Text(`${this.getLatestGrowthRecord().weight}`)
                .fontSize(22).fontWeight(FontWeight.Bold)
                .fontFamily(FONT_FAMILY_SERIF)
                .fontColor(SEMANTIC_INFO)
              Text('kg').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
            }
          }
          if (this.getLatestGrowthRecord().headCircumference > 0) {
            Column() {
              Text(`${this.getLatestGrowthRecord().headCircumference}`)
                .fontSize(22).fontWeight(FontWeight.Bold)
                .fontFamily(FONT_FAMILY_SERIF)
                .fontColor(MIST_PURPLE)
              Text('cm头围').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
            }.margin({ left: 12 })
          }
        }
        .width('100%')
        .padding({ left: 0, right: 0, top: 12, bottom: 12 })
        .border({ width: { bottom: 0.5 }, color: DIVIDER })

        // 里程碑 — flat text, no bg pill
        if (this.getGrowthMilestones().length > 0) {
          Text('里程碑')
            .fontSize(FONT_SUBTITLE)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .width('100%')
            .margin({ top: 12, bottom: 4 })
          ForEach([...this.getGrowthMilestones()].reverse().slice(0, 5), (record: GrowthRecord) => {
            Row() {
              Text(record.milestone)
                .fontSize(FONT_BODY)
                .fontColor(SEMANTIC_WARNING)
                .layoutWeight(1)
              Text(record.recordDate)
                .fontSize(FONT_CAPTION)
                .fontColor(NEUTRAL_INK_SECONDARY)
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 10, bottom: 10 })
            .border({ width: { bottom: 0.5 }, color: DIVIDER })
          }, (record: GrowthRecord) => record.id + '_' + record.updatedAt)
        }

        Text('历史记录')
          .fontSize(FONT_SUBTITLE)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .width('100%')
          .margin({ top: 12, bottom: 4 })

        ForEach([...this.growthRecords].reverse(), (record: GrowthRecord) => {
          Column() {
            Row() {
              Text(record.recordDate)
                .fontSize(FONT_BODY)
                .fontFamily(FONT_FAMILY_SERIF)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .layoutWeight(1)
              if (record.height > 0) Text(`${record.height}cm`).fontSize(FONT_BODY).fontColor(NEUTRAL_INK).margin({ right: 10 })
              if (record.weight > 0) Text(`${record.weight}kg`).fontSize(FONT_BODY).fontColor(NEUTRAL_INK).margin({ right: 10 })
              if (record.headCircumference > 0) Text(`${record.headCircumference}cm`).fontSize(FONT_CAPTION).fontColor(MIST_PURPLE).margin({ right: 10 })
              if (record.milestone) Text(record.milestone).fontSize(FONT_CAPTION).fontColor(SEMANTIC_WARNING)
            }
            .width('100%')

            // 家人共享的成长记录标注创建人，便于看出谁创建的（本人创建的记录不标注）
            if (this.recordCreatorLabel(record.creatorId) !== '') {
              Text(this.recordCreatorLabel(record.creatorId))
                .fontSize(FONT_CAPTION_SM)
                .fontColor(NEUTRAL_INK_TERTIARY)
                .margin({ top: 3 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 0, right: 0, top: 12, bottom: 12 })
          .border({ width: { bottom: 0.5 }, color: DIVIDER })
          .backgroundColor(BG_PAPER)
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
        }, (record: GrowthRecord) => record.id + '_' + record.updatedAt)

        Button('+ 记录成长')
          .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
          .borderRadius(0).width('100%').margin({ top: SPACE_LG })
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
          Text(this.editingEventId ? '编辑孩子事项' : '添加孩子事项')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_SECONDARY).onClick(() => {
            this.showAddEvent = false;
            this.editingEventId = '';
            this.resetEventForm();
          })
        }.width('100%').margin({ bottom: SPACE_LG })

        TextInput({ placeholder: '事项标题（如：家长会）' })
          .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
          .backgroundColor(BG_SUBTLE)
          .onChange((v: string) => { this.newEventTitle = v; })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach([
            { type: 'school', label: '学校' },
            { type: 'activity', label: '课外' },
            { type: 'medical', label: '医疗' },
            { type: 'other', label: '其他' }
          ], (item: EventTypeOption) => {
            Text(item.label)
              .fontSize(FONT_BODY)
              .fontColor(this.newEventType === item.type ? Color.White : NEUTRAL_INK_SECONDARY)
              .backgroundColor(this.newEventType === item.type ? this.getTypeColor(item.type) : BG_SUBTLE)
              .borderRadius(0)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin(3)
              .onClick(() => { this.newEventType = item.type; })
          }, (item: EventTypeOption) => item.type)
        }
        .margin({ bottom: 8 })

        Row() {
          Text(this.newEventDate || '选择日期')
            .fontSize(FONT_BODY).fontColor(this.newEventDate ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY).layoutWeight(1)
        }.width('100%').padding(10).borderRadius(0).backgroundColor(BG_SUBTLE).margin({ bottom: 8 })
        .onClick(() => {
          DatePickerDialog.show({
            selected: this.newEventDate ? new Date(this.newEventDate) : new Date(),
            onAccept: (value: DatePickerResult) => {
              const m = (value.month ?? 0) + 1;
              const d = value.day ?? 1;
              this.newEventDate = `${value.year}-${m < 10 ? '0' + m : '' + m}-${d < 10 ? '0' + d : '' + d}`;
            }
          })
        })

        Row() {
          Text(this.newEventTimeValue || '选择时间')
            .fontSize(FONT_BODY).fontColor(this.newEventTimeValue ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY).layoutWeight(1)
        }.width('100%').padding(10).borderRadius(0).backgroundColor(BG_SUBTLE).margin({ bottom: 8 })
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
          .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
          .backgroundColor(BG_SUBTLE)
          .onChange((v: string) => { this.newEventLocation = v; })

        Row() {
          Text('重复事项').fontSize(FONT_BODY).fontColor(NEUTRAL_INK).layoutWeight(1)
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
                .fontSize(FONT_CAPTION)
                .fontColor(this.newEventRecurrenceRule === item.rule ? Color.White : NEUTRAL_INK_SECONDARY)
                .backgroundColor(this.newEventRecurrenceRule === item.rule ? NEUTRAL_INK : BG_SUBTLE)
                .borderRadius(0)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .onClick(() => { this.newEventRecurrenceRule = item.rule; })
            }, (item: RecurrenceRuleOption) => item.rule)
          }
          .margin({ bottom: 8 })
        }

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
            .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
            .onClick(() => {
              this.showAddEvent = false;
              this.editingEventId = '';
              this.resetEventForm();
            })
          Button(this.isSavingEvent ? '保存中...' : (this.editingEventId ? '保存' : '添加'))
            .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
            .borderRadius(0).layoutWeight(1)
            .enabled(!this.isSavingEvent)
            .onClick(async () => {
              if (this.isSavingEvent) return; // 防重复提交
              this.isSavingEvent = true;
              try {
                if (!this.newEventTitle || !this.newEventDate) return;
                const now = new Date().toISOString();
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
                  const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.KIDS);
                  const event: KidEvent = {
                    id: generateId('ke'),
                    familyId: family?.id ?? '',
                    creatorId: this.db.getCurrentMemberId(),
                    visibility: vis.visibility,
                    visibleMembers: vis.visibleMembers,
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
              } finally {
                this.isSavingEvent = false;
              }
            })
        }
      }
      .width('92%')
      .padding(20)
      .borderRadius(0)
      .backgroundColor(BG_CARD)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  AddGrowthOverlay() {
    Column() {
      Column() {
        Row() {
          Text(this.editingGrowthId ? '编辑成长记录' : '记录成长')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_SECONDARY).onClick(() => {
            this.showAddGrowth = false;
            this.editingGrowthId = '';
            this.resetGrowthForm();
          })
        }.width('100%').margin({ bottom: SPACE_LG })

        TextInput({ placeholder: '身高(cm)' })
          .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
          .backgroundColor(BG_SUBTLE)
          .type(InputType.Normal)
          .inputFilter('^\\d*\\.?\\d{0,1}$', (_value: string) => {})
          .onChange((v: string) => { this.newHeight = v; })

        TextInput({ placeholder: '体重(kg)' })
          .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
          .backgroundColor(BG_SUBTLE)
          .type(InputType.Normal)
          .inputFilter('^\\d*\\.?\\d{0,1}$', (_value: string) => {})
          .onChange((v: string) => { this.newWeight = v; })

        TextInput({ placeholder: '里程碑（如：第一次走路，可选）' })
          .width('100%').padding(10).borderRadius(0).margin({ bottom: 12 })
          .backgroundColor(BG_SUBTLE)
          .onChange((v: string) => { this.newMilestone = v; })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
            .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
            .onClick(() => {
              this.showAddGrowth = false;
              this.editingGrowthId = '';
              this.resetGrowthForm();
            })
          Button(this.isSavingGrowth ? '保存中...' : '保存')
            .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
            .borderRadius(0).layoutWeight(1)
            .enabled(!this.isSavingGrowth)
            .onClick(async () => {
              if (this.isSavingGrowth) return; // 防重复提交
              this.isSavingGrowth = true;
              try {
                const now = new Date().toISOString();
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
                  const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.KIDS);
                  const record: GrowthRecord = {
                    id: generateId('gr'),
                    familyId: family?.id ?? '',
                    creatorId: this.db.getCurrentMemberId(),
                    visibility: vis.visibility,
                    visibleMembers: vis.visibleMembers,
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
              } finally {
                this.isSavingGrowth = false;
              }
            })
        }
      }
      .width('92%')
      .padding(20)
      .borderRadius(0)
      .backgroundColor(BG_CARD)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 事项详情弹窗 ====================
  @Builder
  EventDetailOverlay() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          Text('事项详情')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_SECONDARY).onClick(() => {
            this.showEventDetail = false;
            this.detailEvent = null;
          })
        }.width('100%').margin({ bottom: SPACE_LG })

        if (this.detailEvent) {
          // 事项标题
          Text(this.detailEvent.title)
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .width('100%').margin({ bottom: 12 })

          // 信息网格
          Column({ space: 12 }) {
            this.DetailRow('类型', this.getTypeLabel(this.detailEvent.eventType))
            this.DetailRow('时间', this.detailEvent.eventTime.slice(0, 16).replace('T', ' '))
            if (this.detailEvent.location) {
              this.DetailRow('地点', this.detailEvent.location)
            }
            if (this.detailEvent.isRecurring) {
              this.DetailRow('重复', this.detailEvent.recurrenceRule === 'weekly' ? '每周' :
                this.detailEvent.recurrenceRule === 'monthly' ? '每月' : '每年')
            }
            this.DetailRow('创建时间', formatIsoToLocal(this.detailEvent.createdAt))
          }
          .width('100%')
          .padding(14)
          .borderRadius(0)
          .backgroundColor(BG_SUBTLE)
          .margin({ bottom: SPACE_LG })

          // 操作按钮
          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
              .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
              .onClick(() => {
                this.showEventDetail = false;
                this.detailEvent = null;
              })

            if (this.isCreator(this.detailEvent.creatorId)) {
              Button('编辑')
                .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
                .borderRadius(0).layoutWeight(1)
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
      .width('92%')
      .padding(20)
      .borderRadius(0)
      .backgroundColor(BG_CARD)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
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
          Text('成长记录详情')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_SECONDARY).onClick(() => {
            this.showGrowthDetail = false;
            this.detailGrowth = null;
          })
        }.width('100%').margin({ bottom: SPACE_LG })

        if (this.detailGrowth) {
          // 日期
          Text(this.detailGrowth.recordDate)
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .width('100%').margin({ bottom: 12 })

          // 数据指标 — flat, serif numbers
          Row({ space: 16 }) {
            if (this.detailGrowth.height > 0) {
              Column() {
                Text(`${this.detailGrowth.height}`)
                  .fontSize(28).fontWeight(FontWeight.Bold)
                  .fontFamily(FONT_FAMILY_SERIF)
                  .fontColor(SEMANTIC_WARNING)
                Text('身高 cm').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
              }
              .padding(12).borderRadius(0).backgroundColor(WARNING_BG).layoutWeight(1)
            }
            if (this.detailGrowth.weight > 0) {
              Column() {
                Text(`${this.detailGrowth.weight}`)
                  .fontSize(28).fontWeight(FontWeight.Bold)
                  .fontFamily(FONT_FAMILY_SERIF)
                  .fontColor(SEMANTIC_INFO)
                Text('体重 kg').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
              }
              .padding(12).borderRadius(0).backgroundColor(INFO_BG).layoutWeight(1)
            }
            if (this.detailGrowth.headCircumference > 0) {
              Column() {
                Text(`${this.detailGrowth.headCircumference}`)
                  .fontSize(28).fontWeight(FontWeight.Bold)
                  .fontFamily(FONT_FAMILY_SERIF)
                  .fontColor(MIST_PURPLE)
                Text('头围 cm').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
              }
              .padding(12).borderRadius(0).backgroundColor(BG_SUBTLE).layoutWeight(1)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          // 里程碑 — text only
          if (this.detailGrowth.milestone) {
            Row() {
              Text(this.detailGrowth.milestone)
                .fontSize(FONT_BODY)
                .fontColor(SEMANTIC_WARNING)
                .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .borderRadius(0)
            .backgroundColor(WARNING_BG)
            .margin({ bottom: 12 })
          }

          // 记录时间
          Row() {
            Text('记录时间：').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
            Text(formatIsoToLocal(this.detailGrowth.createdAt)).fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
          }
          .width('100%')
          .margin({ bottom: SPACE_LG })

          // 操作按钮
          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
              .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
              .onClick(() => {
                this.showGrowthDetail = false;
                this.detailGrowth = null;
              })

            if (this.isCreator(this.detailGrowth.creatorId)) {
              Button('编辑')
                .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
                .borderRadius(0).layoutWeight(1)
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
      .width('92%')
      .padding(20)
      .borderRadius(0)
      .backgroundColor(BG_CARD)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
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
      Text(label).fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).width(64)
      Text(value).fontSize(FONT_BODY).fontColor(NEUTRAL_INK).layoutWeight(1)
    }
    .width('100%')
  }

  /** 记录「创建人」标签：本人创建的记录不标注；他人记录显示「头像 昵称」，成员已离开则显示「家人」 */
  private recordCreatorLabel(creatorId: string): string {
    if (!creatorId || this.isCreator(creatorId)) return '';
    return creatorDisplayLabel(creatorId, this.familyMembers);
  }

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  private getFilteredEvents(): KidEvent[] {
    if (this.timeFilter === 'all') return this.events;
    const now = new Date();
    if (this.timeFilter === 'week') {
      // 本周：最近7天（含今天）
      const cutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7);
      const cutoffStr = this.formatLocalDate(cutoff);
      return this.events.filter(e => e.eventTime >= cutoffStr);
    } else {
      // 本月：当月1日起
      const cutoff = new Date(now.getFullYear(), now.getMonth(), 1);
      const cutoffStr = this.formatLocalDate(cutoff);
      return this.events.filter(e => e.eventTime >= cutoffStr);
    }
  }

  /** 格式化日期为本地时间字符串，与 eventTime 格式一致（YYYY-MM-DDThh:mm） */
  private formatLocalDate(d: Date): string {
    const y = d.getFullYear();
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${day}T00:00`;
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

  private getTypeLabel(type: string): string {
    const map: Record<string, string> = { 'school': '学校', 'activity': '课外', 'medical': '医疗', 'other': '其他' };
    return map[type] ?? type;
  }

  private getTypeColor(type: string): string {
    const map: Record<string, string> = { 'school': SEMANTIC_INFO, 'activity': SEMANTIC_WARNING, 'medical': SEMANTIC_ERROR, 'other': SEMANTIC_SUCCESS };
    return map[type] ?? NEUTRAL_INK_SECONDARY;
  }

  // 注意：不要用 TypeScript getter（`private get xxx()`），在 @Builder 中以属性形式访问
  // 会在某些 SDK 版本运行时崩溃（详见 arkts-pitfalls.md #15）。统一使用普通方法 + 括号调用。
  private getLatestGrowthRecord(): GrowthRecord {
    if (this.growthRecords.length === 0) return new GrowthRecord();
    return this.growthRecords[this.growthRecords.length - 1];
  }

  private getGrowthMilestones(): GrowthRecord[] {
    return this.growthRecords.filter(r => r?.milestone);
  }
}
