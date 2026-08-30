/**
 * 购物清单模型
 */
import { BaseRecord } from './BaseRecord';

export class ShoppingItem extends BaseRecord {
  itemName: string = '';
  category: string = '';
  quantity: string = '';
  isPurchased: boolean = false;
  purchasedBy: string = '';
  purchasedAt: string = '';
}

// 家庭常用购物分类（按使用频率排序，"其他"兜底放最后）
export const SHOPPING_CATEGORIES: string[] = [
  '蔬菜', '水果', '肉类', '海鲜', '米面粮油',
  '日用品', '零食', '母婴', '其他'
];
