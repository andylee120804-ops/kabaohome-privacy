/**
 * 工具函数
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** 可见性过滤所需的公共字段 */
export interface VisibilityFields {
  creatorId: string;
  visibility: string;
  visibleMembers: string[];
}

/**
 * 生成唯一ID（前缀 + 时间戳 + 随机字符串，避免碰撞）
 */
export function generateId(prefix: string): string {
  const random = Math.random().toString(36).substring(2, 11);
  return `${prefix}_${Date.now()}_${random}`;
}

/**
 * 使用加密安全随机数生成器生成 6 位数字码
 *
 * 用于邀请码、认领令牌等安全敏感场景，替代 Math.random()
 * 如果 cryptoFramework 不可用则降级到 Math.random()
 *
 * @returns 6位数字字符串 (100000 ~ 999999)
 */
export async function generateSecureCode(): Promise<string> {
  try {
    const random = cryptoFramework.createRandom();
    const randomBytes = await random.generateRandom(4); // 4 字节 = 32 位随机值
    // 将随机字节转为 uint32 再取模
    const view = new DataView(randomBytes.data.buffer);
    const value = view.getUint32(0);
    return (100000 + (value % 900000)).toString();
  } catch (err) {
    // 降级：cryptoFramework 不可用时用 Math.random()（仅用于开发/预览环境，生产环境应排查原因）
    console.warn('[Utils] generateSecureCode: cryptoFramework unavailable, falling back to Math.random()');
    return Math.floor(100000 + Math.random() * 900000).toString();
  }
}

/**
 * 生成6位数字邀请码（同步版本，优先使用 generateSecureCode）
 * @deprecated 推荐使用 generateSecureCode() 以获得加密安全随机数
 */
export function generateInviteCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * 格式化日期为 YYYY-MM-DD
 */
export function formatDate(date: Date): string {
  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * 格式化时间为 HH:mm
 */
export function formatTime(date: Date): string {
  const hour = date.getHours().toString().padStart(2, '0');
  const minute = date.getMinutes().toString().padStart(2, '0');
  return `${hour}:${minute}`;
}

/**
 * 计算两个日期之间的天数差（保留正负方向）
 * 返回 date2 - date1 的天数差，date2 在 date1 之后为正数
 */
export function daysBetween(date1: Date, date2: Date): number {
  const oneDay = 24 * 60 * 60 * 1000;
  return Math.round((date2.getTime() - date1.getTime()) / oneDay);
}

/**
 * 指数退避延迟计算
 */
export function exponentialBackoff(attempt: number, initialDelayMs: number, maxDelayMs: number): number {
  const delay = initialDelayMs * Math.pow(2, attempt);
  return Math.min(delay, maxDelayMs);
}

/**
 * 判断健康指标是否异常
 */
export function isAbnormal(value: number, min: number, max: number): boolean {
  return value < min || value > max;
}

/**
 * 角度转弧度
 */
function toRad(deg: number): number {
  return deg * Math.PI / 180;
}

/**
 * Haversine 公式计算两个经纬度之间的距离（米）
 */
export function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000; // 地球半径（米）
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * 格式化距离为友好文字
 */
export function formatDistance(meters: number): string {
  if (meters < 1000) {
    return `${Math.round(meters)}m`;
  }
  return `${(meters / 1000).toFixed(1)}km`;
}

/**
 * 按可见性过滤记录列表
 * - PRIVATE: 仅创建者可见
 * - SELECTED: 创建者 + visibleMembers 中的成员可见
 * - FAMILY: 所有家庭成员可见
 * @param records 记录列表（需包含 creatorId, visibility, visibleMembers 字段）
 * @param currentUserId 当前用户ID
 * @returns 过滤后的记录列表
 */
export function filterByVisibility<T extends VisibilityFields>(
  records: T[],
  currentUserId: string
): T[] {
  // 安全策略：未登录或无法确定当前用户时，一律不返回任何记录（fail-closed）
  // 避免在预登录态下泄露家庭数据
  if (!currentUserId) return [];
  return records.filter(record => {
    if (record.visibility === 'FAMILY') return true;
    if (record.visibility === 'PRIVATE') return record.creatorId === currentUserId;
    if (record.visibility === 'SELECTED') {
      return record.creatorId === currentUserId || record.visibleMembers.includes(currentUserId);
    }
    // 未设置可见性时，默认仅创建者可见
    return record.creatorId === currentUserId;
  });
}
