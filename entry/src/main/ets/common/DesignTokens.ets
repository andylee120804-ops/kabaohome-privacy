/**
 * 设计 Token - 方向 C · 极简编辑（卡宝红）
 * 纸白底 + 墨黑正文 + 卡宝红（仅 CTA）。flat 编辑风：无卡片阴影、细分隔线、锐利直角。
 * 所有颜色与字号集中在此，便于全局统一维护。
 *
 * 对比度（华为无障碍硬指标：正文 >= 4.5:1，大标题/图标(>=18sp 或 >=14sp 粗体) >= 3:1，
 * 全部在 #FAF7F4 纸底与 #FFFFFF 卡片白双底实测通过）：
 *   - NEUTRAL_INK            16.31 / 17.40  一级文本/标题
 *   - NEUTRAL_INK_SECONDARY   6.27 /  6.69  二级文本（副标题/说明）
 *   - NEUTRAL_INK_TERTIARY    4.64 /  4.95  三级文本/占位（压线通过，勿再调浅）
 *   - NEUTRAL_INK_QUATERNARY  装饰/非文本专用（2.31，禁止用于正文）
 *   - BRAND_RED_LG(#C84A32)   4.39  仅限图标/大标题(>=14sp 粗体)；小字一律用 BRAND_RED
 *   - BRAND_RED(#B8402A)      5.17 /  5.52  小字 CTA 文本 / 白字反色钮
 *   - 白字 on INK             17.40  墨黑主按钮
 */

// ============ 背景层 ============
export const BG_CARD = '#FFFFFF';                  // 卡片白
export const BG_ELEVATED = '#FFFFFF';              // 浮层/弹窗
export const BG_PAPER = '#FAF7F4';                 // 主背景（纸白）
export const BG_SUBTLE = '#F0EFEB';                // 次级背景（选中态/分区底）

// ============ 分隔线/边框（编辑风核心：1px 细线） ============
export const DIVIDER = '#E5E5E5';                   // 主分隔线（列表项/区块）
export const BORDER_CORAL = DIVIDER;               // 兼容旧名：现统一为细线
export const BORDER_SUBTLE = '#ECEAE6';            // 更浅的内部分隔

// ============ 品牌色（卡宝红，仅 CTA） ============
export const BRAND_RED = '#B8402A';                 // 小字 CTA 文本 / 白字钮底
export const BRAND_RED_LG = '#C84A32';              // 大红：图标/大标题(>=14sp 粗体)/today 反白底
export const BRAND_CORAL = BRAND_RED_LG;            // 兼容旧名（图标/强调）
export const BRAND_CORAL_DARK = BRAND_RED;         // 兼容旧名（文本级强调）
export const BRAND_CORAL_LIGHT = '#F3E3DE';        // 浅红底（chip/选中态）
export const CORAL_BG = '#F9E9E4';                 // 兼容旧名：红浅底

// ============ 中性色（冷灰墨调） ============
export const NEUTRAL_INK = '#1A1A1A';               // 一级文本/标题（墨黑）
export const NEUTRAL_INK_SECONDARY = '#5C5C5C';     // 二级文本
export const NEUTRAL_INK_TERTIARY = '#707070';      // 三级文本/占位（压线达标，勿调浅）
export const NEUTRAL_INK_QUATERNARY = '#B0B0B0';   // 四级/装饰/禁用（非正文专用）
export const INK_DISABLED_BG = '#D5D5D5';          // 禁用底/进度条空槽

// ============ 语义色（冷静墨调，纸底全部 >=5:1） ============
export const SEMANTIC_SUCCESS = '#3D6B5C';          // 墨绿（成功/确认）
export const SEMANTIC_WARNING = '#876117';         // 深琥珀（警告）
export const SEMANTIC_ERROR = '#B8402A';            // 深朱红（错误/经期）
export const SEMANTIC_INFO = '#4E6884';             // 雾蓝（信息）
export const MIST_PURPLE = '#6A5A80';               // 雾紫

// ============ 语义色浅底（tag/chip 背景） ============
export const ERROR_BG = '#FAEEE8';                 // 朱红浅底
export const SUCCESS_BG = '#E8F0EC';               // 墨绿浅底
export const WARNING_BG = '#FAF0E0';               // 琥珀浅底
export const INFO_BG = '#E8EDF2';                  // 雾蓝浅底

// ============ 字体 ============
// 编辑风标题用衬线；正文保持默认 HarmonyOS Sans。
// 注意：中文无真斜体，禁止依赖 fontStyle italic 传达层级，用字重与字号对比。
export const FONT_FAMILY_SERIF = 'serif';
export const FONT_DISPLAY = 28;                    // 大标题/空状态数字
export const FONT_TITLE = 20;                      // 页面标题
export const FONT_SUBTITLE = 16;                    // 区块标题/列表主文
export const FONT_BODY_LARGE = 15;                 // 大正文
export const FONT_BODY = 14;                       // 正文
export const FONT_CAPTION = 12;                    // 辅助说明
export const FONT_CAPTION_SM = 11;                 // 小字

// ============ 圆角（编辑风：直角） ============
// 全局直角；圆形元素（圆点/头像）在组件内用 borderRadius('50%') 表达。
export const RADIUS_SM = 0;
export const RADIUS_MD = 0;
export const RADIUS_LG = 0;
export const RADIUS_PILL = 0;

// ============ 间距（8dp 基准） ============
export const SPACE_XS = 4;
export const SPACE_SM = 8;
export const SPACE_MD = 16;
export const SPACE_LG = 24;

// ============ 阴影（编辑风：无阴影，token 保留为透明以防残留引用） ============
export const SHADOW_CARD: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
export const SHADOW_CARD_LG: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
export const SHADOW_BRAND: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };

// ============ 工具函数 ============

/** 根据动作文本返回强调色（编辑风动作为文本按钮，无底色） */
export function getActionColor(action: string): string {
  if (action === '完成') return SEMANTIC_SUCCESS;
  if (action === '查看') return NEUTRAL_INK_SECONDARY;
  return BRAND_RED;
}

/** 兼容旧签名的按钮底色（编辑风下应改用文本动作，见 getActionColor） */
export function getActionBgColor(action: string, primaryColor: string = BRAND_RED): string {
  if (action === '完成') return SEMANTIC_SUCCESS;
  return primaryColor;
}

// ============ 图标资源映射 ============
// $r() 是编译期宏，无法动态拼接，须 switch 映射。
// stroke 1.5px 线性图标，fillColor 染色替换 #000000。

/** 固定 tab 图标资源（首页/我的） */
export function getTabIconRes(tabKey: string): Resource {
  switch (tabKey) {
    case 'home': return $r('app.media.icon_home');
    case 'profile': return $r('app.media.icon_profile');
    default: return $r('app.media.icon_home');
  }
}

/** 模块图标资源映射 */
export function getModuleIconRes(moduleId: string): Resource {
  switch (moduleId) {
    case 'period': return $r('app.media.icon_heart');
    case 'health': return $r('app.media.icon_pill');
    case 'kids': return $r('app.media.icon_book');
    case 'reminder': return $r('app.media.icon_checklist');
    case 'location': return $r('app.media.icon_location');
    case 'album': return $r('app.media.icon_camera');
    case 'shopping': return $r('app.media.icon_cart');
    case 'memo': return $r('app.media.icon_memo');
    case 'accounting': return $r('app.media.icon_wallet');
    default: return $r('app.media.icon_star');
  }
}
