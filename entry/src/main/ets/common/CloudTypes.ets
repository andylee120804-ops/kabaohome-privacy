/**
 * 云端类型映射 - 客户端本地 key ↔ 云端 Cloud DB 对象类型名
 *
 * 从 CloudService 和 LocalDbService 中提取，避免循环依赖。
 */

/** 客户端本地存储 key → 云端 Cloud DB 对象类型名 */
export const CLIENT_TO_CLOUD_TYPE: Record<string, string> = {
  'families': 'Family',
  'members': 'FamilyMember',
  'period_records': 'PeriodRecord',
  'intimacy_records': 'IntimacyRecord',
  'medications': 'Medication',
  'medication_logs': 'MedicationLog',
  'health_metrics': 'HealthMetric',
  'kid_events': 'KidEvent',
  'growth_records': 'GrowthRecord',
  'reminders': 'Reminder',
  'shopping_items': 'ShoppingItem',
  'photos': 'Photo',
  'photo_comments': 'PhotoComment',
  'memos': 'Memo',
  'accounting_records': 'AccountingRecord',
  'budgets': 'Budget',
  'location_places': 'LocationPlace',
  'invitations': 'FamilyInvitation',
};

/** 云端对象类型名 → 客户端本地存储 key（反向映射） */
export const CLOUD_TO_CLIENT: Record<string, string> = {};
// 初始化反向映射（ArkTS 不支持解构赋值，用 keys 循环）
const typeKeys = Object.keys(CLIENT_TO_CLOUD_TYPE);
for (let i = 0; i < typeKeys.length; i++) {
  CLOUD_TO_CLIENT[CLIENT_TO_CLOUD_TYPE[typeKeys[i]]] = typeKeys[i];
}

/** 将客户端 key 转为云端类型名，找不到则原样返回 */
export function toCloudType(localType: string): string {
  return CLIENT_TO_CLOUD_TYPE[localType] ?? localType;
}

/** 将云端类型名转为客户端 key，找不到则原样返回 */
export function toLocalKey(cloudType: string): string {
  return CLOUD_TO_CLIENT[cloudType] ?? cloudType;
}

/** 所有需要云同步的对象类型名（云端格式） */
export const ALL_CLOUD_TYPES: string[] = [
  'Family', 'FamilyMember',
  'PeriodRecord', 'IntimacyRecord',
  'Medication', 'MedicationLog',
  'HealthMetric', 'KidEvent', 'GrowthRecord',
  'Reminder', 'ShoppingItem', 'Photo', 'PhotoComment', 'Memo',
  'AccountingRecord', 'Budget', 'LocationPlace',
];