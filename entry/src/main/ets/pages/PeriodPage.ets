/**
 * 卡宝Home - 姨妈周期页面（完整日历+周期计算+啪啪记录+提醒设置）
 */
import { PregnancyRisk, FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { PeriodRecord, IntimacyRecord } from '../model/PeriodRecord';
import { PeriodViewModel, CycleStatus, CycleTrendRow } from '../viewmodel/PeriodViewModel';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { CalendarView, MarkedDate } from '../components/CalendarView';
import { formatDate } from '../common/Utils';
import { LocalDbService } from '../service/LocalDbService';
import router from '@ohos.router';

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
  @State recentIntimacyRecords: IntimacyRecord[] = [];
  @State records: PeriodRecord[] = [];
  @State cycleTrendRows: CycleTrendRow[] = [];
  @State showCycleTrendDialog: boolean = false;
  @State periodInProgress: boolean = false;
  @State latestPeriodDate: string = '';
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themeLightBg: string = '#FFF5F0';
  @State themePrimary: string = '#E8654A';
  @State themeBorder: string = '#FFD4C2';

  // Reminder settings states
  @State remind3DaysBefore: boolean = true;
  @State remind1DayBefore: boolean = true;
  @State remindOvulation: boolean = false;
  @State remindFertile: boolean = false;
  @State recordsRefreshTag: number = 0; // 记录列表刷新标记，记录结束时递增强制刷新

  private periodVm: PeriodViewModel = new PeriodViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    this.refreshData();
    this.loadReminderSettings();
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
    // 每次进入页面时同步周期提醒（确保提醒与最新数据一致）
    this.periodVm.syncPeriodReminders();
  }

  private refreshData(): void {
    this.cycleStatus = this.periodVm.getCurrentCycleStatus();
    this.records = this.periodVm.getRecords();
    this.cycleTrendRows = this.periodVm.getCycleTrendRows();
    this.recentIntimacyRecords = this.periodVm.getIntimacyRecords()
      .sort((a, b) => b.date.localeCompare(a.date))
      .slice(0, 5);
    this.calendarMarks = this.periodVm.getCalendarMarks(this.displayYear, this.displayMonth);

    // 派生状态：经期是否进行中
    this.periodInProgress = this.periodVm.isPeriodInProgress();
    // 派生状态：最近经期开始日期
    if (this.records.length > 0) {
      const sorted = [...this.records].sort((a, b) => b.startDate.localeCompare(a.startDate));
      this.latestPeriodDate = sorted[0].startDate;
    } else {
      this.latestPeriodDate = '';
    }
    // 递增强制刷新标记，确保 ForEach 正确重渲染（修复结束日期不更新的问题）
    this.recordsRefreshTag++;
    // 每次经期数据变化后同步周期提醒（确保提醒日期基于最新周期预测）
    this.periodVm.syncPeriodReminders();
  }

  private loadReminderSettings(): void {
    const settings = this.db.getPeriodReminderSettings();
    this.remind3DaysBefore = settings.remind3DaysBefore;
    this.remind1DayBefore = settings.remind1DayBefore;
    this.remindOvulation = settings.remindOvulation;
    this.remindFertile = settings.remindFertile;
  }

  private async saveReminderSettings(): Promise<void> {
    await this.db.savePeriodReminderSettings({
      remind3DaysBefore: this.remind3DaysBefore,
      remind1DayBefore: this.remind1DayBefore,
      remindOvulation: this.remindOvulation,
      remindFertile: this.remindFertile
    });
    // 开关变化后立即同步周期提醒（创建/删除对应的 Reminder 记录）
    await this.periodVm.syncPeriodReminders();
  }

  private isCreator(creatorId: string): boolean {
    return creatorId === this.db.getCurrentUserId();
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
        Text('🌸 我的姨妈').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Row().width(34).height(34)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          this.StatusCard()
          this.CalendarSection()
          this.QuickActions()
          // 排序：经期记录 → 怀孕几率 → 啪啪记录 → 提醒设置
          this.PeriodRecordList()
          this.PregnancyRiskCard()
          this.IntimacyHistory()
          this.ReminderSettings()
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
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
  StatusCard() {
    Column() {
      if (this.cycleStatus.currentDay > 0) {
        Text(`第${this.cycleStatus.currentDay}天`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#880E4F')
        Text(`${this.getPhaseLabel(this.cycleStatus.phase)} · 预计${this.cycleStatus.nextPeriodDate}下次经期`)
          .fontSize(15)
          .fontColor('#AD1457')
          .margin({ top: 4 })
        if (this.cycleStatus.earliestPeriodDate && this.cycleStatus.latestPeriodDate) {
          Text(`可能范围 ${this.cycleStatus.earliestPeriodDate} ~ ${this.cycleStatus.latestPeriodDate}`)
            .fontSize(12)
            .fontColor('#AD1457')
            .opacity(0.72)
            .margin({ top: 3 })
          Text(this.cycleStatus.isAdaptive ? `已根据最近${this.cycleStatus.validCycleCount}次有效周期动态预测` : '记录较少，暂按当前周期估算')
            .fontSize(12)
            .fontColor('#AD1457')
            .opacity(0.62)
            .margin({ top: 2 })
        }
        Row({ space: 8 }) {
          Text(`周期: ${this.cycleStatus.cycleLength}天`)
            .fontSize(14)
            .backgroundColor('rgba(255,255,255,0.6)')
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          Text(`持续: ${this.cycleStatus.duration}天`)
            .fontSize(14)
            .backgroundColor('rgba(255,255,255,0.6)')
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        }
        .margin({ top: 8 })
      } else {
        Text('尚未记录周期')
          .fontSize(18).fontColor('#880E4F').fontWeight(FontWeight.Bold)
        Text('点击下方按钮开始记录')
          .fontSize(15).fontColor('#AD1457').margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .linearGradient({ angle: 135, colors: [['#FCE4EC', 0], ['#F8BBD0', 1]] })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  CalendarSection() {
    Column() {
      // 图例 — 颜色与日历渲染保持一致，增加姨妈开始/结束 emoji 说明
      Row({ space: 10 }) {
        Row({ space: 3 }) { Text('🩸').fontSize(10); Text('开始').fontSize(10) }
        Row({ space: 3 }) { Text('🌸').fontSize(10); Text('结束').fontSize(10) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill('#E91E63').opacity(0.75); Text('经期').fontSize(10) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill('#E91E63'); Text('第1天').fontSize(10) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill('#FF9800').opacity(0.25); Text('易孕期').fontSize(10) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill('#4CAF50').opacity(0.25); Text('安全期').fontSize(10) }
        Row({ space: 3 }) { Circle().width(10).height(10).fill('#FFD600').opacity(0.25); Text('排卵日').fontSize(10) }
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
          this.calendarMarks = this.periodVm.getCalendarMarks(year, month);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  QuickActions() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Button('🎀 记录来了')
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor('#E91E63')
          .borderRadius(20)
          .layoutWeight(1)
          .onClick(async () => {
            try {
              if (this.selectedDate > formatDate(new Date())) {
                AlertDialog.show({ message: '不能记录未来日期的经期' });
                return;
              }
              await this.periodVm.savePeriodRecord(
                this.selectedDate,
                this.cycleStatus.duration || 5,
                this.cycleStatus.cycleLength || 28
              );
              this.refreshData();
            } catch (err) {
              const errMsg = err instanceof Error ? err.message : String(err);
              AlertDialog.show({ message: `保存失败: ${errMsg}` });
            }
          })

        Button('✨ 记录结束')
          .fontSize(15)
          .fontColor('#E91E63')
          .backgroundColor(Color.White)
          .border({ width: 1, color: '#E91E63' })
          .borderRadius(20)
          .layoutWeight(1)
          .enabled(this.periodInProgress)
          .opacity(this.periodInProgress ? 1.0 : 0.4)
          .onClick(async () => {
            const endDate = this.selectedDate;
            // 不能选择未来日期
            if (endDate > formatDate(new Date())) {
              AlertDialog.show({ message: '结束日期不能是未来日期' });
              return;
            }
            const records = this.db.getPeriodRecords();
            if (records.length === 0) return;
            const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
            const latest = sorted[0];
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
                    await this.periodVm.endPeriod(endDate);
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
          .fontSize(15)
          .fontColor('#E91E63')
          .backgroundColor(Color.White)
          .border({ width: 1, color: '#E91E63' })
          .borderRadius(20)
          .layoutWeight(1)
          .onClick(async () => {
            if (this.selectedDate > formatDate(new Date())) {
              AlertDialog.show({ message: '不能记录未来日期的啪啪' });
              return;
            }
            await this.periodVm.saveIntimacyRecord(this.selectedDate, '');
            this.refreshData();
          })
      }
      .width('100%')

      // 经期进行中提示
      if (this.periodInProgress && this.latestPeriodDate) {
        Row() {
          Text('🩷 经期进行中')
            .fontSize(13)
            .fontColor('#880E4F')
            .fontWeight(FontWeight.Bold)
          Text(`· 开始于 ${this.latestPeriodDate}`)
            .fontSize(13)
            .fontColor('#AD1457')
          Text('· 点击"记录结束"更新周期')
            .fontSize(13)
            .fontColor('#AD1457')
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor('#FCE4EC')
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
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('×')
          .fontSize(30)
          .fontColor('#999999')
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
                .fontColor('#888888')
                .width(88)
              Text('周期天数')
                .fontSize(13)
                .fontColor('#888888')
                .layoutWeight(1)
              Text('是否准时')
                .fontSize(13)
                .fontColor('#888888')
                .width(82)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .padding({ left: 8, right: 8, bottom: 8 })

            Stack() {
              Column() {}
                .width('34%')
                .height('100%')
                .backgroundColor('#FFF4F8')
                .position({ x: '47%', y: 0 })
              Column({ space: 14 }) {
                if (this.cycleTrendRows.length === 0) {
                  Text('暂无周期记录')
                    .fontSize(15)
                    .fontColor('#999999')
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
                .fontColor('#D86A95')
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
      .backgroundColor('#F7F4F7')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F4F7')
  }

  @Builder
  CycleTrendRowItem(row: CycleTrendRow) {
    Row() {
      Text(row.displayDate)
        .fontSize(15)
        .fontColor('#777777')
        .width(88)
      Stack({ alignContent: Alignment.CenterStart }) {
        if (row.isCurrentCycle) {
          Text(row.cycleLabel)
            .fontSize(14)
            .fontColor('#E85C98')
            .border({ width: 1, color: '#E85C98', style: BorderStyle.Dashed })
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#FFF7FB')
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
          .linearGradient({ angle: 0, colors: [['#FF6BA8', 0], ['#F85A99', 1]] })
          .shadow({ radius: 4, color: '#22000000', offsetX: 0, offsetY: 2 })
        }
      }
      .layoutWeight(1)
      .height(36)
      Text(row.punctualityLabel)
        .fontSize(15)
        .fontColor(row.isCurrentCycle ? '#999999' : '#333333')
        .width(82)
    }
    .width('100%')
    .height(44)
  }

  @Builder
  PeriodRecordList() {
    Column({ space: 8 }) {
      Row() {
        Text('🩷 经期记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        Text('周期趋势')
          .fontSize(13)
          .fontColor('#E91E63')
          .backgroundColor('#FCE4EC')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .onClick(() => {
            this.cycleTrendRows = this.periodVm.getCycleTrendRows();
            this.showCycleTrendDialog = true;
          })
      }
      .width('100%')

      if (this.records.length === 0) {
        Text('暂无经期记录，点击"🎀 记录来了"开始')
          .fontSize(15).fontColor('#999999').width('100%')
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
                  .fontSize(17).fontColor('#333333').fontWeight(FontWeight.Bold)
                // 经期进行中标记 — 判断逻辑：endDate 非空且与 startDate 不同才算已结束
                if (!record.endDate || record.endDate === '') {
                  Text('进行中')
                    .fontSize(13).fontColor('#FFFFFF')
                    .backgroundColor('#E91E63')
                    .borderRadius(8)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .margin({ left: 6 })
                } else {
                  Text(`→ ${record.endDate}`)
                    .fontSize(15).fontColor('#999999')
                    .margin({ left: 4 })
                }
                Blank()
                Text(`${record.duration}天`)
                  .fontSize(14).fontColor('#880E4F')
                  .backgroundColor('#FCE4EC')
                  .borderRadius(8)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                Text(`周期${record.cycleLength}天`)
                  .fontSize(14).fontColor('#AD1457')
                  .backgroundColor('#FCE4EC')
                  .borderRadius(8)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .margin({ left: 4 })
              }
              .width('100%')

              // 备注（兼容历史数据）
              if (record.note) {
                Text(record.note)
                  .fontSize(14).fontColor('#999999').width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              // 操作按钮
              Row({ space: 12 }) {
                if (this.isCreator(record.creatorId)) {
                  if (!record.endDate || record.endDate === '') {
                    Text('结束经期')
                      .fontSize(15).fontColor('#E91E63')
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
                                await this.periodVm.endPeriod(this.selectedDate);
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
                    .fontSize(15).fontColor('#999999')
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
      Text('🔔 提醒设置').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')

      Row() {
        Column() {
          Text('经期前3天提醒').fontSize(16).fontColor('#333333')
          Text('提前3天通知即将来经期').fontSize(13).fontColor('#999999').margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remind3DaysBefore })
          .onChange(async (isOn: boolean) => {
            this.remind3DaysBefore = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor('#E91E63')
      }
      .width('100%')

      Divider().color('#F0F0F0')

      Row() {
        Column() {
          Text('经期前1天提醒').fontSize(16).fontColor('#333333')
          Text('提前1天通知即将来经期').fontSize(13).fontColor('#999999').margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remind1DayBefore })
          .onChange(async (isOn: boolean) => {
            this.remind1DayBefore = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor('#E91E63')
      }
      .width('100%')

      Divider().color('#F0F0F0')

      Row() {
        Column() {
          Text('排卵期提醒').fontSize(16).fontColor('#333333')
          Text('排卵日当天通知').fontSize(13).fontColor('#999999').margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remindOvulation })
          .onChange(async (isOn: boolean) => {
            this.remindOvulation = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor('#E91E63')
      }
      .width('100%')

      Divider().color('#F0F0F0')

      Row() {
        Column() {
          Text('易孕期提醒').fontSize(16).fontColor('#333333')
          Text('易孕窗口开始时通知').fontSize(13).fontColor('#999999').margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.remindFertile })
          .onChange(async (isOn: boolean) => {
            this.remindFertile = isOn;
            await this.saveReminderSettings();
          })
          .selectedColor('#E91E63')
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
        Text('今日怀孕几率').fontSize(15).fontColor('#666666')
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
          .fontSize(14).fontColor('#999999').margin({ top: 4 })
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
      Text('💕 啪啪记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')

      if (this.recentIntimacyRecords.length === 0) {
        Text('暂无啪啪记录')
          .fontSize(15).fontColor('#999999').width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(Color.White)
      } else {
        ForEach(this.recentIntimacyRecords, (record: IntimacyRecord) => {
          Row() {
            Text(record.date).fontSize(17).fontColor('#333333').layoutWeight(1)
            Text(`周期第${record.cycleDay}天`).fontSize(15).fontColor('#999999').margin({ right: 8 })
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
        }, (record: IntimacyRecord) => record.id)
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
    if (risk === PregnancyRisk.HIGH) return '#C62828';
    if (risk === PregnancyRisk.MEDIUM) return '#E65100';
    return '#2E7D32';
  }

  private getRiskBg(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return '#FFEBEE';
    if (risk === PregnancyRisk.MEDIUM) return '#FFF8E1';
    return '#E8F5E9';
  }

  private getRiskAdvice(risk: PregnancyRisk): string {
    if (risk === PregnancyRisk.HIGH) return '当前处于易孕期，怀孕几率较高';
    if (risk === PregnancyRisk.MEDIUM) return '当前怀孕几率中等';
    return '当前处于安全期，怀孕几率较低';
  }
}
