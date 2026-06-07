/**
 * 应用常量定义
 */

// 应用信息
export const APP_NAME = '卡宝Home';
export const APP_BUNDLE_NAME = 'com.family.kabaohome';

// Tab数量限制
export const MAX_CUSTOM_TABS = 3; // 首页+3个自选+我的=5个Tab

// 共享可见范围
export enum Visibility {
  PRIVATE = 'PRIVATE',     // 仅自己
  SELECTED = 'SELECTED',   // 指定成员
  FAMILY = 'FAMILY'        // 家庭清单内可见
}

// 家庭成员角色
export enum MemberRole {
  DAD = 'DAD',
  MOM = 'MOM',
  GRANDPA = 'GRANDPA',
  GRANDMA = 'GRANDMA',
  CHILD = 'CHILD',
  OTHER = 'OTHER'
}

// 字体模式
export enum FontSizeMode {
  NORMAL = 'NORMAL',
  LARGE = 'LARGE'
}

// 邀请方式
export enum InviteMethod {
  CODE = 'CODE',
  QRCODE = 'QRCODE',
  PHONE = 'PHONE'
}

// 邀请状态
export enum InviteStatus {
  PENDING = 'PENDING',
  ACCEPTED = 'ACCEPTED',
  REJECTED = 'REJECTED',
  EXPIRED = 'EXPIRED'
}

// 家庭成员状态
export enum MemberStatus {
  ACTIVE = 'ACTIVE',           // 已激活（创建者或已认领）
  UNCLAIMED = 'UNCLAIMED'      // 等待认领（由家人添加的非代管成员）
}

// 模块ID
export enum ModuleId {
  PERIOD = 'period',
  HEALTH = 'health',
  KIDS = 'kids',
  REMINDER = 'reminder',
  LOCATION = 'location',
  ALBUM = 'album',
  SHOPPING = 'shopping',
  MEMO = 'memo',
  ACCOUNTING = 'accounting'
}

// 怀孕几率
export enum PregnancyRisk {
  HIGH = 'HIGH',
  MEDIUM = 'MEDIUM',
  LOW = 'LOW'
}

// 预设成员颜色
export const MEMBER_COLORS: string[] = [
  '#E91E63', // 粉红
  '#1565C0', // 蓝色
  '#E65100', // 橙色
  '#C62828', // 红色
  '#2E7D32', // 绿色
  '#6A1B9A', // 紫色
  '#00838F', // 青色
  '#4E342E'  // 棕色
];

export interface SyncConfig {
  MAX_RETRIES: number;
  INITIAL_DELAY_MS: number;
  MAX_DELAY_MS: number;
  CLOUD_FUNCTION_TIMEOUT_MS: number;
}

// 模块共享配置
export interface ModuleVisibility {
  moduleId: ModuleId;
  visibility: Visibility;
  visibleMemberIds: string[];
}

// 同步重试配置
export const SYNC_CONFIG: SyncConfig = {
  MAX_RETRIES: 5,
  INITIAL_DELAY_MS: 1000,
  MAX_DELAY_MS: 30000,
  CLOUD_FUNCTION_TIMEOUT_MS: 10000
};

export interface HealthRange {
  min: number;
  max: number;
}

export interface HealthRanges {
  BLOOD_PRESSURE_SYSTOLIC: HealthRange;
  BLOOD_PRESSURE_DIASTOLIC: HealthRange;
  BLOOD_SUGAR_FASTING: HealthRange;
  BODY_TEMP: HealthRange;
  HEART_RATE: HealthRange;
}

// 家庭色系
export enum ThemeColor {
  WARM_CORAL = 'WARM_CORAL',
  OCEAN_BLUE = 'OCEAN_BLUE',
  FOREST_GREEN = 'FOREST_GREEN',
  SUNSET_AMBER = 'SUNSET_AMBER'
}

export interface ThemePalette {
  id: ThemeColor;
  name: string;
  primary: string;
  gradientStart: string;
  gradientEnd: string;
  lightBg: string;
  border: string;
  tag: string;
}

export const THEME_PALETTES: ThemePalette[] = [
  {
    id: ThemeColor.WARM_CORAL, name: '暖珊瑚',
    primary: '#E8654A', gradientStart: '#E8654A', gradientEnd: '#F28B6E',
    lightBg: '#FFF5F0', border: '#FFD4C2', tag: '🪸'
  },
  {
    id: ThemeColor.OCEAN_BLUE, name: '深海蓝',
    primary: '#2B5F9E', gradientStart: '#2B5F9E', gradientEnd: '#5B8FD4',
    lightBg: '#F0F5FF', border: '#C5D8F0', tag: '🌊'
  },
  {
    id: ThemeColor.FOREST_GREEN, name: '森绿',
    primary: '#2D7A4F', gradientStart: '#2D7A4F', gradientEnd: '#5AAF7C',
    lightBg: '#F0F7F0', border: '#C2E4CE', tag: '🌿'
  },
  {
    id: ThemeColor.SUNSET_AMBER, name: '暮光琥珀',
    primary: '#D4850A', gradientStart: '#D4850A', gradientEnd: '#F0A832',
    lightBg: '#FFFBF0', border: '#FFE0A0', tag: '🌅'
  }
];

// 表情风格
export enum EmojiStyle {
  CUTE = 'CUTE',
  WARM = 'WARM',
  KABAO = 'KABAO'
}

export interface EmojiSet {
  id: EmojiStyle;
  name: string;
  modules: string;
  members: string;
  invite: string;
  theme: string;
  emojiStyle: string;
  font: string;
  exit: string;
}

export const EMOJI_SETS: EmojiSet[] = [
  {
    id: EmojiStyle.CUTE, name: '可爱软萌',
    modules: '🧸', members: '🏡', invite: '💌', theme: '🎨',
    emojiStyle: '🎭', font: '🌙', exit: '🍬'
  },
  {
    id: EmojiStyle.WARM, name: '温暖亲密',
    modules: '✨', members: '🫂', invite: '🤝', theme: '🌈',
    emojiStyle: '💫', font: '🌙', exit: '🍂'
  },
  {
    id: EmojiStyle.KABAO, name: '卡宝专属',
    modules: '🧩', members: '💝', invite: '🎁', theme: '🌸',
    emojiStyle: '🧸', font: '🌙', exit: '💔'
  }
];

// 健康指标正常范围
export const HEALTH_RANGES: HealthRanges = {
  BLOOD_PRESSURE_SYSTOLIC: { min: 90, max: 140 },
  BLOOD_PRESSURE_DIASTOLIC: { min: 60, max: 90 },
  BLOOD_SUGAR_FASTING: { min: 3.9, max: 6.1 },
  BODY_TEMP: { min: 36.0, max: 37.3 },
  HEART_RATE: { min: 60, max: 100 }
};
