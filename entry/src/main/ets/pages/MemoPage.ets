/**
 * 卡宝Home - 家庭备忘页面
 * 设计：方向 C 极简编辑 — 纸白底 + 墨黑正文 + flat 行 + 细分隔线
 */
import { Memo, MEMO_CATEGORIES } from '../model/Memo';
import { FamilyMember } from '../model/FamilyMember';
import {
  BG_PAPER, BG_ELEVATED, DIVIDER,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  SEMANTIC_WARNING,
  FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_CAPTION_SM,
  FONT_TITLE, FONT_SUBTITLE, FONT_FAMILY_SERIF,
  SPACE_MD, SPACE_LG,
  getModuleIconRes
} from '../common/DesignTokens';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { Visibility, FontSizeMode, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import { EmptyState } from '../components/EmptyState';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { generateId, formatIsoToLocal, creatorDisplayLabel } from '../common/Utils';
import router from '@ohos.router';

// Simple base64 for obfuscation (not real encryption)
const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function b64idx(c: string): number {
  return Math.max(0, B64_CHARS.indexOf(c));
}

function btoaEncode(str: string): string {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  }
  let result = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    result += B64_CHARS.charAt(b0 >> 2);
    result += B64_CHARS.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
    result += i + 1 < bytes.length ? B64_CHARS.charAt(((b1 & 0x0F) << 2) | (b2 >> 6)) : '=';
    result += i + 2 < bytes.length ? B64_CHARS.charAt(b2 & 0x3F) : '=';
  }
  return result;
}

function btoaDecode(encoded: string): string {
  let bin: number[] = [];
  for (let i = 0; i < encoded.length; i += 4) {
    const c0 = b64idx(encoded.charAt(i));
    const c1 = b64idx(encoded.charAt(i + 1));
    const c2 = encoded.charAt(i + 2) === '=' ? 0 : b64idx(encoded.charAt(i + 2));
    const c3 = encoded.charAt(i + 3) === '=' ? 0 : b64idx(encoded.charAt(i + 3));
    bin.push((c0 << 2) | (c1 >> 4));
    if (encoded.charAt(i + 2) !== '=') bin.push(((c1 & 0x0F) << 4) | (c2 >> 2));
    if (encoded.charAt(i + 3) !== '=') bin.push(((c2 & 0x03) << 6) | c3);
  }
  let result = '';
  let idx = 0;
  while (idx < bin.length) {
    const byte = bin[idx];
    if (byte < 0x80) {
      result += String.fromCharCode(byte);
      idx++;
    } else if ((byte & 0xE0) === 0xC0) {
      result += String.fromCharCode(((byte & 0x1F) << 6) | (bin[idx + 1] & 0x3F));
      idx += 2;
    } else {
      result += String.fromCharCode(((byte & 0x0F) << 12) | ((bin[idx + 1] & 0x3F) << 6) | (bin[idx + 2] & 0x3F));
      idx += 3;
    }
  }
  return result;
}

interface VisibilityOption {
  value: Visibility;
  label: string;
}

@Entry
@Component
struct MemoPage {
  private visibilityOptions: VisibilityOption[] = [
    { value: Visibility.PRIVATE, label: '仅自己' },
    { value: Visibility.SELECTED, label: '指定成员' },
    { value: Visibility.FAMILY, label: '家庭可见' }
  ];

  @State memos: Memo[] = [];
  @State isRefreshing: boolean = false;
  @State familyMembers: FamilyMember[] = [];
  @State selectedCategory: string = '';
  @State showAddDialog: boolean = false;
  @State isSavingMemo: boolean = false;
  @State newTitle: string = '';
  @State newContent: string = '';
  @State newCategory: string = '其他';
  @State newIsObfuscated: boolean = false;
  @State newVisibility: Visibility = Visibility.PRIVATE;
  @State newVisibleUserIds: string[] = [];
  @State memberCandidates: FamilyMember[] = [];
  @State editingMemoId: string = '';
  @State searchText: string = '';
  @State showMemoDetail: boolean = false;
  @State detailMemo: Memo | null = null;
  @State isLargeFont: boolean = false;
  @State fontSize: number = FONT_SUBTITLE;
  @State titleFontSize: number = FONT_TITLE;

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  private recordCreatorLabel(creatorId: string): string {
    if (!creatorId || this.isCreator(creatorId)) return '';
    return creatorDisplayLabel(creatorId, this.familyMembers);
  }

  private async handlePullRefresh(): Promise<void> {
    try {
      const familyId = this.db.getCurrentFamilyId();
      if (familyId && CloudService.getInstance().isCloudAvailable()) {
        await CloudService.getInstance().syncAll(familyId, true);
      }
    } finally {
      this.isRefreshing = false;
      this.memos = this.db.getMemos();
    }
  }

  private buildShareableMembers(): FamilyMember[] {
    const all = this.familyVm.getFamilyMembers();
    const currentUserId = this.db.getCurrentUserId();
    const currentMemberId = this.db.getCurrentMemberId();
    const result: FamilyMember[] = [];
    for (let i = 0; i < all.length; i++) {
      const m = all[i];
      if (!m || m.isDeleted === true) continue;
      if (!m.userId) continue;
      if (currentMemberId && m.id === currentMemberId) continue;
      if (currentUserId && m.userId === currentUserId) continue;
      result.push(m);
    }
    return result;
  }

  private toggleVisibleMember(userId: string): void {
    const idx = this.newVisibleUserIds.indexOf(userId);
    if (idx >= 0) {
      this.newVisibleUserIds = this.newVisibleUserIds.filter(id => id !== userId);
    } else {
      this.newVisibleUserIds = [...this.newVisibleUserIds, userId];
    }
  }

  private isMemberSelected(userId: string): boolean {
    return this.newVisibleUserIds.indexOf(userId) >= 0;
  }

  private selectVisibility(value: Visibility): void {
    this.newVisibility = value;
    if (value !== Visibility.SELECTED) return;
    if (this.newVisibleUserIds.length > 0) return;
    const moduleVis = this.db.resolveModuleVisibilityForRecord(ModuleId.MEMO);
    if (moduleVis.visibility === Visibility.SELECTED && moduleVis.visibleMembers.length > 0) {
      this.newVisibleUserIds = [...moduleVis.visibleMembers];
    }
  }

  aboutToAppear(): void {
    this.memos = this.db.getMemos();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    this.familyMembers = this.familyVm.getFamilyMembers();
    this.memberCandidates = this.buildShareableMembers();
    this.fontSize = this.isLargeFont ? FONT_SUBTITLE + 4 : FONT_SUBTITLE;
    this.titleFontSize = this.isLargeFont ? FONT_TITLE + 4 : FONT_TITLE;
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
  }
