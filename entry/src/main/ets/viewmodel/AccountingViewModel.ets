/**
 * 家庭记账ViewModel - 统计分析+分类汇总+预算管理
 */
import { LocalDbService, BudgetProgressResult } from '../service/LocalDbService';
import { AccountingRecord, AccountCategory, AccountType, Budget, ALL_CATEGORIES } from '../model/AccountingRecord';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';

export interface MonthlyStats {
  totalExpense: number;
  totalIncome: number;
  balance: number;
  categoryBreakdown: Record<string, number>;
}

export interface AnnualStats {
  year: number;
  totalExpense: number;
  totalIncome: number;
  balance: number;
  monthlyData: MonthlyDataPoint[];
  topExpenseCategories: CategoryTotal[];
}

export interface MonthlyDataPoint {
  month: number;
  expense: number;
  income: number;
}

export interface CategoryTotal {
  category: string;
  amount: number;
  percentage: number;
}

export interface MemberTotal {
  memberId: string;
  memberName: string;
  expense: number;
  income: number;
}

export class AccountingViewModel {
  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  getAllRecords(): AccountingRecord[] {
    return this.db.getAccountingRecords()
      .sort((a, b) => b.date.localeCompare(a.date));
  }

  getRecordsByMonth(year: number, month: number): AccountingRecord[] {
    const prefix = `${year}-${month.toString().padStart(2, '0')}`;
    return this.getAllRecords().filter(r => r.date.startsWith(prefix));
  }

  getRecordsByType(type: string): AccountingRecord[] {
    return this.getAllRecords().filter(r => r.type === type);
  }

  getRecordsByMember(memberId: string): AccountingRecord[] {
    return this.getAllRecords().filter(r => r.forMemberId === memberId);
  }

  async addRecord(record: AccountingRecord): Promise<void> {
    await this.db.saveAccountingRecord(record);
  }

  async updateRecord(record: AccountingRecord): Promise<void> {
    await this.db.updateAccountingRecord(record);
  }

  async deleteRecord(id: string): Promise<void> {
    await this.db.deleteAccountingRecord(id);
  }

  getMonthlyStats(year: number, month: number): MonthlyStats {
    const records = this.getRecordsByMonth(year, month);
    let totalExpense = 0;
    let totalIncome = 0;
    const categoryBreakdown: Record<string, number> = {};

    for (const r of records) {
      if (r.type === AccountType.EXPENSE) {
        totalExpense += r.amount;
        categoryBreakdown[r.category] = (categoryBreakdown[r.category] ?? 0) + r.amount;
      } else if (r.type === AccountType.INCOME) {
        totalIncome += r.amount;
      }
    }

    return {
      totalExpense,
      totalIncome,
      balance: totalIncome - totalExpense,
      categoryBreakdown
    };
  }

  getAnnualStats(year: number): AnnualStats {
    const allRecords = this.getAllRecords().filter(r => r.date.startsWith(`${year}-`));
    let totalExpense = 0;
    let totalIncome = 0;
    const monthlyData: MonthlyDataPoint[] = [];
    const categoryMap: Record<string, number> = {};

    for (let m = 1; m <= 12; m++) {
      const prefix = `${year}-${m.toString().padStart(2, '0')}`;
      const monthRecords = allRecords.filter(r => r.date.startsWith(prefix));
      let mExpense = 0;
      let mIncome = 0;
      for (const r of monthRecords) {
        if (r.type === AccountType.EXPENSE) {
          mExpense += r.amount;
          categoryMap[r.category] = (categoryMap[r.category] ?? 0) + r.amount;
        } else if (r.type === AccountType.INCOME) {
          mIncome += r.amount;
        }
      }
      totalExpense += mExpense;
      totalIncome += mIncome;
      monthlyData.push({ month: m, expense: mExpense, income: mIncome });
    }

    const topExpenseCategories: CategoryTotal[] = Object.entries(categoryMap)
      .map((entry: [string, number]) => {
        const ct: CategoryTotal = {
          category: entry[0],
          amount: entry[1],
          percentage: totalExpense > 0 ? (entry[1] / totalExpense) * 100 : 0
        };
        return ct;
      })
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 5);

    return {
      year,
      totalExpense,
      totalIncome,
      balance: totalIncome - totalExpense,
      monthlyData,
      topExpenseCategories
    };
  }

  getMemberTotals(year: number, month: number): MemberTotal[] {
    const records = this.getRecordsByMonth(year, month);
    const members = this.familyVm.getFamilyMembers();
    const result: MemberTotal[] = [];

    for (const member of members) {
      const memberRecords = records.filter(r => r.forMemberId === member.id);
      if (memberRecords.length === 0) continue;
      const expense = memberRecords.filter(r => r.type === AccountType.EXPENSE).reduce((s, r) => s + r.amount, 0);
      const income = memberRecords.filter(r => r.type === AccountType.INCOME).reduce((s, r) => s + r.amount, 0);
      result.push({ memberId: member.id, memberName: member.name, expense, income });
    }

    const noMemberRecords = records.filter(r => !r.forMemberId);
    if (noMemberRecords.length > 0) {
      const expense = noMemberRecords.filter(r => r.type === AccountType.EXPENSE).reduce((s, r) => s + r.amount, 0);
      const income = noMemberRecords.filter(r => r.type === AccountType.INCOME).reduce((s, r) => s + r.amount, 0);
      result.push({ memberId: '', memberName: '家庭公共', expense, income });
    }

    return result;
  }

  // ---- 预算管理 ----
  getBudget(year: number, month: number): Budget | null {
    return this.db.getBudget(year, month);
  }

  async setBudget(year: number, month: number, amount: number): Promise<void> {
    const family = this.db.getCurrentFamily();
    const existing = this.getBudget(year, month);
    const now = new Date().toISOString();
    const budget: Budget = {
      id: existing?.id ?? `budget_${year}_${month}`,
      familyId: family?.id ?? '',
      year,
      month,
      amount,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    };
    await this.db.saveBudget(budget);
  }

  getBudgetProgress(year: number, month: number): BudgetProgressResult {
    const budget = this.getBudget(year, month);
    const stats = this.getMonthlyStats(year, month);
    // 兜底归一化：历史本地数据可能有字符串金额（云端 Float 以字符串返回），
    // 不转成 number 的话页面 `budget.toFixed(0)` 抛 "undefined is not callable" 崩溃
    const budgetAmount = this.toAmount(budget?.amount);
    const result: BudgetProgressResult = {
      budget: budgetAmount,
      spent: stats.totalExpense,
      remaining: budgetAmount - stats.totalExpense,
      percentage: budgetAmount > 0 ? Math.min((stats.totalExpense / budgetAmount) * 100, 100) : 0
    };
    return result;
  }

  /** 把可能来自云端字符串的数值统一转成 number（非法值回退 0） */
  private toAmount(v: number | null | undefined): number {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }

  // ---- 分类工具 ----
  getCategoryLabel(category: string): string {
    const item = ALL_CATEGORIES.find(c => c.key === category);
    return item?.label ?? category;
  }

  getCategoryIcon(category: string): string {
    const item = ALL_CATEGORIES.find(c => c.key === category);
    return item?.icon ?? '📎';
  }

  getCategoryColor(category: string): string {
    const map: Record<string, string> = {
      [AccountCategory.FOOD]: '#E65100',
      [AccountCategory.TRANSPORT]: '#1565C0',
      [AccountCategory.SHOPPING]: '#6A1B9A',
      [AccountCategory.HOUSING]: '#2E7D32',
      [AccountCategory.EDUCATION]: '#00838F',
      [AccountCategory.MEDICAL]: '#C62828',
      [AccountCategory.ENTERTAINMENT]: '#FF6D00',
      [AccountCategory.DAILY]: '#5D4037',
      [AccountCategory.BABY]: '#AD1457',
      [AccountCategory.SALARY]: '#2E7D32',
      [AccountCategory.BONUS]: '#1B5E20',
      [AccountCategory.INVESTMENT]: '#0D47A1',
      [AccountCategory.SIDE_JOB]: '#00695C',
      [AccountCategory.GIFT]: '#C62828',
      [AccountCategory.INCOME_OTHER]: '#757575',
      [AccountCategory.OTHER]: '#757575'
    };
    return map[category] ?? '#757575';
  }

  getMemberName(memberId: string): string {
    if (!memberId) return '家庭公共';
    const member = this.familyVm.getFamilyMembers().find(m => m.id === memberId);
    return member?.name ?? '家庭公共';
  }
}
