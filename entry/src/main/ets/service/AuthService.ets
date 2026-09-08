/**
 * 认证服务 - 管理用户登录状态
 *
 * 认证链路：
 * 1. 华为账号登录（@kit.AccountKit）→ 获取 openID
 * 2. AGC Auth 关联登录（@kit.CloudFoundationKit）→ 获取 AGC UID
 * 3. UID 作为后续 Cloud DB / Cloud Function 的身份凭证
 *
 * 华为账号登录通过 Provider 注入模式，避免 debug HAP 因模块受限而崩溃
 *
 * @example
 * ```typescript
 * const auth = AuthService.getInstance();
 * auth.setContext(this.context);
 * auth.setHuaweiLoginProvider(silentLogin, explicitLogin);
 * auth.setAgcConfig(AgcConfig.getInstance());
 * const userId = await auth.silentLogin();
 * ```
 */
import { LocalDbService } from './LocalDbService';
import { AgcConfig } from './AgcConfig';
import { CloudService, CloudOperation } from './CloudService';
import { ReminderService } from './ReminderService';
import { LocationReporter } from './LocationReporter';
import { FamilyMember } from '../model/FamilyMember';
import { Family } from '../model/Family';
import { MemberRole, MemberStatus, MEMBER_COLORS, ModuleId, FontSizeMode } from '../common/Constants';
import { generateId, generateSecureCode, defaultAvatarForRole } from '../common/Utils';
import { unpackOpenID, unpackIdToken } from './HuaweiAccountProvider';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const TAG = '[AuthService]';
const DOMAIN = 0x0000;

/** 华为账号登录函数签名（由外部 Provider 文件注入） */
export type HuaweiLoginFn = (context: common.Context | null) => Promise<string>;

/** 当前账号摘要（用于"我的"页展示账号身份） */
export interface AccountSummary {
  /** 账号类型：huawei / offline / none */
  type: string;
  /** 显示标签：华为账号 / 离线账号 / 未登录 */
  label: string;
  /** 脱敏 ID（如 ****1234），未登录时为空 */
  maskedId: string;
}

/** 云函数 validate-invite 参数 */
interface ValidateInviteParams {
  inviteCode: string;
}

/** 云函数 validate-claim 参数 */
interface ValidateClaimParams {
  claimToken: string;
}

/** 云函数 claim-member 参数 */
interface ClaimMemberParams {
  claimToken: string;
}

/** claim-member 云函数返回的家庭信息 */
interface ClaimFamilyInfo {
  id: string;
  name: string;
  creatorId: string;
  inviteCode: string;
  inviteCodeExpiresAt: string;
}

/** claim-member 云函数返回结果 */
interface ClaimMemberResult {
  member: FamilyMember;
  family: ClaimFamilyInfo | null;
}

export class AuthService {
  private static instance: AuthService | null = null;
  private db: LocalDbService = LocalDbService.getInstance();
  private currentUserId: string = '';
  /** 云端 validate-claim 返回的家庭名（认领时构建占位家庭使用） */
  private pendingClaimFamilyName: string = '';
  private agcUserId: string = ''; // AGC Auth UID，用于云端操作
  private currentUnionId: string = ''; // 华为账号 unionID，跨应用唯一标识
  private currentMember: FamilyMember | null = null;
  private uiContext: common.Context | null = null;
  private agcConfig: AgcConfig | null = null;

  private huaweiLoginImpl: HuaweiLoginFn | null = null;
  private huaweiSilentLoginImpl: HuaweiLoginFn | null = null;

  /**
   * 用户主动退出登录标志
   *
   * 为什么需要这个标志：
   * logout() 清除 userId/unionId/hasFamily，但保留家庭数据记录。
   * 如果 LoginPage 的 explicitLogout 路由参数因 router.clear() 等原因丢失，
   * silentLogin 会在华为账号已授权设备上静默成功并调用 restoreFamilyContext 恢复家庭上下文，
   * 导致用户退出登录后被意外拉回首页看到家庭数据。
   * 此标志作为第二道防线：logout 置 true，任意登录成功路径清除，silentLogin 命中即返回空。
   */
  private explicitlyLoggedOut: boolean = false;

  private constructor() {}

  static getInstance(): AuthService {
    if (!AuthService.instance) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  setContext(context: common.Context): void {
    this.uiContext = context;
  }

  /** 注入华为账号登录实现（由启动代码在安全上下文中调用） */
  setHuaweiLoginProvider(silentLogin: HuaweiLoginFn, explicitLogin: HuaweiLoginFn): void {
    this.huaweiSilentLoginImpl = silentLogin;
    this.huaweiLoginImpl = explicitLogin;
    hilog.info(0x0000, TAG, 'Huawei login provider registered');
  }

  /** 注入 AGC 配置（由 EntryAbility.onCreate 调用） */
  setAgcConfig(agc: AgcConfig): void {
    this.agcConfig = agc;
    hilog.info(DOMAIN, TAG, 'AGC config injected');
  }

  /** 获取当前登录用户 ID（优先内存缓存，否则从本地存储读取） */
  getCurrentUserId(): string {
    if (!this.currentUserId) {
      this.currentUserId = this.db.getCurrentUserId();
    }
    return this.currentUserId;
  }

  /** 获取 AGC UID，用于云端操作鉴权 */
  getAgcUserId(): string {
    return this.agcUserId;
  }

  /** 获取华为账号 unionID（跨应用唯一标识），离线账号返回空串 */
  getUnionId(): string {
    if (!this.currentUnionId) {
      this.currentUnionId = this.db.getHuaweiUnionId();
    }
    return this.currentUnionId;
  }

  /** 获取当前用户在当前家庭中的成员记录 */
  getCurrentMember(): FamilyMember | null {
    if (this.currentMember) return this.currentMember;
    const userId = this.getCurrentUserId();
    if (!userId) return null;
    const family = this.db.getCurrentFamily();
    if (!family) return null;
    // 在当前家庭范围内查找当前用户的成员记录
    const members = this.db.getMembersByFamilyId(family.id);
    this.currentMember = members.find(m => m.userId === userId && m.status === MemberStatus.ACTIVE) ?? null;
    // 兜底：如果 userId 不匹配任何成员，但该用户是家庭创建者（family.creatorId === userId），
    // 尝试用 creatorId 匹配成员（离线→华为账号切换后本地 FamilyMember.userId 仍为旧 ID 的场景）
    if (!this.currentMember && family.creatorId === userId) {
      this.currentMember = members.find(m => m.userId === family.creatorId && m.status === MemberStatus.ACTIVE) ?? null;
    }
    return this.currentMember;
  }

  /** 用户是否已登录（userId 非空） */
  isLoggedIn(): boolean {
    return this.getCurrentUserId() !== '';
  }

  hasFamily(): boolean {
    return this.db.hasFamily();
  }

  /**
   * 离线登录 - 无华为账号时使用临时 ID
   * @param userId - 可选的自定义 ID，不传则自动生成 offline_xxx
   * @returns 登录后的用户 ID
   */
  async offlineLogin(userId?: string): Promise<string> {
    if (!userId) {
      userId = `offline_${generateId('usr')}`;
    }
    this.currentUserId = userId;
    this.explicitlyLoggedOut = false;
    await this.db.saveCurrentUserId(userId);
    hilog.info(0x0000, TAG, 'Offline login: %{public}s', userId);
    return userId;
  }

  // ===== 华为账号登录（Provider 代理模式） =====

  async silentLogin(): Promise<string> {
    // 用户主动退出登录后，禁止静默登录，避免华为账号自动登录把用户又踢回首页
    if (this.explicitlyLoggedOut) {
      hilog.info(0x0000, TAG, 'Silent login skipped: user explicitly logged out');
      return '';
    }
    if (!this.huaweiSilentLoginImpl) {
      return '';
    }
    try {
      const packed = await this.huaweiSilentLoginImpl(this.uiContext);
      const openID = unpackOpenID(packed);
      const idToken = unpackIdToken(packed);
      if (openID) {
        this.currentUserId = openID;
        this.explicitlyLoggedOut = false;
        await this.db.saveCurrentUserId(this.currentUserId);
        // 先从云端恢复数据（新设备/重装后登录需要）
        await this.restoreFromCloud(openID);
        // 恢复家庭上下文（与 completeHuaweiLogin 保持一致）
        await this.restoreFamilyContext(openID);
        // 关联 AGC Auth：用华为账号 idToken 登录 AGC
        await this.linkAgcAuth(openID, idToken);
        hilog.info(0x0000, TAG, 'Silent login success: %{public}s', openID);
        return openID;
      }
      return '';
    } catch (err) {
      hilog.warn(0x0000, TAG, 'Silent login failed: %{public}s', (err as Error).message);
      return '';
    }
  }

  async huaweiLogin(): Promise<string> {
    if (!this.huaweiLoginImpl) {
      throw new Error('华为账号登录暂不可用（需正式签名包）');
    }
    const packed = await this.huaweiLoginImpl(this.uiContext);
    return await this.completeHuaweiLogin(unpackOpenID(packed), undefined, unpackIdToken(packed));
  }

  /**
   * 用已获取的华为账号 openID 完成登录后续流程
   *
   * LoginWithHuaweiIDButton 组件回调中已拿到 credential.openID / credential.unionID，
   * 调用本方法写入本地登录态并关联 AGC。
   * @param openID 华为账号 openID（本应用内唯一）
   * @param unionID 华为账号 unionID（跨应用唯一，可选，用于账号展示）
   * @param idToken 华为账号 idToken（可选，用于 AGC Auth 登录）
   * @returns 登录后的用户 ID
   */
  async completeHuaweiLogin(openID: string, unionID?: string, idToken?: string): Promise<string> {
    if (!openID) {
      throw new Error('未获取到 Huawei OpenID');
    }
    this.currentUserId = openID;
    this.explicitlyLoggedOut = false;
    await this.db.saveCurrentUserId(this.currentUserId);
    if (unionID) {
      this.currentUnionId = unionID;
      await this.db.saveHuaweiUnionId(unionID);
    }
    // 先从云端恢复数据（新设备/重装后登录需要）
    await this.restoreFromCloud(openID);
    // 恢复家庭上下文：如果该用户已存在于某个家庭中，恢复 hasFamily 标志
    await this.restoreFamilyContext(openID);
    // 关联 AGC Auth：用华为账号 idToken 登录 AGC（失败时降级为 __uid 兜底模式）
    await this.linkAgcAuth(openID, idToken);
    hilog.info(0x0000, TAG, 'Huawei login success: %{public}s', openID);
    return openID;
  }

  /**
   * 当前账号摘要（用于"我的"页展示）
   * - 华为账号：展示 unionID 末 4 位脱敏
   * - 离线账号：展示本地 ID 末 4 位脱敏
   * - 未登录：返回空
   */
  getAccountSummary(): AccountSummary {
    const userId = this.getCurrentUserId();
    if (!userId) {
      const none: AccountSummary = { type: 'none', label: '未登录', maskedId: '' };
      return none;
    }
    if (this.isHuaweiAccount()) {
      const unionId = this.getUnionId();
      const huawei: AccountSummary = {
        type: 'huawei',
        label: '华为账号',
        maskedId: `****${this.maskTail(unionId || userId)}`,
      };
      return huawei;
    }
    const offline: AccountSummary = {
      type: 'offline',
      label: '离线账号',
      maskedId: `****${this.maskTail(userId.replace('offline_', ''))}`,
    };
    return offline;
  }

  /** 取字符串末 4 位（不足 4 位则原样返回），用于脱敏展示 */
  private maskTail(value: string): string {
    if (!value) return '';
    return value.length > 4 ? value.slice(-4) : value;
  }

  /**
   * 当前账号完整 ID（用于核对/复制）
   * - 华为账号：优先返回 unionID（跨应用唯一），fallback openID
   * - 离线账号：返回本地 user ID
   * - 未登录：返回空串
   */
  getAccountFullId(): string {
    const userId = this.getCurrentUserId();
    if (!userId) return '';
    if (this.isHuaweiAccount()) {
      return this.getUnionId() || userId;
    }
    return userId;
  }

  /** 当前用户是否为华为账号登录（非离线账号） */
  isHuaweiAccount(): boolean {
    return this.currentUserId !== '' && !this.currentUserId.startsWith('offline_');
  }

  /**
   * 从云端恢复数据 - 登录后自动拉取该用户的所有家庭数据
   *
   * 核心场景：
   * - 新设备登录 → 本地无数据 → 从云端全量拉取
   * - 卸载重装 → 本地无数据 → 从云端全量拉取
   * - 已有本地数据 → 增量合并（云端版本覆盖本地旧版本）
   *
   * 如果本地已有家庭数据，跳过全量拉取（由 syncAll 增量同步即可）。
   */
  private async restoreFromCloud(userId: string): Promise<void> {
    const cloud = CloudService.getInstance();
    if (!cloud.isCloudAvailable()) {
      hilog.info(DOMAIN, TAG, 'restoreFromCloud: cloud not available, skip');
      return;
    }

    // 如果本地已有家庭数据，不需要全量拉取（syncAll 会增量同步）
    if (this.db.hasFamily() && this.db.getFamilies().length > 0) {
      hilog.info(DOMAIN, TAG, 'restoreFromCloud: local data exists, skip full pull');
      return;
    }

    hilog.info(DOMAIN, TAG, 'restoreFromCloud: no local data, pulling from cloud for userId=%{public}s', userId);

    try {
      // 1. 调用 my-families 云函数 → 按 userId 查询所属家庭
      const emptyParams: Record<string, Object> = {};
      const myFamiliesResult = await cloud.callCloudFunction('my-families', emptyParams);

      if (myFamiliesResult.code !== 0 || !myFamiliesResult.data) {
        hilog.info(DOMAIN, TAG, 'restoreFromCloud: my-families returned no data (code=%{public}d)',
          myFamiliesResult.code);
        return;
      }

      const data = myFamiliesResult.data as Record<string, Object>;
      const families = data['families'] as object[];
      const memberships = data['memberships'] as object[];

      if (!families || families.length === 0) {
        hilog.info(DOMAIN, TAG, 'restoreFromCloud: user has no families in cloud');
        return;
      }

      // 2. 保存家庭成员关系到本地
      if (memberships && memberships.length > 0) {
        await this.db.syncFromCloud({ 'FamilyMember': memberships });
      }

      // 3. 保存家庭信息到本地
      await this.db.syncFromCloud({ 'Family': families });

      // 4. 用第一个家庭的 familyId 全量拉取所有数据
      const firstFamily = families[0] as Record<string, Object>;
      const familyId = firstFamily['id'] as string;

      if (familyId) {
        hilog.info(DOMAIN, TAG, 'restoreFromCloud: pulling all data for familyId=%{public}s', familyId);
        await cloud.fullPullAndMerge(familyId);
      }

      // 5. 恢复 hasFamily 标志
      await this.db.saveHasFamily(true);

      hilog.info(DOMAIN, TAG, 'restoreFromCloud: completed, familyId=%{public}s', familyId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'restoreFromCloud failed (non-blocking): %{public}s',
        (err as Error).message);
    }
  }

  /**
   * 恢复家庭上下文 - 华为账号登录时检查该用户是否已有家庭
   *
   * logout() 会清除 hasFamily 标志，但保留家庭数据。
   * 当同一华为账号重新登录时，需要恢复 hasFamily=true，
   * 以便直接进入首页而非被迫重新创建/加入家庭。
   * 离线账号因为 userId 不同，不会被匹配到旧家庭，自然从零开始。
   */
  private async restoreFamilyContext(userId: string): Promise<void> {
    const families = this.db.getFamilies();
    const members = this.db.getMembers();

    hilog.info(0x0000, TAG, 'restoreFamilyContext: userId=%{public}s, families=%{public}d, members=%{public}d',
      userId, families.length, members.length);

    // 查找该 userId 对应的活跃家庭成员记录
    const memberRecord = members.find(m => m.userId === userId && m.status === MemberStatus.ACTIVE);
    if (memberRecord) {
      const family = families.find(f => f.id === memberRecord.familyId);
      if (family) {
        await this.db.saveHasFamily(true);
        this.currentMember = memberRecord;
        hilog.info(0x0000, TAG, 'Family context restored for user: %{public}s, family=%{public}s', userId, family.id);
        return;
      }
      hilog.warn(0x0000, TAG, 'restoreFamilyContext: member found but family %{public}s not in families list',
        memberRecord.familyId);
    }

    // 查找是否有以该 userId 为创建者的家庭
    const ownedFamily = families.find(f => f.creatorId === userId);
    if (ownedFamily) {
      await this.db.saveHasFamily(true);
      // 尝试在该家庭中找到创建者的成员记录（可能是 creatorId 与当前 userId 匹配、
      // 但 FamilyMember.userId 不同的情况，如离线→华为账号切换后本地残留旧 ID）
      const familyMembers = this.db.getMembersByFamilyId(ownedFamily.id);
      // 优先匹配 userId
      const creatorMember = familyMembers.find(m => m.userId === userId && m.status === MemberStatus.ACTIVE)
        // 兜底：匹配 creatorId 对应的成员（创建者自己的记录，无论 userId 是否一致）
        ?? familyMembers.find(m => m.userId === ownedFamily.creatorId && m.status === MemberStatus.ACTIVE)
        ?? null;
      this.currentMember = creatorMember;
      hilog.info(0x0000, TAG, 'Family context restored (as creator) for user: %{public}s, memberFound=%{public}s',
        userId, !!creatorMember);
      return;
    }

    // 诊断：列出所有成员的 userId 和所有家庭的 creatorId，便于定位不匹配原因
    const memberUserIds = members.map(m => `${m.userId}(${m.status})`).join(', ');
    const familyCreatorIds = families.map(f => f.creatorId).join(', ');
    hilog.warn(0x0000, TAG,
      'restoreFamilyContext FAILED: looking for userId=%{public}s; member userIds: [%{public}s]; family creatorIds: [%{public}s]',
      userId, memberUserIds, familyCreatorIds);

    // 没有找到关联家庭，保持 hasFamily=false（用户需要创建/加入家庭）
    hilog.info(0x0000, TAG, 'No existing family found for user: %{public}s', userId);
  }

  async logout(): Promise<void> {
    // 诊断：记录退出前家庭/成员数据量，确认数据未被意外清除
    const famCount = this.db.getFamilies().length;
    const memCount = this.db.getMembers().length;
    hilog.info(0x0000, TAG, 'logout start: families=%{public}d, members=%{public}d', famCount, memCount);

    this.currentUserId = '';
    this.currentUnionId = '';
    this.currentMember = null;
    this.explicitlyLoggedOut = true;
    await this.db.saveCurrentUserId('');
    await this.db.saveHuaweiUnionId('');
    // 清除家庭归属标志（保留数据，但要求下次登录重新确认家庭关系）
    // 离线登录时 hasFamily=false → FamilySetupPage（全新开始）
    // 华为账号登录时 restoreFamilyContext 会恢复此标志
    await this.db.saveHasFamily(false);

    // 诊断：确认退出后数据仍保留
    const famAfter = this.db.getFamilies().length;
    const memAfter = this.db.getMembers().length;
    hilog.info(0x0000, TAG, 'logout done: families=%{public}d, members=%{public}d (data should be preserved)',
      famAfter, memAfter);
  }

  /** 用户是否主动退出了登录（用于 LoginPage 跳过 silentLogin 的第二道防线） */
  isExplicitlyLoggedOut(): boolean {
    return this.explicitlyLoggedOut;
  }

  setCurrentMember(member: FamilyMember): void {
    this.currentMember = member;
  }

  async saveFamily(family: Family): Promise<void> {
    await this.db.saveFamily(family);
  }

  getFamily(): Family | null {
    return this.db.getCurrentFamily();
  }

  async addMember(member: FamilyMember): Promise<void> {
    await this.db.saveMember(member);
  }

  async updateMember(member: FamilyMember): Promise<void> {
    await this.db.updateMember(member);
  }

  async removeMember(memberId: string): Promise<void> {
    if (!this.isCreator()) {
      throw new Error('仅家庭创建者可以删除成员');
    }
    // 不允许创建者删除自己（应使用退出家庭）
    const currentUserId = this.getCurrentUserId();
    const members = this.db.getMembers();
    const target = members.find(m => m.id === memberId);
    if (target && target.userId === currentUserId) {
      throw new Error('不能删除自己，如需退出请使用退出家庭');
    }
    await this.db.removeMember(memberId);
  }

  getMembers(): FamilyMember[] {
    return this.db.getMembers();
  }

  isCreator(): boolean {
    const member = this.getCurrentMember();
    const family = this.getFamily();
    if (!family) return false;
    // 优先用 member.userId 比较（两者都是 openID，正常情况匹配）
    if (member && family.creatorId === member.userId) return true;
    // 兜底：直接比 family.creatorId 与当前登录 userId
    // 场景：getCurrentMember() 返回 null（如成员列表被云端覆盖后 userId 不匹配缓存）、
    // 或 member.userId 与 creatorId 来源不同（离线→华为账号切换后本地数据残留旧 ID）
    const uid = this.getCurrentUserId();
    return !!uid && family.creatorId === uid;
  }

  reloadCurrentMember(): void {
    this.currentMember = null;
    this.getCurrentMember();
  }

  // ===== 家庭管理业务方法 =====

  /** 创建家庭 */
  async createFamily(name: string, memberName: string, role: MemberRole, color: string): Promise<Family> {
    const userId = this.getCurrentUserId();
    if (!userId) {
      throw new Error('未登录');
    }
    const now = new Date().toISOString();
    const code = await generateSecureCode();

    const family = new Family();
    family.id = generateId('fam');
    family.name = name;
    family.creatorId = userId;
    family.inviteCode = code;
    family.inviteCodeExpiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    family.createdAt = now;
    family.updatedAt = now;

    const member = new FamilyMember();
    member.id = generateId('mem');
    member.familyId = family.id;
    member.userId = userId;
    member.name = memberName;
    member.role = role;
    member.color = color;
    member.avatar = defaultAvatarForRole(role);
    member.createdAt = now;
    member.updatedAt = now;

    await this.db.saveFamily(family);
    await this.db.saveMember(member);
    await this.db.saveHasFamily(true);
    // 初始化默认模块：姨妈、家庭提醒、家庭记账
    await this.db.saveEnabledModules([ModuleId.PERIOD, ModuleId.REMINDER, ModuleId.ACCOUNTING]);

    this.currentMember = member;

    // 后台同步到云端（不阻塞 UI）。processQueue 403 自愈机制会在后续推送时恢复 membership。
    this.syncFamilyAfterJoin(family.id, member).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'createFamily: background cloud sync failed: %{public}s', err.message);
    });

    return family;
  }

  /** 通过邀请码加入家庭 */
  async joinFamilyByCode(code: string, memberName: string, role: MemberRole): Promise<Family | null> {
    const userId = this.getCurrentUserId();
    if (!userId) {
      throw new Error('未登录');
    }

    // 1) 优先走云端验证（跨设备核心场景）
    hilog.info(0x0000, TAG, 'joinFamilyByCode: code=%{public}s, trying cloud first', code);
    let family = await this.validateInviteCodeCloud(code);

    // 2) 云端未找到 → 降级查本地（离线场景）
    if (!family) {
      const families = this.db.getFamilies();
      family = families.find(f => f.inviteCode === code) ?? null;
      hilog.info(0x0000, TAG, 'joinFamilyByCode: cloud miss, local fallback found=%{public}s', !!family);
    } else {
      // 云端找到 → 保存到本地
      await this.db.saveFamily(family);
      hilog.info(0x0000, TAG, 'joinFamilyByCode: cloud family saved locally, id=%{public}s', family.id);
    }

    if (!family) {
      hilog.warn(0x0000, TAG, 'joinFamilyByCode: no family found with inviteCode=%{public}s (local+cloud)', code);
      return null;
    }
    hilog.info(0x0000, TAG,
      'joinFamilyByCode: family resolved, id=%{public}s, name=%{public}s, creatorId=%{public}s',
      family.id || '(empty)', family.name || '(empty)', family.creatorId || '(empty)');
    if (family.inviteCodeExpiresAt && new Date(family.inviteCodeExpiresAt) < new Date()) {
      hilog.warn(0x0000, TAG, 'joinFamilyByCode: invite code expired at %{public}s', family.inviteCodeExpiresAt);
      return null;
    }

    const now = new Date().toISOString();

    // 检查是否已是该家庭的活跃成员（防止重复点击等原因导致重复加入）
    const existingMembers = this.db.getMembersByFamilyId(family.id);
    const existingActive = existingMembers.find(m => m.userId === userId && m.status === MemberStatus.ACTIVE);
    if (existingActive) {
      hilog.info(0x0000, TAG, 'joinFamilyByCode: user already an active member, id=%{public}s, skipping duplicate join', existingActive.id);
      await this.db.saveHasFamily(true);
      this.currentMember = existingActive;
      return family;
    }

    // 检查是否有待认领的同角色成员（家人已提前添加）
    const unclaimedMember = this.findUnclaimedByRole(family.id, role);
    if (unclaimedMember) {
      // 认领已有记录，而非创建新记录
      unclaimedMember.userId = userId;
      unclaimedMember.status = MemberStatus.ACTIVE;
      unclaimedMember.claimToken = '';
      unclaimedMember.name = memberName; // 更新为本人填写的名字
      unclaimedMember.updatedAt = now;
      await this.db.updateMember(unclaimedMember);
      await this.db.saveHasFamily(true);
      this.currentMember = unclaimedMember;
      hilog.info(0x0000, TAG, 'Auto-claimed member on join: %{public}s -> %{public}s', unclaimedMember.id, userId);
      await this.syncFamilyAfterJoin(family.id, unclaimedMember);
      return family;
    }

    // 没有待认领记录 → 创建新成员
    const member = new FamilyMember();
    member.id = generateId('mem');
    member.familyId = family.id;
    member.userId = userId;
    member.name = memberName;
    member.role = role;
    member.color = MEMBER_COLORS[0];
    member.avatar = defaultAvatarForRole(role);
    member.status = MemberStatus.ACTIVE;
    member.createdAt = now;
    member.updatedAt = now;

    hilog.info(0x0000, TAG, "joinFamilyByCode: creating new member, id=%{public}s, familyId=%{public}s, userId=%{public}s", member.id, family.id, member.userId);
    await this.db.saveMember(member);
    await this.db.saveHasFamily(true);

    this.currentMember = member;
    await this.syncFamilyAfterJoin(family.id, member);
    return family;
  }

  /** 添加监护成员（代管）- 适用于无自有设备的孩子/老人，不需要认领 */
  async addCustodialMember(familyId: string, name: string, role: MemberRole): Promise<FamilyMember> {
    const now = new Date().toISOString();
    const member = new FamilyMember();
    member.id = generateId('mem');
    member.familyId = familyId;
    member.userId = generateId('usr'); // 代管成员使用临时ID，由家人代操作
    member.name = name;
    member.role = role;
    member.color = MEMBER_COLORS[0];
    member.avatar = defaultAvatarForRole(role);
    member.isCustodial = true;
    member.status = MemberStatus.ACTIVE; // 代管成员直接激活
    member.createdAt = now;
    member.updatedAt = now;
    await this.db.saveMember(member);
    return member;
  }

  /** 添加家庭成员 */
  async addFamilyMember(familyId: string, name: string, role: MemberRole, isCustodial: boolean = false): Promise<FamilyMember> {
    const now = new Date().toISOString();
    const member = new FamilyMember();
    member.id = generateId('mem');
    member.familyId = familyId;
    member.name = name;
    member.role = role;
    member.color = MEMBER_COLORS[0];
    member.avatar = defaultAvatarForRole(role);
    member.isCustodial = isCustodial;
    member.createdAt = now;
    member.updatedAt = now;

    if (isCustodial) {
      // 代管成员：生成临时userId，无需认领
      member.userId = generateId('usr');
      member.status = MemberStatus.ACTIVE;
    } else {
      // 非代管成员：生成临时userId + claimToken，等待本人认领
      member.userId = generateId('usr');
      member.claimToken = await this.generateClaimToken();
      member.status = MemberStatus.UNCLAIMED;
    }

    await this.db.saveMember(member);
    return member;
  }

  /** 生成6位认领令牌（使用加密安全随机数） */
  private async generateClaimToken(): Promise<string> {
    return await generateSecureCode();
  }

  /**
   * 通过认领令牌认领家庭成员身份
   * 被添加的家人用真实账号登录后，输入claimToken将userId替换为真实ID
   */
  async claimMemberByToken(claimToken: string): Promise<FamilyMember | null> {
    const userId = this.getCurrentUserId();
    if (!userId) throw new Error('未登录');

    hilog.info(0x0000, TAG, 'claimMemberByToken: token=%{public}s', claimToken);

    // 1) 调用 claim-member 云函数：服务端直接更新 Cloud DB（status=ACTIVE, userId=uid, claimToken=''）
    //    不依赖客户端 push-data 推送，避免 membership 检查/竞态时序导致云端 status 不更新。
    const cloudResult = await this.claimMemberCloud(claimToken);
    if (!cloudResult) {
      hilog.warn(0x0000, TAG, 'claimMemberByToken: claim-member cloud function failed');
      return null;
    }

    const claimedMember = cloudResult.member;
    const claimedFamily = cloudResult.family;

    // 2) 保存家庭到本地（用云端返回的真实家庭名，不是占位"我的家庭"）
    const families = this.db.getFamilies();
    const existingFamily = families.find(f => f.id === claimedMember.familyId);
    if (!existingFamily) {
      const family = new Family();
      family.id = claimedMember.familyId;
      family.name = (claimedFamily && claimedFamily.name) ? claimedFamily.name : '我的家庭';
      family.creatorId = (claimedFamily && claimedFamily.creatorId) ? claimedFamily.creatorId : '';
      family.inviteCode = (claimedFamily && claimedFamily.inviteCode) ? claimedFamily.inviteCode : '';
      family.inviteCodeExpiresAt = (claimedFamily && claimedFamily.inviteCodeExpiresAt) ? claimedFamily.inviteCodeExpiresAt : '';
      family.createdAt = claimedMember.createdAt;
      family.updatedAt = claimedMember.updatedAt;
      await this.db.saveFamily(family);
      hilog.info(DOMAIN, TAG, 'claimMemberByToken: family saved, name=%{public}s', family.name);
    } else if (claimedFamily && claimedFamily.name && existingFamily.name !== claimedFamily.name) {
      existingFamily.name = claimedFamily.name;
      existingFamily.creatorId = claimedFamily.creatorId || existingFamily.creatorId;
      existingFamily.inviteCode = claimedFamily.inviteCode || existingFamily.inviteCode;
      existingFamily.inviteCodeExpiresAt = claimedFamily.inviteCodeExpiresAt || existingFamily.inviteCodeExpiresAt;
      const allFamilies = families.map(f => f.id === claimedMember.familyId ? existingFamily : f);
      await this.db.saveList<Family>('families', allFamilies);
      hilog.info(DOMAIN, TAG, 'claimMemberByToken: family name updated to %{public}s', claimedFamily.name);
    }

    // 3) 保存 member 到本地（status=ACTIVE, userId=真实uid, role=云端返回值）
    const localMembers = this.db.getMembers();
    const existingMember = localMembers.find(m => m.id === claimedMember.id);
    if (existingMember) {
      await this.db.updateMember(claimedMember);
    } else {
      await this.db.saveMember(claimedMember);
    }
    await this.db.saveHasFamily(true);

    this.currentMember = claimedMember;
    hilog.info(DOMAIN, TAG, 'Member claimed: %{public}s -> %{public}s, role=%{public}s',
      claimedMember.id, userId, claimedMember.role);

    // 4) 拉取家庭其他数据（member 已在云端更新，push 会 upsert 相同 ACTIVE 状态，无副作用）
    await this.syncFamilyAfterJoin(claimedMember.familyId, claimedMember);

    return claimedMember;
  }

  /**
   * 调用 claim-member 云函数，在服务端完成认领
   *
   * 云函数直接更新 Cloud DB 的 FamilyMember 记录：
   *   status=ACTIVE, userId=uid, claimToken='', updatedAt=now
   * 返回更新后的 member 和 family 信息。
   */
  private async claimMemberCloud(token: string): Promise<ClaimMemberResult | null> {
    const cloud = CloudService.getInstance();
    if (!cloud.isCloudAvailable()) {
      hilog.warn(DOMAIN, TAG, 'claimMemberCloud: cloud not available');
      return null;
    }
    try {
      const claimParams: ClaimMemberParams = {
        claimToken: token
      };
      const result = await cloud.callCloudFunction('claim-member', claimParams);
      if (result.code === 0 && result.data) {
        const d = result.data as Record<string, Object>;
        const memData = d['member'] as Record<string, Object>;
        const member = new FamilyMember();
        member.id = (memData['id'] as string) || '';
        member.familyId = (memData['familyId'] as string) || '';
        member.userId = (memData['userId'] as string) || '';
        member.name = (memData['name'] as string) || '';
        member.role = (memData['role'] as MemberRole) || MemberRole.DAD;
        member.avatar = (memData['avatar'] as string) || '';
        member.color = (memData['color'] as string) || '#5C5C5C';
        member.birthDate = (memData['birthDate'] as string) || '';
        member.phone = (memData['phone'] as string) || '';
        member.isCustodial = memData['isCustodial'] === 1 || memData['isCustodial'] === true;
        member.fontSizeMode = (memData['fontSizeMode'] as FontSizeMode) || FontSizeMode.NORMAL;
        member.claimToken = '';
        member.status = MemberStatus.ACTIVE;
        member.createdAt = (memData['createdAt'] as string) || '';
        member.updatedAt = (memData['updatedAt'] as string) || '';

        let family: ClaimFamilyInfo | null = null;
        const famData = d['family'] as Record<string, Object> | null;
        if (famData) {
          family = {
            id: (famData['id'] as string) || '',
            name: (famData['name'] as string) || '',
            creatorId: (famData['creatorId'] as string) || '',
            inviteCode: (famData['inviteCode'] as string) || '',
            inviteCodeExpiresAt: (famData['inviteCodeExpiresAt'] as string) || ''
          };
        }

        hilog.info(DOMAIN, TAG, 'claimMemberCloud: success, memberId=%{public}s, familyName=%{public}s',
          member.id, family ? family.name : 'null');
        return { member, family };
      }
      hilog.warn(DOMAIN, TAG, 'claimMemberCloud: code=%{public}d, msg=%{public}s', result.code, result.message ?? '');
      return null;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'claimMemberCloud failed: %{public}s', (err as Error).message);
      return null;
    }
  }

  /**
   * 获取家庭中所有待认领的成员
   */
  getUnclaimedMembers(familyId: string): FamilyMember[] {
    const members = this.db.getMembersByFamilyId(familyId);
    return members.filter(m => m.status === MemberStatus.UNCLAIMED);
  }

  /**
   * 通过角色匹配，在待认领成员中查找
   */
  findUnclaimedByRole(familyId: string, role: MemberRole): FamilyMember | null {
    const unclaimed = this.getUnclaimedMembers(familyId);
    return unclaimed.find(m => m.role === role) ?? null;
  }

  /** 重置状态 */
  resetState(): void {
    this.currentUserId = '';
    this.agcUserId = '';
    this.currentMember = null;
  }

  /**
   * 退出家庭 -- 删除云端 FamilyMember 记录后清空本地数据
   *
   * 关键：必须在 clearAllData 之前推送云端删除，否则：
   * - Cloud DB 中旧 FamilyMember 记录残留
   * - 同账号重新登录时 my-families 查到旧记录 -> 自动恢复进旧家庭
   * - 用户「创建新家庭」变成加回旧家庭
   *
   * 推送失败不阻塞退出（本地数据照清），但下次登录可能被旧记录拉回，
   * 由 restoreFromCloud 的 my-families 结果决定。
   *
   * 同时清空 CloudService 的同步队列：leaveFamily 后本地数据已清空，
   * 但 syncQueue 中可能残留旧家庭的待推送操作（saveMember/saveFamily 的 fire-and-forget）。
   * 若不清空，重新加入家庭时 processQueue 会用新 familyId 推送旧数据，
   * 造成跨家庭污染或 FamilyMember 幽灵记录。
   */
  async leaveFamily(): Promise<void> {
    const family = this.getFamily();
    const member = this.getCurrentMember();
    const familyId = family ? family.id : '';
    const uid = this.getCurrentUserId();

    if (familyId && member && uid) {
      // 先删云端位置行再删 FamilyMember：update-location 的 delete 同样校验成员身份，
      // 若成员记录已删则返回 403，位置行会残留（残留行对他人不可见，仅数据整洁问题）
      try {
        await LocationReporter.getInstance().deleteRemoteRow(familyId);
      } catch (e) { /* 清理失败不影响退出 */ }

      const cloud = CloudService.getInstance();
      if (cloud.isCloudAvailable()) {
        try {
          // 只删除自己的 FamilyMember 记录，不删 Family 记录
          // 创建者退出后家庭仍保留，其他成员可继续使用
          const ops: CloudOperation[] = [
            { type: 'FamilyMember', op: 'delete', data: member as object, version: 1 }
          ];
          const result = await cloud.pushToCloudDb(familyId, ops);
          hilog.info(DOMAIN, TAG,
            'leaveFamily: cloud delete succeeded=%{public}d failed=%{public}d',
            result.succeeded, result.failed);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'leaveFamily: cloud delete failed (non-blocking): %{public}s',
            (err as Error).message);
        }
      }
    }

    // 取消所有本地提醒
    try {
      ReminderService.getInstance().cancelAllReminders();
    } catch (e) { /* 提醒取消失败不影响退出 */ }

    // 清空同步队列：防止旧家庭的待推送操作在新家庭中被 processQueue 误推
    CloudService.getInstance().clearSyncQueue();

    await this.db.clearAllData();
    this.resetState();
    hilog.info(DOMAIN, TAG, 'leaveFamily: local data cleared, state reset');
  }

  // ===== AGC Auth 集成 =====

  /**
   * 用华为账号 openID 关联登录 AGC Auth
   *
   * 流程：
   * 1. 检查 AGC 是否已初始化
   * 2. 尝试用华为账号凭证登录 AGC
   * 3. 如果 AGC 中无对应用户，则匿名登录后关联
   * 4. 存储 AGC UID 到本地备用
   *
   * 注意：此方法不抛出异常，失败时仅降级为本地模式
   */
  private async linkAgcAuth(openID: string, idToken?: string): Promise<void> {
    if (!this.agcConfig || !this.agcConfig.isInitialized()) {
      hilog.info(DOMAIN, TAG, 'AGC not initialized, skip auth linking');
      return;
    }

    // 无 idToken 时降级：用 openID 作为 AGC UID，云函数通过 __uid 兜底识别身份
    if (!idToken) {
      hilog.info(DOMAIN, TAG, 'AGC Auth: no idToken, using openID as uid (fallback mode)');
      this.agcUserId = openID;
      await this.db.saveAgcUserId(this.agcUserId);
      return;
    }

    try {
      // AGC Auth SDK 暂未在当前 SDK 版本的 @kit.CloudFoundationKit 中导出 auth 模块，
      // 使用 openID 作为 AGC UID，云函数通过 __uid 兜底识别用户身份。
      // TODO: 当 auth 模块可用后，替换为:
      //   import { auth } from '@kit.CloudFoundationKit';
      //   const credential = auth.HuaweiIdAuthProvider.credentialWithIdToken(idToken);
      //   const user = await auth.signIn(credential);
      //   this.agcUserId = user.getUid();
      hilog.info(DOMAIN, TAG, 'AGC Auth: using openID as uid (auth module pending SDK support)');
      this.agcUserId = openID;
      await this.db.saveAgcUserId(this.agcUserId);
    } catch (err) {
      // 降级：用 openID 作为 UID，云函数通过 __uid 兜底
      hilog.warn(DOMAIN, TAG, 'AGC Auth sign-in failed, fallback to openID: %{public}s',
        (err as Error).message);
      this.agcUserId = openID;
      await this.db.saveAgcUserId(this.agcUserId);
    }
  }

  /**
   * AGC 匿名登录 - 作为备选方案
   * 当华为账号登录不可用时（debug包），使用匿名账号维持云端同步能力
   *
   * TODO(AGC): 使用 @kit.CloudFoundationKit 的匿名登录 API
   *   const user = await auth.signInAnonymously();
   *   this.agcUserId = user.getUid();
   * 当前生成临时 ID，待 AGC 开通后替换为真实匿名登录
   */
  async agcAnonymousLogin(): Promise<string> {
    if (!this.agcConfig || !this.agcConfig.isInitialized()) {
      return '';
    }

    try {
      const anonId = `agc_anon_${generateId('usr')}`;
      this.agcUserId = anonId;
      await this.db.saveAgcUserId(this.agcUserId);
      hilog.info(DOMAIN, TAG, 'AGC anonymous login (pending real API): %{public}s', anonId);
      return anonId;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'AGC anonymous login failed: %{public}s',
        (err as Error).message);
      return '';
    }
  }

  /**
   * 创建家庭 / 加入家庭 / 认领成员成功后的云端同步
   *
   * 背景（AppGallery 审核驳回"加入家庭后无该家庭信息"）：
   * - saveFamily/saveMember 的云端推送是 fire-and-forget，完成时序无保证，
   *   pull-data 要求云端已存在 membership（FamilyMember.userId=uid），否则 403 静默失败；
   * - 加入后若不主动拉取，需等待 5 分钟节流的后台 syncAll，用户会长时间只看到自己一个人。
   *
   * 处理：先定向 await 推送 Family + FamilyMember 记录建立 membership，再全量拉取该家庭已有数据。
   * 推送/拉取失败不影响本地已完成的加入结果，仅记录日志。
   *
   * 同时推送 Family 和 FamilyMember 的原因：
   * - FamilyMember 用于通过 push-data 的 membership 校验（checkFamilyMembership 查 FamilyMember 表）；
   * - Family 用于让其他家庭成员看到这个家庭（pull-data 查 Family 表）；
   * - 两条 upsert 一起发，命中 push-data 的 isEstablishingRelation 放行逻辑。
   */
  private async syncFamilyAfterJoin(familyId: string, member: FamilyMember): Promise<void> {
    const cloud = CloudService.getInstance();
    hilog.info(DOMAIN, TAG,
      'syncFamilyAfterJoin: CALLED, familyId=%{public}s, cloudAvailable=%{public}s, memberUserId=%{public}s',
      familyId || '(empty)', cloud.isCloudAvailable() ? 'yes' : 'NO',
      member ? member.userId || '(empty)' : '(null)');
    if (!cloud.isCloudAvailable() || !familyId) {
      hilog.warn(DOMAIN, TAG,
        'syncFamilyAfterJoin: SKIPPED, cloudAvailable=%{public}s, familyId=%{public}s',
        cloud.isCloudAvailable() ? 'yes' : 'NO', familyId || '(empty)');
      return;
    }
    try {
      // 诊断：记录 uid 和 member.userId，排查 isEstablishingRelation 的 uid 匹配问题
      const localUid = this.db.getCurrentUserId();
      const agcUid = this.db.getAgcUserId();
      const resolvedUid = agcUid || localUid;
      hilog.info(DOMAIN, TAG,
        'syncFamilyAfterJoin: familyId=%{public}s, member.userId=%{public}s, uid(local=%{public}s, agc=%{public}s, resolved=%{public}s)',
        familyId, member.userId, localUid ? 'yes' : 'no', agcUid ? 'yes' : 'no', resolvedUid ? 'yes' : 'no');

      // 同时推送 Family + FamilyMember，建立云端 membership
      // 推送 Family 的条件：creatorId 非空（有合法创建者）+ updatedAt 非空（完整记录）。
      // - createFamily 的本地 Family 完整（含 createdAt/updatedAt）→ 推送，validate-invite 才能查到
      // - joinFamilyByCode 的本地 Family 是 validate-invite 返回的占位记录（仅
      //   id/name/creatorId/inviteCode/inviteCodeExpiresAt，updatedAt=''）→ 不推送。
      //   否则 upsert 会用占位记录整体覆盖云端完整 Family，清空 createdAt/updatedAt，
      //   污染家庭数据；join 场景云端 Family 已存在，只推 FamilyMember 建立 membership 即可。
      // - claimMemberByToken 的占位 Family creatorId='' → 不推送，安全。
      const ops: CloudOperation[] = [];
      const family = this.db.getFamilies().find(f => f.id === familyId);
      if (family && family.creatorId && family.updatedAt) {
        ops.push({ type: 'Family', op: 'upsert', data: family as object, version: 1 });
      }
      ops.push({ type: 'FamilyMember', op: 'upsert', data: member as object, version: 1 });

      let pushResult = await cloud.pushToCloudDb(familyId, ops);
      if (pushResult.failed > 0) {
        // 推送失败时重试一次：membership 未建立会导致随后的 fullPullAndMerge 因 403 拉空，
        // 用户将看不到家庭已有数据
        hilog.warn(DOMAIN, TAG, 'syncFamilyAfterJoin: membership push failed (code=%{public}d msg=%{public}s failedReasons=%{public}s), retrying once',
          pushResult.code ?? 0, pushResult.message ?? '',
          pushResult.failedReasons ? JSON.stringify(pushResult.failedReasons) : '[]');
        pushResult = await cloud.pushToCloudDb(familyId, ops);
      }

      // 第二次仍失败 -> 第三次降级：只推 FamilyMember（必然命中 isEstablishingRelation）
      // 场景：Family upsert 因 schema/冲突失败拉高 failed 计数，但 FamilyMember 可能已成功。
      // 若 FamilyMember 仍未写入（failed 仍 > 0），单独推一次 FamilyMember 确保membership 建立。
      if (pushResult.failed > 0 && (pushResult.code === 403 || pushResult.code === undefined)) {
        hilog.warn(DOMAIN, TAG,
          'syncFamilyAfterJoin: push still failing after retry (code=%{public}d), trying FamilyMember-only push as fallback',
          pushResult.code ?? 0);
        const memberOnlyOps: CloudOperation[] = [
          { type: 'FamilyMember', op: 'upsert', data: member as object, version: 1 }
        ];
        pushResult = await cloud.pushToCloudDb(familyId, memberOnlyOps);
      }

      hilog.info(DOMAIN, TAG, 'syncFamilyAfterJoin: membership push succeeded=%{public}d failed=%{public}d code=%{public}d',
        pushResult.succeeded, pushResult.failed, pushResult.code ?? 0);
      if (pushResult.failedReasons && pushResult.failedReasons.length > 0) {
        hilog.warn(DOMAIN, TAG, 'syncFamilyAfterJoin: failedReasons=%{public}s',
          JSON.stringify(pushResult.failedReasons));
      }
      const pulled = await cloud.fullPullAndMerge(familyId);
      hilog.info(DOMAIN, TAG, 'syncFamilyAfterJoin: fullPullAndMerge=%{public}s, familyId=%{public}s',
        pulled, familyId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'syncFamilyAfterJoin failed: %{public}s', (err as Error).message);
    }
  }

  /**
   * 从云端拉取 Family 记录，更新本地家庭名等信息
   *
   * 使用场景：认领成功后占位家庭名可能是“我的家庭”，
   * fullPullAndMerge 可能因 updatedAt 比较未覆盖。此方法显式拉取并覆盖。
   */
  private async refreshFamilyNameFromCloud(familyId: string): Promise<void> {
    const cloud = CloudService.getInstance();
    if (!cloud.isCloudAvailable() || !familyId) return;

    try {
      const result = await cloud.pullFromCloudDb(familyId, ['Family']);
      const families = result.snapshots['Family'];
      if (!families || families.length === 0) {
        hilog.info(DOMAIN, TAG, 'refreshFamilyNameFromCloud: no Family in cloud for %{public}s', familyId);
        return;
      }
      const cloudFam = families[0] as Record<string, Object>;
      const cloudName = cloudFam['name'] as string;
      const localFamilies = this.db.getFamilies();
      const localFam = localFamilies.find(f => f.id === familyId);
      if (localFam && cloudName && localFam.name !== cloudName) {
        localFam.name = cloudName;
        localFam.creatorId = cloudFam['creatorId'] as string || localFam.creatorId;
        localFam.inviteCode = cloudFam['inviteCode'] as string || localFam.inviteCode;
        localFam.inviteCodeExpiresAt = cloudFam['inviteCodeExpiresAt'] as string || localFam.inviteCodeExpiresAt;
        localFam.updatedAt = cloudFam['updatedAt'] as string || localFam.updatedAt;
        // 直接写本地存储，不触发 pushToCloud（避免把云端数据又推回去）
        const allFamilies = localFamilies.map(f => f.id === familyId ? localFam : f);
        await this.db.saveList<Family>('families', allFamilies);
        hilog.info(DOMAIN, TAG, 'refreshFamilyNameFromCloud: updated local family name to %{public}s', cloudName);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshFamilyNameFromCloud failed: %{public}s', (err as Error).message);
    }
  }

  // ===== 云端邀请码/认领码验证方法 =====

  /**
   * 通过云函数验证邀请码（本地无匹配时作为降级方案调用）
   *
   * 云函数 validate-invite 查询 Cloud DB 的 Family 表，
   * 返回匹配的家庭数据。此方法不执行加入操作，仅返回验证结果。
   *
   * @returns 验证通过时返回 Family 对象，失败时返回 null
   */
  private async validateInviteCodeCloud(code: string): Promise<Family | null> {
    const cloud = CloudService.getInstance();
    if (!cloud.isCloudAvailable()) {
      hilog.warn(DOMAIN, TAG, 'validateInviteCodeCloud: cloud not available');
      return null;
    }
    try {
      const inviteParams: ValidateInviteParams = {
        inviteCode: code
      };
      const result = await cloud.callCloudFunction('validate-invite', inviteParams);
      if (result.code === 0 && result.data) {
        const d = result.data as Record<string, Object>;
        const valid = d['valid'] as boolean;
        if (valid) {
          const famData = d['family'] as Record<string, Object>;
          const family = new Family();
          family.id = (famData['id'] as string) || '';
          family.name = (famData['name'] as string) || '';
          family.creatorId = (famData['creatorId'] as string) || '';
          family.inviteCode = (famData['inviteCode'] as string) || '';
          family.inviteCodeExpiresAt = (famData['inviteCodeExpiresAt'] as string) || '';
          hilog.info(DOMAIN, TAG, 'validateInviteCodeCloud: valid, familyId=%{public}s', family.id);
          return family;
        }
      }
      hilog.warn(DOMAIN, TAG, 'validateInviteCodeCloud: code=%{public}d, msg=%{public}s',
        result.code, result.message);
      return null;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'validateInviteCodeCloud failed: %{public}s',
        (err as Error).message);
      return null;
    }
  }

  /**
   * 通过云函数验证认领码（本地无匹配时作为降级方案调用）
   *
   * 云函数 validate-claim 查询 Cloud DB 的 FamilyMember 表，
   * 返回匹配的待认领成员数据。此方法不执行认领操作，仅返回验证结果。
   *
   * @returns 验证通过时返回 FamilyMember 对象，失败时返回 null
   */
  private async validateClaimTokenCloud(token: string): Promise<FamilyMember | null> {
    const cloud = CloudService.getInstance();
    if (!cloud.isCloudAvailable()) {
      hilog.warn(DOMAIN, TAG, 'validateClaimTokenCloud: cloud not available');
      return null;
    }
    try {
      const claimParams: ValidateClaimParams = {
        claimToken: token
      };
      const result = await cloud.callCloudFunction('validate-claim', claimParams);
      if (result.code === 0 && result.data) {
        const d = result.data as Record<string, Object>;
        const valid = d['valid'] as boolean;
        if (valid) {
          const memData = d['member'] as Record<string, Object>;
          const member = new FamilyMember();
          member.id = (memData['id'] as string) || '';
          member.familyId = (memData['familyId'] as string) || '';
          member.name = (memData['name'] as string) || '';
          member.role = (memData['role'] as MemberRole) || MemberRole.DAD;
          member.avatar = (memData['avatar'] as string) || '';
          member.color = (memData['color'] as string) || '#5C5C5C';
          member.claimToken = (memData['claimToken'] as string) || '';
          member.status = (memData['status'] as string) || MemberStatus.ACTIVE;
          member.userId = '';
          member.isCustodial = false;
          // 使用云端返回的真实创建时间，保证 7 天过期检查有效且不污染云端数据
          const cloudCreatedAt = memData['createdAt'] as string;
          member.createdAt = cloudCreatedAt ? cloudCreatedAt : new Date().toISOString();
          member.updatedAt = new Date().toISOString();
          // 保存云端返回的家庭名，供 claimMemberByToken 构建占位家庭时使用
          const famData = d['family'] as Record<string, Object> | null;
          this.pendingClaimFamilyName = famData ? (famData['name'] as string) ?? '' : '';
          hilog.info(DOMAIN, TAG, 'validateClaimTokenCloud: valid, memberId=%{public}s', member.id);
          return member;
        }
      }
      hilog.warn(DOMAIN, TAG, 'validateClaimTokenCloud: code=%{public}d, msg=%{public}s',
        result.code, result.message);
      return null;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'validateClaimTokenCloud failed: %{public}s',
        (err as Error).message);
      return null;
    }
  }
}
