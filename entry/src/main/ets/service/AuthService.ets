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
import { FamilyMember } from '../model/FamilyMember';
import { Family } from '../model/Family';
import { MemberRole, MemberStatus, MEMBER_COLORS, ModuleId } from '../common/Constants';
import { generateId, generateSecureCode } from '../common/Utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const TAG = '[AuthService]';
const DOMAIN = 0x0000;

/** 华为账号登录函数签名（由外部 Provider 文件注入） */
export type HuaweiLoginFn = (context: common.Context | null) => Promise<string>;

export class AuthService {
  private static instance: AuthService | null = null;
  private db: LocalDbService = LocalDbService.getInstance();
  private currentUserId: string = '';
  private agcUserId: string = ''; // AGC Auth UID，用于云端操作
  private currentMember: FamilyMember | null = null;
  private uiContext: common.Context | null = null;
  private agcConfig: AgcConfig | null = null;

  private huaweiLoginImpl: HuaweiLoginFn | null = null;
  private huaweiSilentLoginImpl: HuaweiLoginFn | null = null;

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

  /** 获取当前用户在当前家庭中的成员记录 */
  getCurrentMember(): FamilyMember | null {
    if (this.currentMember) return this.currentMember;
    const userId = this.getCurrentUserId();
    if (!userId) return null;
    const family = this.db.getCurrentFamily();
    if (!family) return null;
    // 在当前家庭范围内查找当前用户的成员记录
    const members = this.db.getMembersByFamilyId(family.id);
    this.currentMember = members.find(m => m.userId === userId) ?? null;
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
    await this.db.saveCurrentUserId(userId);
    hilog.info(0x0000, TAG, 'Offline login: %{public}s', userId);
    return userId;
  }

  // ===== 华为账号登录（Provider 代理模式） =====

  async silentLogin(): Promise<string> {
    if (!this.huaweiSilentLoginImpl) {
      return '';
    }
    try {
      const openID = await this.huaweiSilentLoginImpl(this.uiContext);
      if (openID) {
        this.currentUserId = openID;
        await this.db.saveCurrentUserId(this.currentUserId);
        // 关联 AGC Auth：用华为账号 openID 登录 AGC
        await this.linkAgcAuth(openID);
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
    const openID = await this.huaweiLoginImpl(this.uiContext);
    this.currentUserId = openID;
    await this.db.saveCurrentUserId(this.currentUserId);
    // 关联 AGC Auth：用华为账号 openID 登录 AGC
    await this.linkAgcAuth(openID);
    hilog.info(0x0000, TAG, 'Huawei login success: %{public}s', openID);
    return openID;
  }

  /** 当前用户是否为华为账号登录（非离线账号） */
  isHuaweiAccount(): boolean {
    return this.currentUserId !== '' && !this.currentUserId.startsWith('offline_');
  }

  async logout(): Promise<void> {
    this.currentUserId = '';
    this.currentMember = null;
    await this.db.saveCurrentUserId('');
    hilog.info(0x0000, TAG, 'Logged out');
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
    await this.db.removeMember(memberId);
  }

  getMembers(): FamilyMember[] {
    return this.db.getMembers();
  }

  isCreator(): boolean {
    const member = this.getCurrentMember();
    const family = this.getFamily();
    return member !== null && family !== null && family.creatorId === member.userId;
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
    member.createdAt = now;
    member.updatedAt = now;

    await this.db.saveFamily(family);
    await this.db.saveMember(member);
    await this.db.saveHasFamily(true);
    // 初始化默认模块：姨妈、家庭提醒、家庭记账
    await this.db.saveEnabledModules([ModuleId.PERIOD, ModuleId.REMINDER, ModuleId.ACCOUNTING]);

    this.currentMember = member;
    return family;
  }

  /** 通过邀请码加入家庭 */
  async joinFamilyByCode(code: string, memberName: string, role: MemberRole): Promise<Family | null> {
    const userId = this.getCurrentUserId();
    if (!userId) {
      throw new Error('未登录');
    }
    const families = this.db.getFamilies();
    const family = families.find(f => f.inviteCode === code);
    if (!family) return null;
    if (family.inviteCodeExpiresAt && new Date(family.inviteCodeExpiresAt) < new Date()) return null;

    const now = new Date().toISOString();

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
    member.status = MemberStatus.ACTIVE;
    member.createdAt = now;
    member.updatedAt = now;

    await this.db.saveMember(member);
    await this.db.saveHasFamily(true);

    this.currentMember = member;
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

    const members = this.db.getMembers();
    const member = members.find(m => m.claimToken === claimToken && m.status === MemberStatus.UNCLAIMED);
    if (!member) return null;

    // 检查claimToken是否过期（7天有效）
    const createdAt = new Date(member.createdAt);
    if (Date.now() - createdAt.getTime() > 7 * 24 * 60 * 60 * 1000) {
      hilog.warn(0x0000, TAG, 'Claim token expired for member: %{public}s', member.id);
      return null;
    }

    member.userId = userId;
    member.status = MemberStatus.ACTIVE;
    member.claimToken = ''; // 清除令牌，防止重复使用
    member.updatedAt = new Date().toISOString();

    await this.db.updateMember(member);
    await this.db.saveHasFamily(true);

    this.currentMember = member;
    hilog.info(0x0000, TAG, 'Member claimed: %{public}s -> %{public}s', member.id, userId);
    return member;
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
  private async linkAgcAuth(openID: string): Promise<void> {
    if (!this.agcConfig || !this.agcConfig.isInitialized()) {
      hilog.info(DOMAIN, TAG, 'AGC not initialized, skip auth linking');
      return;
    }

    try {
      // TODO(AGC): 使用 @kit.CloudFoundationKit 的华为账号凭证登录
      // 完整实现时机：AGC 控制台开通认证服务后
      //
      // 参考实现（需 AGC Auth SDK 版本确认后启用）：
      //   const credential = auth.HuaweiIdAuthProvider.credentialWithIdToken(idToken);
      //   const user = await auth.signIn(credential);
      //   this.agcUserId = user.getUid();
      //
      // 当前阶段：因为需要华为账号 ID Token（非 openID），
      // 而 @kit.AccountKit 的 HuaweiIDProvider 仅返回 openID，
      // 需要在 HuaweiAccountProvider 中额外请求 ID Token 才能完成关联。
      // 先用 openID 作为临时 AGC UID，待 Token 获取完善后替换。
      hilog.info(DOMAIN, TAG, 'AGC Auth linked for openID: %{public}s (pending ID Token)', openID);
      this.agcUserId = `pending_${openID}`;
      await this.db.saveAgcUserId(this.agcUserId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'AGC Auth link failed (local mode): %{public}s',
        (err as Error).message);
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
}
