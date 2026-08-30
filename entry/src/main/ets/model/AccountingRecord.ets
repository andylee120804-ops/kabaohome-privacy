/**
 * 家庭记账模型
 */
import { BaseRecord } from './BaseRecord';

export enum AccountType {
  EXPENSE = 'expense',
  INCOME = 'income'
}

export enum AccountCategory {
  FOOD = 'food',
  TRANSPORT = 'transport',
  SHOPPING = 'shopping',
  HOUSING = 'housing',
  EDUCATION = 'education',
  MEDICAL = 'medical',
  ENTERTAINMENT = 'entertainment',
  DAILY = 'daily',
  BABY = 'baby',
  OTHER = 'other',
  SALARY = 'salary',
  BONUS = 'bonus',
  INVESTMENT = 'investment',
  SIDE_JOB = 'side_job',
  GIFT = 'gift',
  INCOME_OTHER = 'income_other'
}

export interface CategoryItem {
  key: AccountCategory;
  label: string;
  icon: string;
}

export const EXPENSE_CATEGORIES: CategoryItem[] = [
  { key: AccountCategory.FOOD, label: '餐饮', icon: '🍜' },
  { key: AccountCategory.TRANSPORT, label: '交通', icon: '🚌' },
  { key: AccountCategory.SHOPPING, label: '购物', icon: '🛍' },
  { key: AccountCategory.HOUSING, label: '住房', icon: '🏠' },
  { key: AccountCategory.EDUCATION, label: '教育', icon: '📚' },
  { key: AccountCategory.MEDICAL, label: '医疗', icon: '🏥' },
  { key: AccountCategory.ENTERTAINMENT, label: '娱乐', icon: '🎮' },
  { key: AccountCategory.DAILY, label: '日用', icon: '🧴' },
  { key: AccountCategory.BABY, label: '宝宝', icon: '🍼' },
  { key: AccountCategory.OTHER, label: '其他', icon: '📎' }
];

export const INCOME_CATEGORIES: CategoryItem[] = [
  { key: AccountCategory.SALARY, label: '工资', icon: '💼' },
  { key: AccountCategory.BONUS, label: '奖金', icon: '🎯' },
  { key: AccountCategory.INVESTMENT, label: '理财', icon: '📈' },
  { key: AccountCategory.SIDE_JOB, label: '副业', icon: '💻' },
  { key: AccountCategory.GIFT, label: '红包', icon: '🧧' },
  { key: AccountCategory.INCOME_OTHER, label: '其他', icon: '📎' }
];

export const ALL_CATEGORIES: CategoryItem[] = [...EXPENSE_CATEGORIES, ...INCOME_CATEGORIES];

export class AccountingRecord extends BaseRecord {
  type: AccountType = AccountType.EXPENSE;
  amount: number = 0;
  category: AccountCategory = AccountCategory.OTHER;
  description: string = '';
  date: string = '';
  forMemberId: string = '';
}

export interface Budget {
  id: string;
  familyId: string;
  year: number;
  month: number;
  amount: number;
  createdAt: string;
  updatedAt: string;
}
