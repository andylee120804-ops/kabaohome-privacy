/**
 * 工具函数
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { FamilyMember } from '../model/FamilyMember';

export interface DateParts {
  year: number;
  month: number;
  day: number;
}

/** 可见性过滤所需的公共字段 */
export interface VisibilityFields {
  creatorId: string;
  visibility: string;
  visibleMembers: string[];
}

/**
 * 判断当前用户是否为记录的创建者
 *
 * creatorId 的两种格式：
 * - 新格式：存 FamilyMember.id（以 'mem_' 前缀），退出家庭后重新加入会获得新 ID，旧记录不可见
 * - 旧格式：存华为账号 openID（无 'mem_' 前缀），向后兼容已存在的记录
 *
 * @param creatorId 记录的 creatorId 字段
 * @param currentUserId 当前用户的 openID
 * @param currentMemberId 当前用户在家庭中的 FamilyMember.id
 */
export function isRecordCreator(
  creatorId: string,
  currentUserId: string,
  currentMemberId: string
): boolean {
  if (!creatorId) return false;
  // 新格式：creatorId 是 memberId
  if (currentMemberId && creatorId === currentMemberId) return true;
  // 旧格式：creatorId 是 openID（无 'mem_' 前缀的记录视为旧格式）
  if (creatorId === currentUserId && !creatorId.startsWith('mem_')) return true;
  return false;
}

/**
 * 生成记录「创建人」展示标签（共享给家人看时便于区分谁创建的）
 *
 * creatorId 兼容两种格式：
 * - 新格式：FamilyMember.id（'mem_' 前缀）
 * - 旧格式：成员账号 openID（直接等于成员 userId）
 *
 * @param creatorId 记录的 creatorId 字段
 * @param members 家庭成员列表（用于解析昵称）
 * @returns 成员昵称字符串；creatorId 为空返回 ''；成员已不在名单返回 fallback（默认「家人」）
 */
export function creatorDisplayLabel(creatorId: string, members: FamilyMember[], fallback: string = '家人'): string {
  if (!creatorId) return '';
  for (let i = 0; i < members.length; i++) {
    const m = members[i];
    if (!m) continue;
    if (m.id === creatorId || (m.userId && m.userId === creatorId)) {
      return m.name;
    }
  }
  return fallback;
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
 * 将 ISO UTC 时间字符串转为本地时区（北京时间）的 YYYY-MM-DD HH:mm
 *
 * 数据库存的是 new Date().toISOString()（UTC，带 Z 后缀），直接对字符串
 * slice 显示会慢 8 小时。显示一律用本函数转成本地时间。
 * 解析失败时原样返回，避免展示空值。
 */
export function formatIsoToLocal(isoStr: string): string {
  if (!isoStr) return '';
  const d = new Date(isoStr);
  if (Number.isNaN(d.getTime())) return isoStr;
  const year = d.getFullYear();
  const month = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  const hour = d.getHours().toString().padStart(2, '0');
  const minute = d.getMinutes().toString().padStart(2, '0');
  return `${year}-${month}-${day} ${hour}:${minute}`;
}

/**
 * 将 ISO UTC 时间字符串转为本地时区的日期 YYYY-MM-DD
 * 用于按天分组、日期展示，避免凌晨 0-8 点的照片被分到前一天
 */
export function toLocalDateKey(isoStr: string): string {
  if (!isoStr) return '';
  const d = new Date(isoStr);
  if (Number.isNaN(d.getTime())) return isoStr.slice(0, 10);
  const month = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${d.getFullYear()}-${month}-${day}`;
}

/**
 * 计算两个日期之间的天数差（保留正负方向）
 * 返回 date2 - date1 的天数差，date2 在 date1 之后为正数
 */
export function daysBetween(date1: Date, date2: Date): number {
  const oneDay = 24 * 60 * 60 * 1000;
  return Math.round((date2.getTime() - date1.getTime()) / oneDay);
}

export function parseDateParts(dateStr: string): DateParts {
  const parts = dateStr.split('-');
  const fallback = new Date();
  if (parts.length < 3) {
    return {
      year: fallback.getFullYear(),
      month: fallback.getMonth() + 1,
      day: fallback.getDate()
    };
  }

  return {
    year: Number(parts[0]),
    month: Number(parts[1]),
    day: Number(parts[2])
  };
}

export function toDateAtLocalMidnight(dateStr: string): Date {
  const parts = parseDateParts(dateStr);
  return new Date(parts.year, parts.month - 1, parts.day);
}

export function toDateTime(dateTimeStr: string): Date {
  const datePart = dateTimeStr.slice(0, 10);
  const date = toDateAtLocalMidnight(datePart);
  if (dateTimeStr.length <= 10) return date;

  const timePart = dateTimeStr.slice(11);
  const timePieces = timePart.split(':');
  const hour = Number(timePieces[0]);
  const minute = timePieces.length > 1 ? Number(timePieces[1]) : 0;
  const second = timePieces.length > 2 ? Number(timePieces[2]) : 0;
  if (isNaN(hour) || isNaN(minute) || isNaN(second)) return date;
  const d = new Date(date.getTime());
  d.setHours(hour, minute, second, 0);
  return d;
}

export function addDaysToDateStr(dateStr: string, days: number): string {
  const date = toDateAtLocalMidnight(dateStr);
  date.setDate(date.getDate() + days);
  return formatDate(date);
}

export function daysBetweenDateStrings(startDate: string, endDate: string): number {
  return daysBetween(toDateAtLocalMidnight(startDate), toDateAtLocalMidnight(endDate));
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
 *
 * creatorId 格式：
 * - 新格式：FamilyMember.id（角色级标识），退出后重新加入家庭会获得新 ID，旧记录不可见
 * - 旧格式：华为账号 openID（账号级标识），向后兼容
 *
 * @param records 记录列表（需包含 creatorId, visibility, visibleMembers 字段）
 * @param currentUserId 当前用户ID（华为账号 openID）
 * @param currentMemberId 当前用户在家庭中的成员ID（FamilyMember.id）
 * @returns 过滤后的记录列表
 */
export function filterByVisibility<T extends VisibilityFields>(
  records: T[],
  currentUserId: string,
  currentMemberId: string = ''
): T[] {
  // 安全策略：未登录或无法确定当前用户时，一律不返回任何记录（fail-closed）
  // 避免在预登录态下泄露家庭数据
  if (!currentUserId) return [];
  return records.filter(record => {
    const isCreator = isRecordCreator(record.creatorId, currentUserId, currentMemberId);
    if (record.visibility === 'FAMILY') return true;
    if (record.visibility === 'PRIVATE') return isCreator;
    if (record.visibility === 'SELECTED') {
      return isCreator || record.visibleMembers.includes(currentUserId);
    }
    // 未设置可见性时，默认仅创建者可见
    return isCreator;
  });
}

// ---- 成员默认头像 ----
/** 成员角色 → 默认头像 emoji（历史数据 avatar 为空时兜底显示；家庭角色选择 UI 用同一套 emoji） */
const ROLE_AVATAR_DEFAULTS: Map<string, string> = new Map();
ROLE_AVATAR_DEFAULTS.set('DAD', '👨');
ROLE_AVATAR_DEFAULTS.set('MOM', '👩');
ROLE_AVATAR_DEFAULTS.set('GRANDPA', '👴');
ROLE_AVATAR_DEFAULTS.set('GRANDMA', '👵');
ROLE_AVATAR_DEFAULTS.set('CHILD', '🧒');
ROLE_AVATAR_DEFAULTS.set('OTHER', '🧑');

/** 按成员角色返回默认头像 emoji；未知角色兜底 🧑 */
export function defaultAvatarForRole(role: string): string {
  const avatar = ROLE_AVATAR_DEFAULTS.get(role);
  return avatar ? avatar : '🧑';
}
