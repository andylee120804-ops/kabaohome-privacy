/**
 * 应用常量定义
 */

// 应用信息
export const APP_NAME = '卡宝Home';
export const APP_BUNDLE_NAME = 'com.family.kabaohome';

// 页面转场动效时长（满足华为UX规范：<8.5寸≥200ms, 8.5-12寸≥250ms, >12寸≥300ms）
export const PAGE_TRANSITION_DURATION = 350;

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

// 预设成员颜色（莫兰迪色系 - 柔和低饱和，方向B）
// 成员色同时作为「选中态白字标签」的背景色，全部加深到白字对比度 >= 4.5:1（审核整改）
export const MEMBER_COLORS: string[] = [
  '#A85668', // 藕粉（白字 5.0:1 ✓）
  '#4F6E88', // 雾蓝（白字 5.4:1 ✓）
  '#96683F', // 暖橙（白字 4.8:1 ✓）
  '#A55847', // 砖红（白字 5.1:1 ✓）
  '#5F7A66', // 鼠尾草绿（白字 4.7:1 ✓）
  '#6A5A80', // 雾紫（白字 6.0:1 ✓）
  '#527478', // 灰青（白字 5.0:1 ✓）
  '#7A6B5D'  // 暖棕（白字 5.0:1 ✓）
];

export interface PeriodMarkColors {
  PERIOD: string;
  PERIOD_TEXT: string;    // 经期日期文字色（用于日历中经期非首天的文字）
  FERTILE: string;
  SAFE: string;
  OVULATION: string;
  INTIMACY: string;
}

// 周期标记色（莫兰迪暖系，与樱花粉主题协调，方向B）
// 审核整改：PERIOD 加深至白字 5.3:1 ✓；经期日期统一实心圆+白字（原 0.85 半透明圆+暗玫
// 瑰字仅 1.7:1，被华为审核判定对比度不足）；其余标记色加深使文字/标签场景 >= 4.5:1
export const PERIOD_MARK_COLORS: PeriodMarkColors = {
  PERIOD: '#C84A32',     // 卡宝红大（经期标记色，白字 on 方格 4.69:1 ✓ ≥14sp bold）
  PERIOD_TEXT: '#FFFFFF', // 经期日期白字
  FERTILE: '#707070',    // 三级灰（易孕，italic 文字 4.64:1 ✓）
  SAFE: '#3D6B5C',       // 墨绿（安全，文字 5.69:1 ✓）
  OVULATION: '#1A1A1A',  // 墨黑粗体（排卵，bold 16.31:1 ✓）
  INTIMACY: '#B8402A'    // 卡宝红深（亲密，文字 5.17:1 ✓）
};

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

/** 模块共享配置解析结果（用于创建单条记录：visibleMembers 已转成 userId） */
export interface ResolvedVisibility {
  visibility: Visibility;
  visibleMembers: string[];
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

// 家庭色系（全部莫兰迪化，方向B - 柔和低饱和暖系）
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
    id: ThemeColor.WARM_CORAL, name: '樱花粉',
    // 审核整改：渐变色板加深，保证其上白色文字 >= 4.5:1（原 #D47D8E 白字仅 2.8:1）
    primary: '#AC5263', gradientStart: '#AC5263', gradientEnd: '#8E3A4C',
    lightBg: '#FFF2F4', border: '#F0D0DA', tag: '🌸'
  },
  {
    id: ThemeColor.OCEAN_BLUE, name: '雾霾蓝',
    primary: '#4A6B85', gradientStart: '#4A6B85', gradientEnd: '#3A5B75',
    lightBg: '#F4F6F8', border: '#D5DEE5', tag: '🌊'
  },
  {
    id: ThemeColor.FOREST_GREEN, name: '鼠尾草绿',
    primary: '#4A7560', gradientStart: '#4A7560', gradientEnd: '#3A6550',
    lightBg: '#F4F7F5', border: '#D5DED7', tag: '🌿'
  },
  {
    id: ThemeColor.SUNSET_AMBER, name: '暮光金',
    primary: '#8A6530', gradientStart: '#8A6530', gradientEnd: '#705525',
    lightBg: '#FAF6F0', border: '#E8DCC8', tag: '🌅'
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
    emojiStyle: '💫', font: '☀️', exit: '🍂'
  },
  {
    id: EmojiStyle.KABAO, name: '卡宝专属',
    modules: '🧩', members: '💝', invite: '🎁', theme: '🌸',
    emojiStyle: '🧸', font: '🌟', exit: '💔'
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
