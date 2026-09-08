/**
 * 卡宝Home - 健康用药页面（服药确认+指标趋势+异常标记）
 * 方向 C · 极简编辑：纸白底 + 墨黑正文 + flat 列表 + 衬线标题 + 文本动作
 */
import { Visibility, FontSizeMode, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import {
  BG_PAPER, BG_CARD, BG_SUBTLE, DIVIDER,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, BRAND_RED_LG,
  SEMANTIC_SUCCESS, SEMANTIC_WARNING, SEMANTIC_ERROR, SEMANTIC_INFO, MIST_PURPLE,
  FONT_FAMILY_SERIF, FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_CAPTION_SM,
  FONT_TITLE, FONT_SUBTITLE, SPACE_MD, SPACE_LG,
  getModuleIconRes
} from '../common/DesignTokens';
import { FamilyMember } from '../model/FamilyMember';
import { Medication, MedicationLog } from '../model/Medication';
import { HealthMetric } from '../model/HealthMetric';
import { HealthViewModel } from '../viewmodel/HealthViewModel';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { EmptyState } from '../components/EmptyState';
import { TrendChart } from '../components/TrendChart';
import { generateId, formatDate, formatIsoToLocal, creatorDisplayLabel } from '../common/Utils';
import router from '@ohos.router';
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct HealthPage {
  @State currentTab: number = 0;
  @State isRefreshing: boolean = false;
  @State selectedMemberIndex: number = 0;
  @State familyMembers: FamilyMember[] = [];
  @State medications: Medication[] = [];
  @State todayLogs: MedicationLog[] = [];
  @State metrics: HealthMetric[] = [];
  @State showAddMedication: boolean = false;
  @State isSavingMed: boolean = false;
  @State showAddMetric: boolean = false;
  @State isSavingMetric: boolean = false;
  @State newMedName: string = '';
  @State newMedDosage: string = '';
  @State newMedFrequency: string = '';
  @State newMedStartDate: string = '';
  @State newMedEndDate: string = '';
  @State newMedTimeSlots: string = '';
  @State newMetricType: string = 'blood_pressure_systolic';
  @State newMetricValue: string = '';
  @State newMetricUnit: string = 'mmHg';
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State medTimeSlots: string[] = [];
  @State editingMedId: string = '';
  @State editingMetricId: string = '';
  @State showMedicationDetail: boolean = false;
  @State showMetricDetail: boolean = false;
  @State detailMedication: Medication | null = null;
  @State detailMetric: HealthMetric | null = null;
  @State trendRange: number = 7;
  @State showMemberPicker: boolean = false;
  @State pendingMedId: string = '';
  @State pendingMedTimeSlot: string = '';
  @State defaultMemberId: string = '';
  /** 创建/编辑用药时选中的服药人ID（成员ID） */
  @State newMedForMemberId: string = '';
  /** 可被指派为服药人的候选成员（来自健康模块共享范围） */
  @State shareableMembers: FamilyMember[] = [];

  private healthVm: HealthViewModel = new HealthViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();
  private metricTypeOptions: MetricTypeOption[] = [
    { type: 'blood_pressure_systolic', label: '收缩压' },
    { type: 'blood_pressure_diastolic', label: '舒张压' },
    { type: 'blood_sugar', label: '血糖' },
    { type: 'body_temp', label: '体温' },
    { type: 'heart_rate', label: '心率' }
  ];

  aboutToAppear(): void {
    this.familyMembers = this.healthVm.getMembersWithMedication();
    if (this.familyMembers.length === 0) {
      const family = this.db.getCurrentFamily();
      if (family) {
        this.familyMembers = this.db.getMembersByFamilyId(family.id);
      }
    }
    this.shareableMembers = this.healthVm.getHealthShareableMembers();
    this.todayLogs = this.healthVm.getTodayLogs();
    if (this.familyMembers.length > 0) {
      this.loadMemberData(this.familyMembers[this.selectedMemberIndex].id);
    }
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    this.applyFontMode();
  }

  private isMedicationTimeSlotMissed(medId: string, timeSlot: string): boolean {
    return !this.healthVm.isMedicationTaken(medId, timeSlot) && this.isSlotMissed(timeSlot);
  }

  private getOtherMedicationMembers(): FamilyMember[] {
    return this.familyMembers.filter((member: FamilyMember) => member.id !== this.defaultMemberId);
  }

  private applyFontMode(): void {
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    } else {
      this.fontSize = 16;
      this.titleFontSize = 20;
    }
  }

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  /** 获取某条服药记录的服药人名字 */
  private getTakenByName(medId: string, timeSlot: string): string {
    const log = this.todayLogs.find(l => l.medicationId === medId && l.timeSlot === timeSlot &&
      (l.status === 'taken' || l.status === 'late'));
    if (!log || !log.takenBy) return '';
    const member = this.familyMembers.find(m => m.id === log.takenBy);
    return member ? `${member.name}服` : '';
  }

  private getPendingMedDisplay(): string {
    const med = this.medications.find(m => m.id === this.pendingMedId);
    return med ? `${med.medicineName} ${med.dosage}` : '';
  }

  private loadMemberData(memberId: string): void {
    this.medications = this.healthVm.getMedicationsByMember(memberId);
    this.metrics = this.healthVm.getMetricsByMember(memberId);
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
      // 重载成员/今日服药/当前浏览成员的数据
      this.familyMembers = this.healthVm.getMembersWithMedication();
      if (this.familyMembers.length === 0) {
        const family = this.db.getCurrentFamily();
        if (family) {
          this.familyMembers = this.db.getMembersByFamilyId(family.id);
        }
      }
      this.shareableMembers = this.healthVm.getHealthShareableMembers();
      this.todayLogs = this.healthVm.getTodayLogs();
      if (this.familyMembers.length > 0) {
        this.loadMemberData(this.familyMembers[this.selectedMemberIndex].id);
      }
    }
  }

  /** 打开添加用药弹窗，初始化默认服药人 */
  private openAddMedicationDialog(): void {
    this.editingMedId = '';
    this.newMedName = '';
    this.newMedDosage = '';
    this.newMedFrequency = '';
    this.newMedStartDate = '';
    this.newMedEndDate = '';
    this.medTimeSlots = [];
    // 刷新共享成员列表（可能用户在 SettingsPage 改过共享配置）
    this.shareableMembers = this.healthVm.getHealthShareableMembers();
    // 默认服药人：当前正在浏览的成员（如果在共享范围内）；否则取共享范围第一位
    const currentMemberId = this.familyMembers.length > 0
      ? this.familyMembers[this.selectedMemberIndex].id : '';
    if (currentMemberId && this.shareableMembers.some(m => m.id === currentMemberId)) {
      this.newMedForMemberId = currentMemberId;
    } else {
      this.newMedForMemberId = this.shareableMembers.length > 0 ? this.shareableMembers[0].id : '';
    }
    this.showAddMedication = true;
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
            Image(getModuleIconRes('health'))
              .width(16).height(16)
              .fillColor(BRAND_RED_LG)
              .margin({ right: 6 })
            Text('健康用药')
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
            if (this.currentTab === 0) {
              this.openAddMedicationDialog();
            } else {
              this.editingMetricId = '';
              this.newMetricType = 'blood_pressure_systolic';
              this.newMetricValue = '';
              this.newMetricUnit = 'mmHg';
              this.showAddMetric = true;
            }
          })
      }
      .width('100%')
      .padding({ left: SPACE_MD, right: SPACE_MD, top: 12, bottom: 8 })

        // 成员切换 — flat text tabs
        if (this.familyMembers.length > 0) {
          Scroll() {
            Row({ space: 0 }) {
              ForEach(this.familyMembers, (member: FamilyMember, index: number) => {
                Text(member.name)
                  .fontSize(this.fontSize - 1)
                  .fontColor(this.selectedMemberIndex === index ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
                  .fontWeight(this.selectedMemberIndex === index ? FontWeight.Bold : FontWeight.Normal)
                  .padding({ left: 0, right: SPACE_MD, top: 8, bottom: 8 })
                  .border({ width: { bottom: this.selectedMemberIndex === index ? 2 : 0 }, color: NEUTRAL_INK })
                  .onClick(() => {
                    this.selectedMemberIndex = index as number;
                    this.loadMemberData(member.id);
                  })
              }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .padding({ left: SPACE_MD, right: SPACE_MD, bottom: 8 })
        }

        // 子Tab — flat underline
        Row() {
          Text('用药提醒')
            .fontSize(this.fontSize + 1)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
            .layoutWeight(1).textAlign(TextAlign.Center)
            .padding({ bottom: 8 })
            .border({ width: { bottom: this.currentTab === 0 ? 2 : 0.5 }, color: this.currentTab === 0 ? NEUTRAL_INK : DIVIDER })
            .onClick(() => { this.currentTab = 0; })
          Text('指标记录')
            .fontSize(this.fontSize + 1)
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
              this.MedicationTab()
            } else {
              this.MetricsTab()
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

      if (this.showAddMedication) {
        this.AddMedicationOverlay()
      }
      if (this.showAddMetric) {
        this.AddMetricOverlay()
      }
      if (this.showMedicationDetail) {
        this.MedicationDetailOverlay()
      }
      if (this.showMetricDetail) {
        this.MetricDetailOverlay()
      }
      if (this.showMemberPicker) {
        this.MemberPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
  }

  @Builder
  MedicationTab() {
    if (this.medications.length === 0) {
      EmptyState({
        icon: '💊',
        title: '暂无用药提醒',
        subtitle: '为家人添加吃药提醒',
        actionText: '+ 添加用药',
        buttonColor: BRAND_RED,
        onAction: () => {
          this.openAddMedicationDialog();
        }
      })
    } else {
      Column({ space: 0 }) {
        ForEach(this.medications, (med: Medication) => {
          ForEach(med.timeSlots, (timeSlot: string) => {
            Row() {
              // Status indicator — text only, no emoji
              Text(this.healthVm.isMedicationTaken(med.id, timeSlot) ? '✓' : (this.isMedicationTimeSlotMissed(med.id, timeSlot) ? '!' : '○'))
                .fontSize(18)
                .fontColor(this.healthVm.isMedicationTaken(med.id, timeSlot) ? SEMANTIC_SUCCESS : (this.isMedicationTimeSlotMissed(med.id, timeSlot) ? SEMANTIC_ERROR : NEUTRAL_INK_TERTIARY))
                .margin({ right: 12 })

              Column() {
                Text(`${med.medicineName} · ${med.dosage}`)
                  .fontWeight(FontWeight.Medium).fontSize(FONT_BODY_LARGE)
                  .fontColor(this.healthVm.isMedicationTaken(med.id, timeSlot) ? NEUTRAL_INK_SECONDARY : (this.isMedicationTimeSlotMissed(med.id, timeSlot) ? SEMANTIC_ERROR : NEUTRAL_INK))
                  .decoration({ type: this.healthVm.isMedicationTaken(med.id, timeSlot) ? TextDecorationType.LineThrough : TextDecorationType.None })
                Text(`${med.frequency} · ${timeSlot}`)
                  .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 3 })
                if (this.recordCreatorLabel(med.creatorId) !== '') {
                  Text(this.recordCreatorLabel(med.creatorId))
                    .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY).margin({ top: 2 })
                }
                if (this.healthVm.isMedicationLate(med.id, timeSlot)) {
                  Text('补服').fontSize(FONT_CAPTION).fontColor(SEMANTIC_WARNING).margin({ top: 2 })
                }
                if (this.isMedicationTimeSlotMissed(med.id, timeSlot)) {
                  Text('可能漏服').fontSize(FONT_CAPTION).fontColor(SEMANTIC_ERROR).margin({ top: 2 })
                }
                if (this.getTakenByName(med.id, timeSlot) !== '') {
                  Text(this.getTakenByName(med.id, timeSlot))
                    .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY).margin({ top: 2 })
                }
              }
              .alignItems(HorizontalAlign.Start).layoutWeight(1)

              // Right action — text-only, no bg pill
              if (this.healthVm.isMedicationTaken(med.id, timeSlot)) {
                Text(this.healthVm.isMedicationLate(med.id, timeSlot) ? '已补服' : '已服')
                  .fontSize(FONT_BODY).fontColor(SEMANTIC_SUCCESS)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              } else if (!this.healthVm.canConfirmMedication(med)) {
                Text(this.isMedicationTimeSlotMissed(med.id, timeSlot) ? '待补服' : '待服药')
                  .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_TERTIARY)
              } else if (this.isMedicationTimeSlotMissed(med.id, timeSlot)) {
                Text('补服')
                  .fontSize(FONT_BODY).fontColor(SEMANTIC_ERROR)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .onClick(() => {
                    this.pendingMedId = med.id;
                    this.pendingMedTimeSlot = timeSlot;
                    this.defaultMemberId = med.forMemberId;
                    this.showMemberPicker = true;
                  })
              } else {
                Text('服药')
                  .fontSize(FONT_BODY).fontColor(BRAND_RED)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .onClick(() => {
                    this.pendingMedId = med.id;
                    this.pendingMedTimeSlot = timeSlot;
                    this.defaultMemberId = med.forMemberId;
                    this.showMemberPicker = true;
                  })
              }
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 14, bottom: 14 })
            .border({ width: { bottom: 0.5 }, color: DIVIDER })
            .backgroundColor(BG_PAPER)
            .opacity(this.isMedicationActiveToday(med) ? 1 : 0.5)
            .onClick(() => {
              this.detailMedication = med;
              this.showMedicationDetail = true;
            })
            .gesture(
              LongPressGesture()
                .onAction(() => {
                  if (this.isCreator(med.creatorId)) {
                    AlertDialog.show({
                      title: '确认删除',
                      message: `确定删除「${med.medicineName}」？`,
                      primaryButton: {
                        value: '取消',
                        action: () => {}
                      },
                      secondaryButton: {
                        value: '删除',
                        action: async () => {
                          await this.db.deleteMedication(med.id);
                          this.loadMemberData(this.familyMembers.length > 0 ?
                            this.familyMembers[this.selectedMemberIndex].id : '');
                        }
                      }
                    });
                  } else {
                    AlertDialog.show({
                      title: '提示',
                      message: '只能删除自己创建的记录',
                      primaryButton: {
                        value: '确定',
                        action: () => {}
                      }
                    });
                  }
                })
            )
          }, (timeSlot: string) => `${med.id}_${timeSlot}`)
        }, (med: Medication) => med.id + '_' + med.updatedAt)

        Button('+ 添加用药提醒')
          .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
          .borderRadius(0).width('100%').margin({ top: SPACE_LG })
          .onClick(() => {
            this.openAddMedicationDialog();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  MetricsTab() {
    if (this.metrics.length === 0) {
      EmptyState({
        icon: '📊',
        title: '暂无指标记录',
        subtitle: '记录血压、血糖等健康指标',
        actionText: '+ 记录指标',
        buttonColor: BRAND_RED,
        onAction: () => {
          this.editingMetricId = '';
          this.newMetricType = 'blood_pressure_systolic';
          this.newMetricValue = '';
          this.newMetricUnit = 'mmHg';
          this.showAddMetric = true;
        }
      })
    } else {
      Column({ space: 0 }) {
        // 全局趋势范围切换 — text-only toggle
        Row() {
          Text('指标趋势')
            .fontSize(FONT_SUBTITLE)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK).layoutWeight(1)
          Row({ space: SPACE_MD }) {
            Text('近7天')
              .fontSize(FONT_CAPTION)
              .fontColor(this.trendRange === 7 ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
              .fontWeight(this.trendRange === 7 ? FontWeight.Bold : FontWeight.Normal)
              .onClick(() => { this.trendRange = 7; })
            Text('近30天')
              .fontSize(FONT_CAPTION)
              .fontColor(this.trendRange === 30 ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
              .fontWeight(this.trendRange === 30 ? FontWeight.Bold : FontWeight.Normal)
              .onClick(() => { this.trendRange = 30; })
          }
        }
        .width('100%')
        .padding({ bottom: 8 })

        // 每个指标类型一个 flat 区块
        ForEach(this.getMetricTypes(), (type: string) => {
          Column({ space: 0 }) {
            // 最新数值区域 - serif 数字
            Row() {
              Column() {
                Text(this.getMetricTypeName(type))
                  .fontSize(this.isLargeFont ? 20 : 18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isTypeAbnormal(type) ? SEMANTIC_ERROR : NEUTRAL_INK)
                Text(this.getLatestMetricTime(type))
                  .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 大号数值显示 — serif
              Text(`${this.getLatestMetricValue(type)}`)
                .fontSize(this.isLargeFont ? 40 : 36)
                .fontWeight(FontWeight.Bold)
                .fontFamily(FONT_FAMILY_SERIF)
                .fontColor(this.isTypeAbnormal(type) ? SEMANTIC_ERROR : this.getChartColor(type))
              Text(` ${this.getUnitForType(type)}`)
                .fontSize(this.isLargeFont ? 18 : 16)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .margin({ left: 2 })

              if (this.isTypeAbnormal(type)) {
                Text('异常')
                  .fontSize(FONT_CAPTION)
                  .fontColor(SEMANTIC_ERROR)
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 16, bottom: 4 })

            // 正常参考值
            Row() {
              Text('正常范围: ')
                .fontSize(FONT_CAPTION)
                .fontColor(NEUTRAL_INK_SECONDARY)
              Text(this.getNormalRangeText(type))
                .fontSize(FONT_CAPTION)
                .fontColor(SEMANTIC_SUCCESS)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 2, bottom: 10 })

            // 趋势图
            TrendChart({
              dataPoints: this.getChartData(type).values,
              labels: this.getChartData(type).labels,
              barColor: this.getChartColor(type),
              abnormalHigh: this.getAbnormalHigh(type),
              abnormalLow: this.getAbnormalLow(type),
              unit: this.getUnitForType(type)
            })

            // 统计摘要
            Row({ space: SPACE_LG }) {
              Row() {
                Text('最高 ').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
                Text(`${this.getMetricStats(type).max}`).fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(SEMANTIC_ERROR)
              }
              Row() {
                Text('最低 ').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
                Text(`${this.getMetricStats(type).min}`).fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(SEMANTIC_SUCCESS)
              }
              Row() {
                Text('均值 ').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
                Text(`${this.getMetricStats(type).avg}`).fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(SEMANTIC_INFO)
              }
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 4, bottom: 14 })

            // 历史记录列表（最近3条）— flat with divider
            Column({ space: 0 }) {
              ForEach(this.getRecentMetricsForType(type, 3), (metric: HealthMetric) => {
                Row() {
                  Column() {
                    Text(formatIsoToLocal(metric.measuredAt).slice(5))
                      .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
                    if (this.recordCreatorLabel(metric.creatorId) !== '') {
                      Text(this.recordCreatorLabel(metric.creatorId))
                        .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY).margin({ top: 2 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(`${metric.value} ${metric.unit}`)
                    .fontSize(this.isLargeFont ? 17 : 15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(FONT_FAMILY_SERIF)
                    .fontColor(this.healthVm.checkAbnormal(metric.metricType, metric.value) ? SEMANTIC_ERROR : NEUTRAL_INK)
                  if (this.healthVm.checkAbnormal(metric.metricType, metric.value)) {
                    Text(' ⚠').fontSize(FONT_CAPTION).fontColor(SEMANTIC_ERROR)
                  }
                }
                .width('100%')
                .padding({ left: 0, right: 0, top: 10, bottom: 10 })
                .border({ width: { bottom: 0.5 }, color: DIVIDER })
                .onClick(() => {
                  this.detailMetric = metric;
                  this.showMetricDetail = true;
                })
                .gesture(
                  LongPressGesture()
                    .onAction(() => {
                      if (this.isCreator(metric.creatorId)) {
                        AlertDialog.show({
                          title: '确认删除',
                          message: `确定删除「${this.getMetricTypeName(metric.metricType)}」记录？`,
                          primaryButton: {
                            value: '取消',
                            action: () => {}
                          },
                          secondaryButton: {
                            value: '删除',
                            action: async () => {
                              await this.db.deleteHealthMetric(metric.id);
                              const memberId = this.familyMembers.length > 0 ?
                                this.familyMembers[this.selectedMemberIndex].id : '';
                              this.loadMemberData(memberId);
                            }
                          }
                        });
                      } else {
                        AlertDialog.show({
                          title: '提示',
                          message: '只能删除自己创建的记录',
                          primaryButton: {
                            value: '确定',
                            action: () => {}
                          }
                        });
                      }
                    })
                )
              }, (metric: HealthMetric) => metric.id + '_' + metric.updatedAt)
            }
            .width('100%')
          }
          .width('100%')
          .border({ width: { bottom: 0.5 }, color: DIVIDER })
          .backgroundColor(BG_PAPER)
        }, (type: string) => type)

        Button('+ 记录指标')
          .fontSize(this.isLargeFont ? 18 : FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
          .borderRadius(0).width('100%').margin({ top: SPACE_MD })
          .onClick(() => {
            this.editingMetricId = '';
            this.newMetricType = 'blood_pressure_systolic';
            this.newMetricValue = '';
            this.newMetricUnit = 'mmHg';
            this.showAddMetric = true;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private getMetricTypeName(type: string): string {
    const map: Record<string, string> = {
      'blood_pressure_systolic': '收缩压',
      'blood_pressure_diastolic': '舒张压',
      'blood_sugar': '血糖(空腹)',
      'body_temp': '体温',
      'heart_rate': '心率',
      'weight': '体重'
    };
    return map[type] ?? type;
  }

  @Builder
  AddMedicationOverlay() {
    if (this.showAddMedication) {
      Column() {
        Column() {
          Text(this.editingMedId ? '编辑用药提醒' : '添加用药提醒')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK).margin({ bottom: SPACE_LG })

          TextInput({ placeholder: '药品名称（如：氨氯地平）', text: this.newMedName })
            .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
            .backgroundColor(BG_SUBTLE)
            .onChange((v: string) => { this.newMedName = v; })

          TextInput({ placeholder: '剂量（如：1片）', text: this.newMedDosage })
            .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
            .backgroundColor(BG_SUBTLE)
            .onChange((v: string) => { this.newMedDosage = v; })

          TextInput({ placeholder: '频率（如：每日一次）', text: this.newMedFrequency })
            .width('100%').padding(10).borderRadius(0).margin({ bottom: 8 })
            .backgroundColor(BG_SUBTLE)
            .onChange((v: string) => { this.newMedFrequency = v; })

          // 服药人选择（来自健康模块共享范围）
          Text('服药人').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
          if (this.shareableMembers.length === 0) {
            Text('健康模块未共享给任何人，请先在「我的-模块管理」中开启共享')
              .fontSize(FONT_CAPTION).fontColor(SEMANTIC_ERROR).width('100%').margin({ bottom: 8 })
          } else {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.shareableMembers, (member: FamilyMember) => {
                Text(member.name)
                  .fontSize(FONT_CAPTION)
                  .fontColor(this.newMedForMemberId === member.id ? Color.White : NEUTRAL_INK)
                  .backgroundColor(this.newMedForMemberId === member.id ? NEUTRAL_INK : BG_SUBTLE)
                  .borderRadius(0)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => { this.newMedForMemberId = member.id; })
              }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
            }
            .width('100%')
            .margin({ bottom: 8 })
          }

          Row() {
            Text(this.newMedStartDate || '选择开始日期')
              .fontSize(FONT_BODY).fontColor(this.newMedStartDate ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY).layoutWeight(1)
          }.width('100%').padding(10).borderRadius(0).backgroundColor(BG_SUBTLE).margin({ bottom: 8 })
          .onClick(() => {
            DatePickerDialog.show({
              selected: this.newMedStartDate ? new Date(this.newMedStartDate) : new Date(),
              onAccept: (value: DatePickerResult) => {
                const m = (value.month ?? 0) + 1;
                const d = value.day ?? 1;
                this.newMedStartDate = `${value.year}-${m < 10 ? '0' + m : '' + m}-${d < 10 ? '0' + d : '' + d}`;
              }
            })
          })

          Row() {
            Text(this.newMedEndDate || '选择结束日期（可选）')
              .fontSize(FONT_BODY).fontColor(this.newMedEndDate ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY).layoutWeight(1)
          }.width('100%').padding(10).borderRadius(0).backgroundColor(BG_SUBTLE).margin({ bottom: 8 })
          .onClick(() => {
            DatePickerDialog.show({
              selected: this.newMedEndDate ? new Date(this.newMedEndDate) : new Date(),
              onAccept: (value: DatePickerResult) => {
                const m = (value.month ?? 0) + 1;
                const d = value.day ?? 1;
                this.newMedEndDate = `${value.year}-${m < 10 ? '0' + m : '' + m}-${d < 10 ? '0' + d : '' + d}`;
              }
            })
          })

          Text('服药时间').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.medTimeSlots, (slot: string, index: number) => {
              Row() {
                Text(slot).fontSize(FONT_CAPTION).fontColor(BRAND_RED)
                Text(' ×').fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
                  .onClick(() => {
                    const newSlots: string[] = [];
                    for (let i = 0; i < this.medTimeSlots.length; i++) {
                      if (i !== index) newSlots.push(this.medTimeSlots[i]);
                    }
                    this.medTimeSlots = newSlots;
                  })
              }
              .padding({ left: 10, right: 8, top: 5, bottom: 5 })
              .borderRadius(0)
              .backgroundColor(BG_SUBTLE)
              .margin({ right: 6, bottom: 6 })
            }, (slot: string, index: number) => `${slot}_${index}`)
            Row() {
              Text('+ 添加时间').fontSize(FONT_CAPTION).fontColor(BRAND_RED)
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(0)
            .border({ width: 1, color: BRAND_RED })
            .margin({ bottom: 6 })
            .onClick(() => {
              TimePickerDialog.show({
                selected: new Date(),
                useMilitaryTime: true,
                onAccept: (value: TimePickerResult) => {
                  const h = value.hour as number;
                  const min = value.minute as number;
                  const slot = `${h < 10 ? '0' + h : '' + h}:${min < 10 ? '0' + min : '' + min}`;
                  const newSlots: string[] = [];
                  for (const s of this.medTimeSlots) { newSlots.push(s); }
                  newSlots.push(slot);
                  this.medTimeSlots = newSlots;
                }
              })
            })
          }
          .width('100%')
          .margin({ bottom: 12 })

          Row({ space: 12 }) {
            Button('取消')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
              .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
              .onClick(() => {
                this.editingMedId = '';
                this.showAddMedication = false;
              })
            Button(this.isSavingMed ? '保存中...' : (this.editingMedId ? '保存' : '添加'))
              .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
              .borderRadius(0).layoutWeight(1)
              .enabled(!this.isSavingMed)
              .onClick(async () => {
                if (this.isSavingMed) return; // 防重复提交
                this.isSavingMed = true;
                try {
                  if (!this.newMedName) return;
                  if (!this.newMedForMemberId) {
                    AlertDialog.show({
                      title: '提示',
                      message: '请选择服药人',
                      primaryButton: { value: '确定', action: () => {} }
                    });
                    return;
                  }
                  const now = new Date().toISOString();
                  const timeSlots = this.medTimeSlots.length > 0 ? [...this.medTimeSlots] : ['08:00'];

                  if (this.editingMedId) {
                    const existing = this.medications.find((m: Medication) => m.id === this.editingMedId);
                    if (existing) {
                      const updated: Medication = {
                        id: existing.id,
                        familyId: existing.familyId,
                        creatorId: existing.creatorId,
                        visibility: existing.visibility,
                        visibleMembers: [...existing.visibleMembers],
                        version: existing.version + 1,
                        createdAt: existing.createdAt,
                        updatedAt: now,
                        forMemberId: this.newMedForMemberId,
                        medicineName: this.newMedName,
                        dosage: this.newMedDosage,
                        frequency: this.newMedFrequency,
                        timeSlots: timeSlots,
                        startDate: this.newMedStartDate || existing.startDate,
                        endDate: this.newMedEndDate || existing.endDate,
                        isActive: existing.isActive,
                        note: existing.note
                      };
                      await this.db.updateMedication(updated);
                    }
                  } else {
                    const family = this.db.getCurrentFamily();
                    const vis = this.healthVm.buildVisibilityForNewMedication();
                    const med: Medication = {
                      id: generateId('med'),
                      familyId: family?.id ?? '',
                      creatorId: this.db.getCurrentMemberId(),
                      visibility: vis.visibility,
                      visibleMembers: vis.visibleMembers,
                      version: 1,
                      createdAt: now,
                      updatedAt: now,
                      forMemberId: this.newMedForMemberId,
                      medicineName: this.newMedName,
                      dosage: this.newMedDosage,
                      frequency: this.newMedFrequency,
                      timeSlots: timeSlots,
                      startDate: this.newMedStartDate || now.slice(0, 10),
                      endDate: this.newMedEndDate || '',
                      isActive: true,
                      note: ''
                    };
                    await this.healthVm.addMedication(med);
                  }
                  this.editingMedId = '';
                  this.showAddMedication = false;
                  this.newMedName = '';
                  this.newMedDosage = '';
                  this.newMedFrequency = '';
                  this.newMedStartDate = '';
                  this.newMedEndDate = '';
                  this.medTimeSlots = [];
                  this.newMedForMemberId = '';
                  const reloadMemberId = this.familyMembers.length > 0 ?
                    this.familyMembers[this.selectedMemberIndex].id : '';
                  this.loadMemberData(reloadMemberId);
                } finally {
                  this.isSavingMed = false;
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
      .onClick(() => {
        this.editingMedId = '';
        this.showAddMedication = false;
      })
    }
  }

  @Builder
  AddMetricOverlay() {
    if (this.showAddMetric) {
      Column() {
        Column() {
          Text(this.editingMetricId ? '更新指标数值' : '记录健康指标')
            .fontSize(this.isLargeFont ? 20 : FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK).margin({ bottom: SPACE_LG })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.metricTypeOptions, (item: MetricTypeOption) => {
              Text(item.label)
                .fontSize(this.isLargeFont ? 16 : FONT_BODY)
                .fontColor(this.newMetricType === item.type ? Color.White : NEUTRAL_INK_SECONDARY)
                .backgroundColor(this.newMetricType === item.type ? NEUTRAL_INK : BG_SUBTLE)
                .borderRadius(0)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin(4)
                .onClick(() => {
                  this.newMetricType = item.type;
                  this.newMetricUnit = this.getUnitForType(item.type);
                })
            }, (item: MetricTypeOption) => item.type)
          }
          .margin({ bottom: 12 })

          TextInput({ placeholder: '数值', text: this.newMetricValue })
            .width('100%').padding(10).borderRadius(0).margin({ bottom: 12 })
            .backgroundColor(BG_SUBTLE)
            .fontSize(this.isLargeFont ? 18 : FONT_BODY_LARGE)
            .type(InputType.Normal)
            .inputFilter('^\\d*\\.?\\d{0,2}$', (_value: string) => {})
            .onChange((v: string) => { this.newMetricValue = v; })

          Row({ space: 12 }) {
            Button('取消')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
              .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
              .onClick(() => {
                this.editingMetricId = '';
                this.showAddMetric = false;
              })
            Button(this.isSavingMetric ? '保存中...' : (this.editingMetricId ? '保存' : '添加'))
              .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
              .borderRadius(0).layoutWeight(1)
              .enabled(!this.isSavingMetric)
              .onClick(async () => {
                if (this.isSavingMetric) return; // 防重复提交
                this.isSavingMetric = true;
                try {
                  if (!this.newMetricValue) return;
                  const value = parseFloat(this.newMetricValue);
                  if (isNaN(value)) return;
                  const now = new Date().toISOString();
                  const memberId = this.familyMembers.length > 0 ?
                    this.familyMembers[this.selectedMemberIndex].id : '';

                  if (this.editingMetricId) {
                    // 编辑指标时，创建一条新记录（保留历史数据）
                    const existing = this.metrics.find((m: HealthMetric) => m.id === this.editingMetricId);
                    const memberId = this.db.getCurrentMemberId();
                    const family = this.db.getCurrentFamily();
                    const newMetric: HealthMetric = {
                      id: generateId('hm'),
                      familyId: existing?.familyId ?? family?.id ?? '',
                      creatorId: existing?.creatorId ?? memberId,
                      visibility: existing?.visibility ?? Visibility.FAMILY,
                      visibleMembers: existing?.visibleMembers ? [...existing.visibleMembers] : [],
                      version: 1,
                      createdAt: now,
                      updatedAt: now,
                      forMemberId: existing?.forMemberId ?? memberId,
                      metricType: this.newMetricType,
                      value: value,
                      unit: this.newMetricUnit,
                      measuredAt: now,
                      isAbnormal: this.healthVm.checkAbnormal(this.newMetricType, value),
                      note: ''
                    };
                    await this.healthVm.addMetric(newMetric);
                  } else {
                    const family = this.db.getCurrentFamily();
                    const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.HEALTH);
                    const metric: HealthMetric = {
                      id: generateId('hm'),
                      familyId: family?.id ?? '',
                      creatorId: this.db.getCurrentMemberId(),
                      visibility: vis.visibility,
                      visibleMembers: vis.visibleMembers,
                      version: 1,
                      createdAt: now,
                      updatedAt: now,
                      forMemberId: memberId,
                      metricType: this.newMetricType,
                      value: value,
                      unit: this.newMetricUnit,
                      measuredAt: now,
                      isAbnormal: this.healthVm.checkAbnormal(this.newMetricType, value),
                      note: ''
                    };
                    await this.healthVm.addMetric(metric);
                  }
                  this.editingMetricId = '';
                  this.showAddMetric = false;
                  this.newMetricValue = '';
                  this.loadMemberData(memberId);
                } finally {
                  this.isSavingMetric = false;
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
      .onClick(() => {
        this.editingMetricId = '';
        this.showAddMetric = false;
      })
    }
  }

  // ==================== 用药详情弹窗 ====================
  @Builder
  MedicationDetailOverlay() {
    Column() {
      Column() {
        Row() {
          Text('用药详情')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK).layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_SECONDARY).onClick(() => {
            this.showMedicationDetail = false;
            this.detailMedication = null;
          })
        }.width('100%').margin({ bottom: SPACE_LG })

        if (this.detailMedication) {
          Text(this.detailMedication.medicineName)
            .fontSize(22).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK)
            .width('100%').margin({ bottom: 12 })

          Column({ space: 10 }) {
            this.DetailRow('服药人', this.getMemberNameById(this.detailMedication.forMemberId))
            this.DetailRow('剂量', this.detailMedication.dosage)
            this.DetailRow('频率', this.detailMedication.frequency)
            this.DetailRow('时间', this.detailMedication.timeSlots.join('、'))
            this.DetailRow('开始', this.detailMedication.startDate)
            if (this.detailMedication.endDate) {
              this.DetailRow('结束', this.detailMedication.endDate)
            }
            if (!this.isCreator(this.detailMedication.creatorId)) {
              this.DetailRow('创建人', this.getCreatorDisplay(this.detailMedication.creatorId))
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(0)
          .backgroundColor(BG_SUBTLE)
          .margin({ bottom: SPACE_LG })

          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
              .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
              .onClick(() => {
                this.showMedicationDetail = false;
                this.detailMedication = null;
              })

            if (this.isCreator(this.detailMedication.creatorId)) {
              Button('编辑')
                .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
                .borderRadius(0).layoutWeight(1)
                .onClick(() => {
                  const med = this.detailMedication!;
                  this.editingMedId = med.id;
                  this.newMedName = med.medicineName;
                  this.newMedDosage = med.dosage;
                  this.newMedFrequency = med.frequency;
                  this.medTimeSlots = [...med.timeSlots];
                  this.newMedStartDate = med.startDate;
                  this.newMedEndDate = med.endDate;
                  this.newMedForMemberId = med.forMemberId;
                  // 刷新共享成员列表，确保下拉里包含原服药人
                  this.shareableMembers = this.healthVm.getHealthShareableMembers();
                  if (!this.shareableMembers.some(m => m.id === med.forMemberId)) {
                    // 原服药人已不在共享范围，补回（避免显示为空）
                    const all = this.db.getMembersByFamilyId(this.db.getCurrentFamilyId());
                    const orig = all.find(m => m.id === med.forMemberId);
                    if (orig) this.shareableMembers = [...this.shareableMembers, orig];
                  }
                  this.showMedicationDetail = false;
                  this.detailMedication = null;
                  this.showAddMedication = true;
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
      this.showMedicationDetail = false;
      this.detailMedication = null;
    })
  }

  // ==================== 指标详情弹窗 ====================
  @Builder
  MetricDetailOverlay() {
    Column() {
      Column() {
        Row() {
          Text('指标详情')
            .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(NEUTRAL_INK).layoutWeight(1)
          Text('✕').fontSize(18).fontColor(NEUTRAL_INK_SECONDARY).onClick(() => {
            this.showMetricDetail = false;
            this.detailMetric = null;
          })
        }.width('100%').margin({ bottom: SPACE_LG })

        if (this.detailMetric) {
          Text(`${this.detailMetric.value} ${this.detailMetric.unit}`)
            .fontSize(32).fontWeight(FontWeight.Bold)
            .fontFamily(FONT_FAMILY_SERIF)
            .fontColor(this.healthVm.checkAbnormal(this.detailMetric.metricType, this.detailMetric.value) ? SEMANTIC_ERROR : NEUTRAL_INK)
            .width('100%').textAlign(TextAlign.Center).margin({ bottom: 8 })

          if (this.healthVm.checkAbnormal(this.detailMetric.metricType, this.detailMetric.value)) {
            Text('异常')
              .fontSize(FONT_CAPTION).fontColor(SEMANTIC_ERROR)
              .margin({ bottom: 8 })
          }

          Column({ space: 10 }) {
            this.DetailRow('类型', this.getMetricTypeName(this.detailMetric.metricType))
            this.DetailRow('测量时间', formatIsoToLocal(this.detailMetric.measuredAt))
          }
          .width('100%')
          .padding(14)
          .borderRadius(0)
          .backgroundColor(BG_SUBTLE)
          .margin({ bottom: SPACE_LG })

          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
              .borderRadius(0).border({ width: 1, color: DIVIDER }).layoutWeight(1)
              .onClick(() => {
                this.showMetricDetail = false;
                this.detailMetric = null;
              })

            if (this.isCreator(this.detailMetric.creatorId)) {
              Button('编辑')
                .fontSize(FONT_BODY).fontColor(Color.White).backgroundColor(NEUTRAL_INK)
                .borderRadius(0).layoutWeight(1)
                .onClick(() => {
                  const metric = this.detailMetric!;
                  this.editingMetricId = metric.id;
                  this.newMetricType = metric.metricType;
                  this.newMetricValue = metric.value.toString();
                  this.newMetricUnit = metric.unit;
                  this.showMetricDetail = false;
                  this.detailMetric = null;
                  this.showAddMetric = true;
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
      this.showMetricDetail = false;
      this.detailMetric = null;
    })
  }

  @Builder
  MemberPickerOverlay() {
    Column() {
      Column() {
        Text('谁服了药？')
          .fontSize(FONT_TITLE).fontWeight(FontWeight.Bold)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK).margin({ bottom: 4 })
        Text(this.getPendingMedDisplay())
          .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 12 })

        // 一键按默认服药人确认
        if (this.defaultMemberId) {
          ForEach(this.familyMembers.filter((member: FamilyMember) => member.id === this.defaultMemberId), (defaultMember: FamilyMember) => {
            Row() {
              Column() {
                Row() {
                  Text(defaultMember.name)
                    .fontSize(FONT_BODY_LARGE).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text(' 默认')
                    .fontSize(FONT_CAPTION_SM).fontColor(Color.White)
                    .margin({ left: 6 })
                }
                Text('该用药的服药人，点这里直接确认')
                  .fontSize(FONT_CAPTION).fontColor(Color.White).opacity(0.8).margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('✓').fontSize(20).fontColor(Color.White)
            }
            .width('100%')
            .padding(14)
            .borderRadius(0)
            .backgroundColor(NEUTRAL_INK)
            .margin({ bottom: 12 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(async () => {
              await this.healthVm.confirmTaken(this.pendingMedId, this.pendingMedTimeSlot, defaultMember.id);
              this.showMemberPicker = false;
              this.pendingMedId = '';
              this.pendingMedTimeSlot = '';
              this.defaultMemberId = '';
              this.todayLogs = this.healthVm.getTodayLogs();
              this.loadMemberData(this.familyMembers.length > 0 ?
                this.familyMembers[this.selectedMemberIndex].id : '');
            })
          }, (defaultMember: FamilyMember) => defaultMember.id + '_' + defaultMember.updatedAt)
        }

        if (this.familyMembers.length > 1) {
          Text('或选择其他人')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 8 })
        }

        ForEach(this.getOtherMedicationMembers(), (member: FamilyMember) => {
          Row() {
            Column() {
              Text(member.name)
                .fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
              Text('点击确认是此人所服')
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .borderRadius(0)
          .backgroundColor(BG_SUBTLE)
          .border({ width: { bottom: 0.5 }, color: DIVIDER })
          .margin({ bottom: 0 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(async () => {
            await this.healthVm.confirmTaken(this.pendingMedId, this.pendingMedTimeSlot, member.id);
            this.showMemberPicker = false;
            this.pendingMedId = '';
            this.pendingMedTimeSlot = '';
            this.defaultMemberId = '';
            this.todayLogs = this.healthVm.getTodayLogs();
            this.loadMemberData(this.familyMembers.length > 0 ?
              this.familyMembers[this.selectedMemberIndex].id : '');
          })
        }, (member: FamilyMember) => member.id + '_' + member.updatedAt)

        Button('取消')
          .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BG_PAPER)
          .borderRadius(0).border({ width: 1, color: DIVIDER }).width('100%').margin({ top: 4 })
          .onClick(() => {
            this.showMemberPicker = false;
            this.pendingMedId = '';
            this.pendingMedTimeSlot = '';
            this.defaultMemberId = '';
          })
      }
      .width('88%')
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
      this.showMemberPicker = false;
      this.pendingMedId = '';
      this.pendingMedTimeSlot = '';
      this.defaultMemberId = '';
    })
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).width(72)
      Text(value).fontSize(FONT_BODY).fontColor(NEUTRAL_INK).layoutWeight(1)
    }
    .width('100%')
  }

  /** 根据成员ID获取展示名（含 emoji） */
  private getMemberNameById(memberId: string): string {
    const m = this.familyMembers.find(mm => mm.id === memberId);
    if (m) return `${m.avatar} ${m.name}`;
    const all = this.db.getMembersByFamilyId(this.db.getCurrentFamilyId());
    const found = all.find(mm => mm.id === memberId);
    return found ? `${found.avatar} ${found.name}` : '未知';
  }

  /** 根据创建人userId获取展示名（含 emoji） */
  private getCreatorDisplay(creatorUserId: string): string {
    const all = this.db.getMembersByFamilyId(this.db.getCurrentFamilyId());
    const m = all.find(mm => mm.userId === creatorUserId);
    return m ? `${m.avatar} ${m.name}` : '其他家人';
  }

  /** 记录「创建人」标签：本人创建的记录不标注；他人记录显示「头像 昵称」，成员已离开则显示「家人」 */
  private recordCreatorLabel(creatorId: string): string {
    if (!creatorId || this.isCreator(creatorId)) return '';
    // familyMembers 仅含「有用药的成员」，创建者本人未必在其中，故用全量家庭名单解析
    return creatorDisplayLabel(creatorId, this.db.getMembersByFamilyId(this.db.getCurrentFamilyId()));
  }

  private getUnitForType(type: string): string {
    const map: Record<string, string> = {
      'blood_pressure_systolic': 'mmHg',
      'blood_pressure_diastolic': 'mmHg',
      'blood_sugar': 'mmol/L',
      'body_temp': '°C',
      'heart_rate': 'bpm',
      'weight': 'kg'
    };
    return map[type] ?? '';
  }

  private getMetricTypes(): string[] {
    const types: string[] = [];
    for (const m of this.metrics) {
      if (!types.includes(m.metricType)) {
        types.push(m.metricType);
      }
    }
    return types;
  }

  private getChartData(type: string): ChartData {
    const typeMetrics = this.metrics
      .filter(m => m.metricType === type)
      .sort((a, b) => a.measuredAt.localeCompare(b.measuredAt));
    const count: number = this.trendRange === 7 ? 7 : 30;
    const displayMetrics = typeMetrics.slice(-count);
    const values = displayMetrics.map(m => m.value);
    const labels = displayMetrics.map(m => m.measuredAt.slice(5, 10));
    return { values, labels };
  }

  private getChartColor(type: string): string {
    const map: Record<string, string> = {
      'blood_pressure_systolic': SEMANTIC_ERROR,
      'blood_pressure_diastolic': SEMANTIC_WARNING,
      'blood_sugar': MIST_PURPLE,
      'body_temp': SEMANTIC_INFO,
      'heart_rate': SEMANTIC_SUCCESS,
      'weight': NEUTRAL_INK_TERTIARY
    };
    return map[type] ?? SEMANTIC_INFO;
  }

  private getAbnormalHigh(type: string): number {
    const map: Record<string, number> = {
      'blood_pressure_systolic': 140,
      'blood_pressure_diastolic': 90,
      'blood_sugar': 7.0,
      'body_temp': 37.3,
      'heart_rate': 100
    };
    return map[type] ?? 0;
  }

  private getAbnormalLow(type: string): number {
    const map: Record<string, number> = {
      'blood_pressure_systolic': 90,
      'blood_pressure_diastolic': 60,
      'blood_sugar': 3.9,
      'body_temp': 36.0,
      'heart_rate': 60
    };
    return map[type] ?? 0;
  }

  /** 获取某指标类型的正常参考范围文字 */
  private getNormalRangeText(type: string): string {
    const map: Record<string, string> = {
      'blood_pressure_systolic': '90 - 140 mmHg',
      'blood_pressure_diastolic': '60 - 90 mmHg',
      'blood_sugar': '3.9 - 6.1 mmol/L',
      'body_temp': '36.0 - 37.3 °C',
      'heart_rate': '60 - 100 bpm',
      'weight': '依身高而定'
    };
    return map[type] ?? '';
  }

  /** 获取某指标类型的最新一条记录 */
  private getLatestMetricForType(type: string): HealthMetric | null {
    const typeMetrics = this.metrics
      .filter(m => m.metricType === type)
      .sort((a, b) => b.measuredAt.localeCompare(a.measuredAt));
    return typeMetrics.length > 0 ? typeMetrics[0] : null;
  }

  /** 获取某指标类型最新值（数字） */
  private getLatestMetricValue(type: string): number {
    const latest = this.getLatestMetricForType(type);
    return latest ? latest.value : 0;
  }

  /** 获取某指标类型最新测量时间 */
  private getLatestMetricTime(type: string): string {
    const latest = this.getLatestMetricForType(type);
    return latest ? formatIsoToLocal(latest.measuredAt) : '';
  }

  /** 判断某指标类型最新值是否异常 */
  private isTypeAbnormal(type: string): boolean {
    const latest = this.getLatestMetricForType(type);
    return latest ? this.healthVm.checkAbnormal(type, latest.value) : false;
  }

  /** 获取某指标类型的统计数据（最高/最低/均值）- 与趋势范围同步 */
  private getMetricStats(type: string): MetricStats {
    const typeMetrics = this.metrics
      .filter(m => m.metricType === type)
      .sort((a, b) => a.measuredAt.localeCompare(b.measuredAt));
    const count: number = this.trendRange === 7 ? 7 : 30;
    const displayMetrics = typeMetrics.slice(-count);
    if (displayMetrics.length === 0) {
      return { max: 0, min: 0, avg: 0 };
    }
    const values = displayMetrics.map(m => m.value);
    let maxVal = values[0];
    let minVal = values[0];
    let sum = 0;
    for (let i = 0; i < values.length; i++) {
      if (values[i] > maxVal) maxVal = values[i];
      if (values[i] < minVal) minVal = values[i];
      sum += values[i];
    }
    const avgVal = Math.round(sum / values.length * 10) / 10;
    return { max: maxVal, min: minVal, avg: avgVal };
  }

  /** 获取某指标类型最近N条记录（按时间倒序） */
  private getRecentMetricsForType(type: string, count: number): HealthMetric[] {
    return this.metrics
      .filter(m => m.metricType === type)
      .sort((a, b) => b.measuredAt.localeCompare(a.measuredAt))
      .slice(0, count);
  }

  private getMissedMedications(): MissedMedication[] {
    const result: MissedMedication[] = [];
    for (const med of this.medications) {
      if (!this.isMedicationActiveToday(med)) continue;
      for (const slot of med.timeSlots) {
        if (this.isSlotMissed(slot) && !this.healthVm.isMedicationTaken(med.id, slot)) {
          result.push({ medId: med.id, name: med.medicineName, slot });
        }
      }
    }
    return result;
  }

  /** 判断用药是否在有效期内（startDate ~ endDate 之间） */
  private isMedicationActiveToday(med: Medication): boolean {
    if (!med.isActive) return false;
    const today = formatDate(new Date());
    if (med.startDate && today < med.startDate) return false;
    if (med.endDate && today > med.endDate) return false;
    return true;
  }

  /** 判断某个时间段是否已错过（当前时间超过计划时间2小时以上） */
  private isSlotMissed(timeSlot: string): boolean {
    if (!timeSlot || !timeSlot.includes(':')) return false;
    const now = new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();
    const parts = timeSlot.split(':');
    const hours = parseInt(parts[0]);
    const minutes = parseInt(parts[1]);
    if (isNaN(hours) || isNaN(minutes)) return false;
    const slotMinutes = hours * 60 + minutes;
    return currentMinutes > slotMinutes + 120;
  }
}

interface MissedMedication {
  medId: string;
  name: string;
  slot: string;
}

interface ChartData {
  values: number[];
  labels: string[];
}

interface MetricStats {
  max: number;
  min: number;
  avg: number;
}

interface MetricTypeOption {
  type: string;
  label: string;
}
