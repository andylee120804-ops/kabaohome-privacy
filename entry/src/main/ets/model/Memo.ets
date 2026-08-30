/**
 * 家庭备忘模型
 */
import { BaseRecord } from './BaseRecord';

export class Memo extends BaseRecord {
  title: string = '';
  content: string = '';
  category: string = '';
  isEncrypted: boolean = false;
}

export const MEMO_CATEGORIES: string[] = ['密码', '证件', '地址', '常用电话', '其他'];
