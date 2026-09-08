/**
 * 家庭记账
 *
 * 页面结构：月度收支明细（默认）/ 分类统计 / 年度报表 三个子 Tab。
 * - 新建/编辑记录弹层内的共享范围跟随「我的-模块管理」中的记账模块设置
 *   （resolveModuleVisibilityForRecord），不再单条选择分享对象。
 * - 记录行显示创建人标签（家人共享的记录标注是谁记的，本人不标注）。
 * - 列表支持下拉刷新：先从云端强制拉取合并再重载本地（家人记录即时可见）。
 */
import { AccountType, AccountCategory, AccountingRecord, CategoryItem, EXPENSE_CATEGORIES, INCOME_CATEGORIES } from '../model/AccountingRecord';
import {
  BG_PAPER, BG_SUBTLE, BORDER_CORAL, BORDER_SUBTLE, BRAND_CORAL, NEUTRAL_INK,
  NEUTRAL_INK_SECONDARY, SEMANTIC_ERROR, SEMANTIC_INFO, SEMANTIC_SUCCESS,
  SEMANTIC_WARNING, ERROR_BG, SUCCESS_BG
} from '../common/DesignTokens';
import { AccountingViewModel, MonthlyStats, AnnualStats, CategoryTotal, MemberTotal, MonthlyDataPoint } from '../viewmodel/AccountingViewModel';
import { LocalDbService, BudgetProgressResult } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { FamilyMember } from '../model/FamilyMember';
import { Visibility, FontSizeMode, THEME_PALETTES, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import { EmptyState } from '../components/EmptyState';
import { formatDate, generateId, creatorDisplayLabel } from '../common/Utils';
import router from '@ohos.router';

interface TypeOption {
  type: AccountType;
  label: string;
  color: string;
}

@Entry
@Component
struct AccountingPage {
  // 0=收支明细 1=分类统计 2=年度报表
  @State currentTab: number = 0;
  @State records: AccountingRecord[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State monthlyStats: MonthlyStats = { totalExpense: 0, totalIncome: 0, balance: 0, categoryBreakdown: {} };
  @State displayYear: number = new Date().getFullYear();
  @State displayMonth: number = new Date().getMonth() + 1;
  @State showAddDialog: boolean = false;
  @State isSavingRecord: boolean = false;
  @State showBudgetDialog: boolean = false;
  @State isSavingBudget: boolean = false;
  @State editingRecordId: string = '';
  @State showRecordDetail: boolean = false;
  @State detailRecord: AccountingRecord | null = null;
  @State newType: AccountType = AccountType.EXPENSE;
  @State newAmount: string = '';
  @State newCategory: AccountCategory = AccountCategory.FOOD;
  @State newDescription: string = '';
  @State newDate: string = formatDate(new Date());
  @State newForMemberId: string = '';
  @State amountError: string = '';
  @State budgetAmount: string = '';
  @State selectedMemberFilter: string = '';
  @State isRefreshing: boolean = false;
  @State isLargeFont: boolean = false;
  @State annualStats: AnnualStats = { year: 0, totalExpense: 0, totalIncome: 0, balance: 0, monthlyData: [], topExpenseCategories: [] };
  @State budgetProgress: BudgetProgressResult = { budget: 0, spent: 0, remaining: 0, percentage: 0 };
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themePrimary: string = BRAND_CORAL;
  @State themeBorder: string = BORDER_CORAL;
  @State themeLightBg: string = BG_PAPER;

  private accountingVm: AccountingViewModel = new AccountingViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  aboutToAppear(): void {
    this.familyMembers = this.familyVm.getFamilyMembers();
    this.refreshData();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    this.themeLightBg = palette.lightBg;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
  }

  onPageShow(): void {
    // 重新拉取家庭成员，保证创建人标签/成员筛选显示最新昵称
    this.familyMembers = this.familyVm.getFamilyMembers();
    this.refreshData();
  }

  pageTransition() {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
  }

  private refreshData(): void {
    this.records = this.getFilteredRecords();
    this.monthlyStats = this.accountingVm.getMonthlyStats(this.displayYear, this.displayMonth);
    this.annualStats = this.accountingVm.getAnnualStats(this.displayYear);
    this.budgetProgress = this.accountingVm.getBudgetProgress(this.displayYear, this.displayMonth);
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
      this.refreshData();
    }
  }

  private getFilteredRecords(): AccountingRecord[] {
    let result = this.accountingVm.getRecordsByMonth(this.displayYear, this.displayMonth);
    if (this.selectedMemberFilter) {
      result = result.filter(r => r.forMemberId === this.selectedMemberFilter);
    }
    return result;
  }

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  /** 记录「创建人」标签：本人创建的记录不标注；他人记录显示「头像 昵称」，成员已离开则显示「家人」 */
  private recordCreatorLabel(creatorId: string): string {
    if (!creatorId || this.isCreator(creatorId))
      return '';
    return creatorDisplayLabel(creatorId, this.familyMembers);
  }

  /** 读取记账模块的共享配置标签（用于表单提示，展示用） */
  private getModuleVisibilityLabel(): string {
    const cfg = this.db.getModuleVisibilityConfig(ModuleId.ACCOUNTING);
    if (!cfg)
      return '家庭可见';
    switch (cfg.visibility) {
      case Visibility.PRIVATE: return '仅自己';
      case Visibility.SELECTED: return `指定${cfg.visibleMemberIds.length}位成员`;
      case Visibility.FAMILY: return '家庭可见';
      default: return '家庭可见';
    }
  }

  build() {
    Stack() {
      Column() {
        this.TitleBar()
        this.MonthNav()
        this.BudgetCard()
        this.MemberFilter()
        this.SubTabs()
        if (this.currentTab === 0) {
          this.RecordsTab()
        } else if (this.currentTab === 1) {
          this.StatsTab()
        } else {
          this.AnnualTab()
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.themeLightBg)

      if (this.showAddDialog) {
        this.AddRecordOverlay()
      }
      if (this.showBudgetDialog) {
        this.BudgetOverlay()
      }
      if (this.showRecordDetail) {
        this.RecordDetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
  }

  @Builder
  TitleBar() {
    Row() {
      Row() {
        Text('<')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themePrimary)
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor(this.themeBorder)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { router.back(); })

      Text('💰 家庭记账')
        .fontSize(this.titleFontSize)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Row() {
        Text('+')
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(this.themePrimary)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.editingRecordId = '';
        this.resetForm();
        this.showAddDialog = true;
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  MonthNav() {
    Row() {
      Text('◀')
        .fontSize(14)
        .fontColor(this.themePrimary)
        .padding({ left: 12, right: 6, top: 8, bottom: 8 })
        .onClick(() => { this.prevMonth(); })

      Text(`${this.displayYear}年${this.displayMonth}月`)
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(NEUTRAL_INK)
        .margin({ left: 4, right: 4 })

      Text('▶')
        .fontSize(14)
        .fontColor(this.themePrimary)
        .padding({ left: 6, right: 12, top: 8, bottom: 8 })
        .onClick(() => { this.nextMonth(); })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 4, bottom: 8 })
    .margin({ bottom: 4 })
  }

  @Builder
  BudgetCard() {
    Column() {
      // 月度总览
      Row() {
        Column() {
          Text('支出')
            .fontSize(12)
            .fontColor(NEUTRAL_INK_SECONDARY)
          Text(`¥${this.monthlyStats.totalExpense.toFixed(0)}`)
            .fontSize(this.fontSize + 1)
            .fontWeight(FontWeight.Bold)
            .fontColor(SEMANTIC_ERROR)
            .margin({ top: 2 })
        }
        .layoutWeight(1)

        Column() {
          Text('收入')
            .fontSize(12)
            .fontColor(NEUTRAL_INK_SECONDARY)
          Text(`¥${this.monthlyStats.totalIncome.toFixed(0)}`)
            .fontSize(this.fontSize + 1)
            .fontWeight(FontWeight.Bold)
            .fontColor(SEMANTIC_SUCCESS)
            .margin({ top: 2 })
        }
        .layoutWeight(1)

        Column() {
          Text('结余')
            .fontSize(12)
            .fontColor(NEUTRAL_INK_SECONDARY)
          Text(`¥${this.monthlyStats.balance.toFixed(0)}`)
            .fontSize(this.fontSize + 1)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.monthlyStats.balance >= 0 ? SEMANTIC_SUCCESS : SEMANTIC_ERROR)
            .margin({ top: 2 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 4 })

      // 预算进度条
      Row() {
        if (this.budgetProgress.budget > 0) {
          Column({ space: 4 }) {
            Row() {
              Text(`预算 ¥${this.budgetProgress.budget.toFixed(0)}`)
                .fontSize(12)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .layoutWeight(1)
              Text(`已花 ${this.budgetProgress.percentage.toFixed(0)}%`)
                .fontSize(12)
                .fontColor(this.budgetProgress.percentage >= 90 ? SEMANTIC_ERROR : NEUTRAL_INK_SECONDARY)
              Text('📊')
                .fontSize(14)
                .margin({ left: 8 })
                .onClick(() => { this.openBudgetDialog(); })
            }
            .width('100%')

            Row() {
              Row()
                .width(`${Math.min(this.budgetProgress.percentage, 100).toFixed(1)}%`)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.budgetProgress.percentage >= 90 ? SEMANTIC_ERROR :
                  this.budgetProgress.percentage >= 70 ? SEMANTIC_WARNING : SEMANTIC_SUCCESS)
            }
            .width('100%')
            .height(6)
            .borderRadius(3)
            .backgroundColor(BORDER_SUBTLE)

            Row() {
              Text(`剩余 ¥${this.budgetProgress.remaining.toFixed(0)}`)
                .fontSize(11)
                .fontColor(this.budgetProgress.remaining >= 0 ? SEMANTIC_SUCCESS : SEMANTIC_ERROR)
            }
          }
          .width('100%')
          .padding({ left: 10, right: 10, bottom: 10 })
        } else {
          Row() {
            Text('设置月度预算')
              .fontSize(13)
              .fontColor(this.themePrimary)
              .onClick(() => { this.openBudgetDialog(); })
          }
          .width('100%')
          .padding({ left: 10, right: 10, bottom: 10 })
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .borderRadius(10)
    .backgroundColor(Color.White)
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  MemberFilter() {
    if (this.familyMembers.length > 0) {
      Scroll() {
        Row({ space: 6 }) {
          Text('全部')
            .fontSize(12)
            .fontColor(this.selectedMemberFilter === '' ? Color.White : NEUTRAL_INK_SECONDARY)
            .backgroundColor(this.selectedMemberFilter === '' ? this.themePrimary : BORDER_SUBTLE)
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { this.selectedMemberFilter = ''; this.refreshData(); })

          ForEach(this.familyMembers, (member: FamilyMember) => {
            Text(`${member.avatar} ${member.name}`)
              .fontSize(12)
              .fontColor(this.selectedMemberFilter === member.id ? Color.White : NEUTRAL_INK_SECONDARY)
              .backgroundColor(this.selectedMemberFilter === member.id ? member.color : BORDER_SUBTLE)
              .borderRadius(12)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => { this.selectedMemberFilter = member.id; this.refreshData(); })
          }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 6 })
    }
  }

  @Builder
  SubTabs() {
    Row() {
      Text('收支明细')
        .fontSize(this.fontSize)
        .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === 0 ? SEMANTIC_INFO : NEUTRAL_INK_SECONDARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ bottom: 8 })
        .border({ width: { bottom: this.currentTab === 0 ? 2 : 0 }, color: SEMANTIC_INFO })
        .onClick(() => { this.currentTab = 0; })

      Text('分类统计')
        .fontSize(this.fontSize)
        .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === 1 ? SEMANTIC_INFO : NEUTRAL_INK_SECONDARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ bottom: 8 })
        .border({ width: { bottom: this.currentTab === 1 ? 2 : 0 }, color: SEMANTIC_INFO })
        .onClick(() => { this.currentTab = 1; })

      Text('年度报表')
        .fontSize(this.fontSize)
        .fontWeight(this.currentTab === 2 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === 2 ? SEMANTIC_INFO : NEUTRAL_INK_SECONDARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ bottom: 8 })
        .border({ width: { bottom: this.currentTab === 2 ? 2 : 0 }, color: SEMANTIC_INFO })
        .onClick(() => { this.currentTab = 2; })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  RecordsTab() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        if (this.records.length === 0) {
          EmptyState({
            icon: '💰',
            title: '暂无记录',
            subtitle: '记录家庭收支，轻松管账',
            actionText: '+ 记一笔',
            buttonColor: this.themePrimary,
            onAction: () => { this.showAddDialog = true; }
          })
        } else {
          Column({ space: 6 }) {
            ForEach(this.records, (record: AccountingRecord) => {
              Row() {
                Text(this.accountingVm.getCategoryIcon(record.category))
                  .fontSize(20)
                  .fontColor(this.accountingVm.getCategoryColor(record.category))
                  .margin({ right: 8 })

                Column() {
                  Text(record.description || this.accountingVm.getCategoryLabel(record.category))
                    .fontSize(15)
                    .fontColor(NEUTRAL_INK)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    Text(this.accountingVm.getCategoryLabel(record.category))
                      .fontSize(13)
                      .fontColor(NEUTRAL_INK_SECONDARY)
                    if (record.forMemberId) {
                      Text(` · ${this.accountingVm.getMemberName(record.forMemberId)}`)
                        .fontSize(13)
                        .fontColor(NEUTRAL_INK_SECONDARY)
                    }
                    Text(record.date.slice(5))
                      .fontSize(13)
                      .fontColor(NEUTRAL_INK_SECONDARY)
                      .margin({ left: 6 })
                    if (this.recordCreatorLabel(record.creatorId) !== '') {
                      Text(` · 👤${this.recordCreatorLabel(record.creatorId)}`)
                        .fontSize(13)
                        .fontColor(NEUTRAL_INK_SECONDARY)
                        .margin({ left: 6 })
                    }
                  }
                  .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(`${record.type === AccountType.EXPENSE ? '-' : '+'}¥${record.amount.toFixed(2)}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(record.type === AccountType.EXPENSE ? SEMANTIC_ERROR : SEMANTIC_SUCCESS)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(8)
              .backgroundColor(Color.White)
              .onClick(() => {
                this.detailRecord = record;
                this.showRecordDetail = true;
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
                      message: `确定删除这条${record.type === AccountType.EXPENSE ? '支出' : '收入'}记录？`,
                      primaryButton: { value: '取消', action: () => { } },
                      secondaryButton: {
                        value: '删除', fontColor: SEMANTIC_ERROR,
                        action: async () => {
                          try {
                            await this.accountingVm.deleteRecord(record.id);
                          } catch (_) {
                            AlertDialog.show({ message: '删除失败，请重试' });
                          } finally {
                            this.refreshData();
                          }
                        }
                      }
                    });
                  })
              )
            }, (record: AccountingRecord) => record.id + '_' + record.updatedAt)

            Button('+ 记一笔')
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(20)
              .width('100%')
              .margin({ top: 12 })
              .onClick(() => {
                this.editingRecordId = '';
                this.resetForm();
                this.showAddDialog = true;
              })
          }
          .padding(16)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
    .onRefreshing(() => { this.handlePullRefresh().catch(() => {}); })
  }

  @Builder
  StatsTab() {
    Scroll() {
      Column({ space: 12 }) {
        // 支出分类
        Text('支出分类')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .width('100%')

        if (Object.keys(this.monthlyStats.categoryBreakdown).length === 0) {
          Text('暂无支出数据')
            .fontSize(15)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(20)
        } else {
          ForEach(this.getSortedCategoryEntries(), (entry: [string, number]) => {
            Row() {
              Text(this.accountingVm.getCategoryIcon(entry[0]))
                .fontSize(16)
                .fontColor(this.accountingVm.getCategoryColor(entry[0]))
                .margin({ right: 6 })

              Column() {
                Row() {
                  Text(this.accountingVm.getCategoryLabel(entry[0]))
                    .fontSize(16)
                    .fontColor(NEUTRAL_INK)
                    .layoutWeight(1)
                  Text(`¥${entry[1].toFixed(0)}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(NEUTRAL_INK)
                  Text(`${this.categoryTotalExpense > 0 ? (entry[1] / this.categoryTotalExpense * 100).toFixed(1) : '0.0'}%`)
                    .fontSize(14)
                    .fontColor(NEUTRAL_INK_SECONDARY)
                    .margin({ left: 8 })
                }
                .width('100%')

                Row() {
                  Row()
                    .width(`${this.categoryTotalExpense > 0 ? Math.min(entry[1] / this.categoryTotalExpense * 100, 100).toFixed(1) : '0.0'}%`)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(this.accountingVm.getCategoryColor(entry[0]))
                }
                .width('100%')
                .height(8)
                .borderRadius(4)
                .backgroundColor(BORDER_SUBTLE)
                .margin({ top: 6 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor(Color.White)
          }, (entry: [string, number]) => entry[0])
        }

        // 成员消费统计
        if (this.familyMembers.length > 0) {
          Text('成员消费')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .width('100%')
            .margin({ top: 8 })

          ForEach(this.accountingVm.getMemberTotals(this.displayYear, this.displayMonth), (mt: MemberTotal) => {
            Row() {
              Text(mt.memberName)
                .fontSize(15)
                .fontColor(NEUTRAL_INK)
                .layoutWeight(1)
              Text(`支出 ¥${mt.expense.toFixed(0)}`)
                .fontSize(14)
                .fontColor(SEMANTIC_ERROR)
                .margin({ left: 8 })
              if (mt.income > 0) {
                Text(`收入 ¥${mt.income.toFixed(0)}`)
                  .fontSize(14)
                  .fontColor(SEMANTIC_SUCCESS)
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor(Color.White)
          }, (mt: MemberTotal) => mt.memberId)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .layoutWeight(1)
    .align(Alignment.TopStart)
  }

  @Builder
  AnnualTab() {
    Scroll() {
      Column({ space: 12 }) {
        // 年度总览
        Column() {
          Text(`${this.annualStats.year}年总览`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .width('100%')

          Row() {
            Column() {
              Text('总支出')
                .fontSize(12)
                .fontColor(NEUTRAL_INK_SECONDARY)
              Text(`¥${this.annualStats.totalExpense.toFixed(0)}`)
                .fontSize(this.fontSize + 1)
                .fontWeight(FontWeight.Bold)
                .fontColor(SEMANTIC_ERROR)
                .margin({ top: 2 })
            }
            .layoutWeight(1)

            Column() {
              Text('总收入')
                .fontSize(12)
                .fontColor(NEUTRAL_INK_SECONDARY)
              Text(`¥${this.annualStats.totalIncome.toFixed(0)}`)
                .fontSize(this.fontSize + 1)
                .fontWeight(FontWeight.Bold)
                .fontColor(SEMANTIC_SUCCESS)
                .margin({ top: 2 })
            }
            .layoutWeight(1)

            Column() {
              Text('总结余')
                .fontSize(12)
                .fontColor(NEUTRAL_INK_SECONDARY)
              Text(`¥${this.annualStats.balance.toFixed(0)}`)
                .fontSize(this.fontSize + 1)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.annualStats.balance >= 0 ? SEMANTIC_SUCCESS : SEMANTIC_ERROR)
                .margin({ top: 2 })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(10)
        .backgroundColor(Color.White)

        // 月度趋势
        Text('月度趋势')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .width('100%')
          .margin({ top: 4 })

        ForEach(this.annualStats.monthlyData, (dp: MonthlyDataPoint) => {
          Row() {
            Text(`${dp.month}月`)
              .fontSize(14)
              .fontColor(NEUTRAL_INK)
              .width(36)

            Column() {
              Row() {
                Row()
                  .width(`${this.getMonthBarWidth(dp.expense, this.annualStats)}%`)
                  .height(14)
                  .borderRadius(3)
                  .backgroundColor(ERROR_BG)
              }
              .width('100%')
              .height(14)
              .borderRadius(3)
              .backgroundColor(BG_SUBTLE)

              Row() {
                Row()
                  .width(`${this.getMonthBarWidth(dp.income, this.annualStats)}%`)
                  .height(14)
                  .borderRadius(3)
                  .backgroundColor(SUCCESS_BG)
              }
              .width('100%')
              .height(14)
              .borderRadius(3)
              .backgroundColor(BG_SUBTLE)
              .margin({ top: 3 })
            }
            .layoutWeight(1)

            Column() {
              Text(`¥${dp.expense.toFixed(0)}`)
                .fontSize(11)
                .fontColor(SEMANTIC_ERROR)
              Text(`¥${dp.income.toFixed(0)}`)
                .fontSize(11)
                .fontColor(SEMANTIC_SUCCESS)
                .margin({ top: 2 })
            }
            .width(60)
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor(Color.White)
        }, (dp: MonthlyDataPoint) => `${dp.month}`)

        // 年度支出TOP5
        if (this.annualStats.topExpenseCategories.length > 0) {
          Text('年度支出TOP5')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .width('100%')
            .margin({ top: 4 })

          ForEach(this.annualStats.topExpenseCategories, (cat: CategoryTotal, index: number) => {
            Row() {
              Text(`${index + 1}`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.themePrimary)
                .width(20)
              Text(this.accountingVm.getCategoryIcon(cat.category))
                .fontSize(16)
                .fontColor(this.accountingVm.getCategoryColor(cat.category))
                .margin({ right: 6 })

              Column() {
                Text(this.accountingVm.getCategoryLabel(cat.category))
                  .fontSize(15)
                  .fontColor(NEUTRAL_INK)

                Row() {
                  Row()
                    .width(`${cat.percentage.toFixed(1)}%`)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(this.accountingVm.getCategoryColor(cat.category))
                }
                .width('100%')
                .height(6)
                .borderRadius(3)
                .backgroundColor(BORDER_SUBTLE)
                .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(`¥${cat.amount.toFixed(0)}`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(NEUTRAL_INK)
              Text(`${cat.percentage.toFixed(1)}%`)
                .fontSize(12)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .margin({ left: 6 })
            }
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor(Color.White)
          }, (cat: CategoryTotal) => cat.category)
        }

        // 图例
        Row() {
          Row() {
            Row()
              .width(12)
              .height(12)
              .borderRadius(2)
              .backgroundColor(ERROR_BG)
              .margin({ right: 4 })
            Text('支出')
              .fontSize(12)
              .fontColor(NEUTRAL_INK_SECONDARY)
          }
          Row() {
            Row()
              .width(12)
              .height(12)
              .borderRadius(2)
              .backgroundColor(SUCCESS_BG)
              .margin({ right: 4 })
            Text('收入')
              .fontSize(12)
              .fontColor(NEUTRAL_INK_SECONDARY)
          }
          .margin({ left: 16 })
        }
        .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .layoutWeight(1)
    .align(Alignment.TopStart)
  }

  @Builder
  AddRecordOverlay() {
    Column() {
      Column() {
        Text(this.editingRecordId ? '编辑记录' : '记一笔')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .margin({ bottom: 12 })

        // 共享范围提示：新建记录跟随模块设置，无需在表单内重复选择分享对象
        if (!this.editingRecordId) {
          Row() {
            Text(`📌 共享范围：${this.getModuleVisibilityLabel()}`)
              .fontSize(12)
              .fontColor(NEUTRAL_INK_SECONDARY)
              .layoutWeight(1)
            Text('在「我的-模块管理」修改')
              .fontSize(10)
              .fontColor(NEUTRAL_INK_SECONDARY)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor(BG_SUBTLE)
          .margin({ bottom: 14 })
        }

        // 收入/支出切换
        Row({ space: 8 }) {
          ForEach([
            { type: AccountType.EXPENSE, label: '支出', color: SEMANTIC_ERROR },
            { type: AccountType.INCOME, label: '收入', color: SEMANTIC_SUCCESS }
          ], (item: TypeOption) => {
            Text(item.label)
              .fontSize(14)
              .fontColor(this.newType === item.type ? Color.White : NEUTRAL_INK)
              .backgroundColor(this.newType === item.type ? item.color : BG_SUBTLE)
              .borderRadius(16)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .onClick(() => {
                this.newType = item.type;
                this.newCategory = item.type === AccountType.EXPENSE ? AccountCategory.FOOD : AccountCategory.SALARY;
              })
          }, (item: TypeOption) => item.type)
        }
        .margin({ bottom: 12 })

        // 1) 分类选择
        Text('① 选择分类')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(NEUTRAL_INK)
          .width('100%')
          .margin({ bottom: 6 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.newType === AccountType.EXPENSE ? EXPENSE_CATEGORIES : INCOME_CATEGORIES, (cat: CategoryItem) => {
            Row({ space: 6 }) {
              Text(cat.icon)
                .fontSize(15)
                .fontColor(this.newCategory === cat.key ? Color.White : this.accountingVm.getCategoryColor(cat.key))
              Text(cat.label)
                .fontSize(15)
                .fontWeight(this.newCategory === cat.key ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.newCategory === cat.key ? Color.White : NEUTRAL_INK)
            }
            .backgroundColor(this.newCategory === cat.key ?
              (this.newType === AccountType.EXPENSE ? SEMANTIC_ERROR : SEMANTIC_SUCCESS) : BG_SUBTLE)
            .borderRadius(20)
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .margin(4)
            .onClick(() => { this.newCategory = cat.key; })
          }, (cat: CategoryItem) => cat.key)
        }
        .width('100%')
        .margin({ bottom: 14 })

        // 2) 金额（带校验）
        Text('② 输入金额')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(NEUTRAL_INK)
          .width('100%')
          .margin({ bottom: 6 })

        Row() {
          Text('¥')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .margin({ right: 8 })
          TextInput({ placeholder: '0.00', text: this.editingRecordId ? this.newAmount : undefined })
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .type(InputType.NUMBER_DECIMAL)
            .onChange((v: string) => {
              this.newAmount = v;
              const amt = parseFloat(v);
              if (!v) {
                this.amountError = '';
              } else if (isNaN(amt) || amt <= 0) {
                this.amountError = '金额必须大于 0';
              } else if (amt > 9999999) {
                this.amountError = '金额过大';
              } else {
                this.amountError = '';
              }
            })
        }
        .width('100%')

        if (this.amountError) {
          Text(this.amountError)
            .fontSize(12)
            .fontColor(SEMANTIC_ERROR)
            .width('100%')
            .margin({ top: 4 })
        }

        Divider()
          .color(BORDER_SUBTLE)
          .margin({ top: 8, bottom: 12 })

        // 为谁支出（记账归属，仅用于统计，不影响共享范围）
        if (this.familyMembers.length > 0) {
          Text('为谁支出')
            .fontSize(13)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .width('100%')
            .margin({ bottom: 2 })
          Text('仅用于成员消费统计，不影响上方共享范围')
            .fontSize(10)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .width('100%')
            .margin({ bottom: 4 })

          Scroll() {
            Row({ space: 6 }) {
              Text('家庭公共')
                .fontSize(12)
                .fontColor(this.newForMemberId === '' ? Color.White : NEUTRAL_INK_SECONDARY)
                .backgroundColor(this.newForMemberId === '' ? this.themePrimary : BORDER_SUBTLE)
                .borderRadius(12)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .onClick(() => { this.newForMemberId = ''; })

              ForEach(this.familyMembers, (member: FamilyMember) => {
                Text(`${member.avatar} ${member.name}`)
                  .fontSize(12)
                  .fontColor(this.newForMemberId === member.id ? Color.White : NEUTRAL_INK_SECONDARY)
                  .backgroundColor(this.newForMemberId === member.id ? member.color : BORDER_SUBTLE)
                  .borderRadius(12)
                  .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                  .onClick(() => { this.newForMemberId = member.id; })
              }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .margin({ bottom: 12 })
        }

        // 描述
        TextInput({ placeholder: '备注（可选）', text: this.editingRecordId ? this.newDescription : undefined })
          .width('100%')
          .padding(10)
          .borderRadius(8)
          .margin({ bottom: 8 })
          .onChange((v: string) => { this.newDescription = v; })

        // 日期
        Row() {
          Text(this.newDate || '选择日期')
            .fontSize(14)
            .fontColor(this.newDate ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
            .layoutWeight(1)
          Text('🗓️')
            .fontSize(16)
        }
        .width('100%')
        .padding(10)
        .borderRadius(8)
        .backgroundColor(BG_SUBTLE)
        .margin({ bottom: 12 })
        .onClick(() => {
          DatePickerDialog.show({
            selected: this.parseDateOrToday(this.newDate),
            onAccept: (value: DatePickerResult) => {
              const m = (value.month ?? 0) + 1;
              const d = value.day ?? 1;
              this.newDate = `${value.year}-${m < 10 ? '0' + m : '' + m}-${d < 10 ? '0' + d : '' + d}`;
            }
          });
        })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .backgroundColor(BORDER_SUBTLE)
            .borderRadius(20)
            .layoutWeight(1)
            .onClick(() => {
              this.showAddDialog = false;
              this.resetForm();
            })
          Button(this.isSavingRecord ? '保存中...' : '保存')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(this.newType === AccountType.EXPENSE ? SEMANTIC_ERROR : SEMANTIC_SUCCESS)
            .borderRadius(20)
            .layoutWeight(1)
            .enabled(!this.isSavingRecord)
            .onClick(async () => {
              if (this.isSavingRecord)
                return; // 防重复提交
              this.isSavingRecord = true;
              try {
                const amount = parseFloat(this.newAmount);
                if (!this.newAmount || isNaN(amount) || amount <= 0) {
                  this.amountError = '请输入大于 0 的金额';
                  AlertDialog.show({ message: '请输入大于 0 的金额' });
                  return;
                }
                if (amount > 9999999) {
                  this.amountError = '金额过大';
                  AlertDialog.show({ message: '金额过大，请检查' });
                  return;
                }
                const now = new Date().toISOString();
                const family = this.db.getCurrentFamily();
                if (this.editingRecordId) {
                  const allRecords = this.accountingVm.getAllRecords();
                  const existing = allRecords.find(r => r.id === this.editingRecordId);
                  if (existing) {
                    const updated: AccountingRecord = {
                      id: existing.id,
                      familyId: existing.familyId,
                      creatorId: existing.creatorId,
                      visibility: existing.visibility,
                      visibleMembers: existing.visibleMembers,
                      version: existing.version + 1,
                      createdAt: existing.createdAt,
                      updatedAt: now,
                      type: this.newType,
                      amount: amount,
                      category: this.newCategory,
                      description: this.newDescription,
                      date: this.newDate,
                      forMemberId: this.newForMemberId
                    };
                    await this.accountingVm.updateRecord(updated);
                  } else {
                    AlertDialog.show({ message: '原记录未找到，无法编辑' });
                    return;
                  }
                } else {
                  // 共享范围跟随「我的-模块管理」中的记账模块设置，单条记录不再单独选分享对象
                  const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.ACCOUNTING);
                  const record: AccountingRecord = {
                    id: generateId('ar'),
                    familyId: family?.id ?? '',
                    creatorId: this.db.getCurrentMemberId(),
                    visibility: vis.visibility,
                    visibleMembers: vis.visibleMembers,
                    version: 1,
                    createdAt: now,
                    updatedAt: now,
                    type: this.newType,
                    amount: amount,
                    category: this.newCategory,
                    description: this.newDescription,
                    date: this.newDate,
                    forMemberId: this.newForMemberId
                  };
                  await this.accountingVm.addRecord(record);
                }
                this.showAddDialog = false;
                this.resetForm();
              } catch (_) {
                AlertDialog.show({ message: '保存失败，请重试' });
              } finally {
                this.isSavingRecord = false;
                this.refreshData();
              }
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => { })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 记账详情弹窗 ====================
  @Builder
  RecordDetailOverlay() {
    Column() {
      Column() {
        Row() {
          Text('💰 记录详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text('✕')
            .fontSize(18)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .onClick(() => {
              this.showRecordDetail = false;
              this.detailRecord = null;
            })
        }
        .width('100%')
        .margin({ bottom: 16 })

        if (this.detailRecord) {
          // 金额
          Text(`${this.detailRecord.type === AccountType.EXPENSE ? '-' : '+'}¥${this.detailRecord.amount.toFixed(2)}`)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.detailRecord.type === AccountType.EXPENSE ? SEMANTIC_ERROR : SEMANTIC_SUCCESS)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ bottom: 16 })

          // 详情
          Column({ space: 10 }) {
            this.DetailField('类型', this.detailRecord.type === AccountType.EXPENSE ? '支出' : '收入')
            this.DetailField('分类', this.accountingVm.getCategoryLabel(this.detailRecord.category))
            if (this.detailRecord.description) {
              this.DetailField('备注', this.detailRecord.description)
            }
            this.DetailField('日期', this.detailRecord.date)
            if (this.detailRecord.forMemberId) {
              this.DetailField('成员', this.accountingVm.getMemberName(this.detailRecord.forMemberId))
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(BG_SUBTLE)
          .margin({ bottom: 16 })

          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(14)
              .fontColor(NEUTRAL_INK_SECONDARY)
              .backgroundColor(BORDER_SUBTLE)
              .borderRadius(20)
              .layoutWeight(1)
              .onClick(() => {
                this.showRecordDetail = false;
                this.detailRecord = null;
              })
            if (this.isCreator(this.detailRecord.creatorId)) {
              Button('编辑')
                .fontSize(14)
                .fontColor(Color.White)
                .backgroundColor(this.detailRecord.type === AccountType.EXPENSE ? SEMANTIC_ERROR : SEMANTIC_SUCCESS)
                .borderRadius(20)
                .layoutWeight(1)
                .onClick(() => {
                  const record = this.detailRecord!;
                  this.editingRecordId = record.id;
                  this.newType = record.type;
                  this.newAmount = `${record.amount}`;
                  this.newCategory = record.category;
                  this.newDescription = record.description;
                  this.newDate = record.date;
                  this.newForMemberId = record.forMemberId;
                  this.showRecordDetail = false;
                  this.detailRecord = null;
                  this.showAddDialog = true;
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
      .onClick(() => { })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showRecordDetail = false;
      this.detailRecord = null;
    })
  }

  @Builder
  DetailField(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(NEUTRAL_INK_SECONDARY)
        .width(48)
      Text(value)
        .fontSize(14)
        .fontColor(NEUTRAL_INK)
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  BudgetOverlay() {
    Column() {
      Column() {
        Text('设置月度预算')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 8 })
        Text(`${this.displayYear}年${this.displayMonth}月`)
          .fontSize(14)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .margin({ bottom: 16 })

        Text('预算金额')
          .fontSize(13)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .width('100%')
          .margin({ bottom: 4 })

        Row() {
          Text('¥')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .margin({ right: 8 })
          TextInput({ placeholder: '0.00', text: this.budgetAmount || undefined })
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .type(InputType.NUMBER_DECIMAL)
            .onChange((v: string) => { this.budgetAmount = v; })
        }
        .width('100%')
        .padding({ bottom: 16 })

        Row() {
          // 快捷金额
          ForEach(['3000', '5000', '8000', '10000'], (val: string) => {
            Text(`¥${parseInt(val).toLocaleString()}`)
              .fontSize(13)
              .fontColor(this.budgetAmount === val ? Color.White : NEUTRAL_INK)
              .backgroundColor(this.budgetAmount === val ? this.themePrimary : BG_SUBTLE)
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin(4)
              .onClick(() => { this.budgetAmount = val; })
          }, (val: string) => val)
        }
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .backgroundColor(BORDER_SUBTLE)
            .borderRadius(20)
            .layoutWeight(1)
            .onClick(() => { this.showBudgetDialog = false; })
          Button(this.isSavingBudget ? '保存中...' : '保存')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .borderRadius(20)
            .layoutWeight(1)
            .enabled(!this.isSavingBudget)
            .onClick(async () => {
              if (this.isSavingBudget)
                return; // 防重复提交
              this.isSavingBudget = true;
              try {
                const amount = parseFloat(this.budgetAmount);
                if (this.budgetAmount && (isNaN(amount) || amount < 0)) {
                  AlertDialog.show({ message: '预算金额必须为非负数' });
                  return;
                }
                if (amount > 0) {
                  await this.accountingVm.setBudget(this.displayYear, this.displayMonth, amount);
                } else {
                  await this.accountingVm.setBudget(this.displayYear, this.displayMonth, 0);
                }
                this.showBudgetDialog = false;
              } catch (_) {
                AlertDialog.show({ message: '预算设置失败，请重试' });
              } finally {
                this.isSavingBudget = false;
                this.refreshData();
              }
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => { })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
  }

  private prevMonth(): void {
    if (this.displayMonth === 1) {
      this.displayMonth = 12;
      this.displayYear--;
    } else {
      this.displayMonth--;
    }
    this.refreshData();
  }

  private nextMonth(): void {
    if (this.displayMonth === 12) {
      this.displayMonth = 1;
      this.displayYear++;
    } else {
      this.displayMonth++;
    }
    this.refreshData();
  }

  private resetForm(): void {
    this.editingRecordId = '';
    this.newType = AccountType.EXPENSE;
    this.newAmount = '';
    this.newCategory = AccountCategory.FOOD;
    this.newDescription = '';
    this.newDate = formatDate(new Date());
    this.newForMemberId = '';
    this.amountError = '';
  }

  private parseDateOrToday(dateStr: string): Date {
    if (!dateStr)
      return new Date();
    const parts = dateStr.split('-');
    if (parts.length !== 3)
      return new Date();
    const y = parseInt(parts[0], 10);
    const m = parseInt(parts[1], 10);
    const d = parseInt(parts[2], 10);
    if (isNaN(y) || isNaN(m) || isNaN(d))
      return new Date();
    return new Date(y, m - 1, d);
  }

  private openBudgetDialog(): void {
    const budget = this.accountingVm.getBudget(this.displayYear, this.displayMonth);
    this.budgetAmount = budget ? `${budget.amount}` : '';
    this.showBudgetDialog = true;
  }

  private get categoryTotalExpense(): number {
    return this.monthlyStats.totalExpense || 0;
  }

  private getSortedCategoryEntries(): [string, number][] {
    return Object.entries(this.monthlyStats.categoryBreakdown)
      .sort((a, b) => b[1] - a[1]);
  }

  private getMonthBarWidth(value: number, annual: AnnualStats): number {
    const maxVal = Math.max(...annual.monthlyData.map(d => Math.max(d.expense, d.income)), 1);
    return (value / maxVal) * 100;
  }
}
