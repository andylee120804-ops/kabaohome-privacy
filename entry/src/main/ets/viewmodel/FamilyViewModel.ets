/**
 * 家庭数据ViewModel
 */
import { LocalDbService } from '../service/LocalDbService';
import { AuthService } from '../service/AuthService';
import { FamilyMember } from '../model/FamilyMember';
import { Family } from '../model/Family';
import { MemberRole, MemberStatus, MEMBER_COLORS } from '../common/Constants';
import { generateSecureCode } from '../common/Utils';

/** updateMember 时可覆盖的字段（未指定的字段从原成员拷贝） */
interface MemberPatch {
  name?: string;
  role?: MemberRole;
  color?: string;
  claimToken?: string;
}

export class FamilyViewModel {
  private db: LocalDbService = LocalDbService.getInstance();
  private auth: AuthService = AuthService.getInstance();

  /**
   * 复制成员全字段并应用覆盖项，updatedAt 统一刷新为当前时间。
   * FamilyMember 新增字段时只需改这里，避免各处手抄字段列表漏字段。
   */
  private buildUpdatedMember(member: FamilyMember, patch: MemberPatch): FamilyMember {
    const updated = new FamilyMember();
    updated.id = member.id;
    updated.familyId = member.familyId;
    updated.userId = member.userId;
    updated.name = patch.name ?? member.name;
    updated.avatar = member.avatar;
    updated.color = patch.color ?? member.color;
    updated.role = patch.role ?? member.role;
    updated.birthDate = member.birthDate;
    updated.phone = member.phone;
    updated.isCustodial = member.isCustodial;
    updated.fontSizeMode = member.fontSizeMode;
    updated.claimToken = patch.claimToken ?? member.claimToken;
    updated.status = member.status;
    updated.isDeleted = member.isDeleted ?? false;
    updated.createdAt = member.createdAt;
    updated.updatedAt = new Date().toISOString();
    updated.syncStatus = member.syncStatus;
    return updated;
  }

  getCurrentFamily(): Family | null {
    return this.db.getCurrentFamily();
  }

  getFamilyMembers(): FamilyMember[] {
    const family = this.getCurrentFamily();
    if (!family) return [];
    return this.db.getMembersByFamilyId(family.id);
  }

  getCurrentMember(): FamilyMember | null {
    return this.auth.getCurrentMember();
  }

  /** 当前用户是否为家庭创建者 */
  isCreator(): boolean {
    return this.auth.isCreator();
  }

  async addCustodialMember(name: string, role: MemberRole): Promise<FamilyMember> {
    const family = this.getCurrentFamily();
    if (!family) throw new Error('未加入家庭');
    return await this.auth.addCustodialMember(family.id, name, role);
  }

  async addFamilyMember(name: string, role: MemberRole, isCustodial: boolean = false): Promise<FamilyMember> {
    const family = this.getCurrentFamily();
    if (!family) throw new Error('未加入家庭');
    return await this.auth.addFamilyMember(family.id, name, role, isCustodial);
  }

  async removeMember(memberId: string): Promise<void> {
    await this.auth.removeMember(memberId);
  }

  async updateMemberColor(memberId: string, color: string): Promise<void> {
    const family = this.getCurrentFamily();
    if (!family) return;
    const members = this.db.getMembersByFamilyId(family.id);
    const member = members.find(m => m.id === memberId);
    if (member) {
      await this.db.updateMember(this.buildUpdatedMember(member, { color: color }));
    }
  }

  /**
   * 当前用户是否可编辑指定成员的资料（名字/角色）
   *
   * 安全规则：只有本人或家庭创建者可改。
   * - 本人：member.userId 匹配当前账号（可改自己的名字和角色）
   * - 创建者：可改任何成员（管理代管孩子/待认领成员等场景）
   * - 待认领成员 userId 为空，只有创建者可改
   */
  canEditMember(member: FamilyMember): boolean {
    if (this.isCreator()) return true;
    const uid = this.auth.getCurrentUserId();
    return member.userId !== '' && member.userId === uid;
  }

  /**
   * 修改成员名字与角色
   *
   * 权限在服务端之外的本地强制校验（canEditMember），云端 push-data 的
   * membership 检查只要求调用方是家庭成员，同 id 的 FamilyMember upsert
   * 会正常通过（checkDuplicateMember 排除同 id 记录）。
   */
  async updateMemberProfile(memberId: string, name: string, role: MemberRole): Promise<void> {
    const trimmed = name.trim();
    if (!trimmed) throw new Error('名字不能为空');
    const member = this.getFamilyMembers().find(m => m.id === memberId);
    if (!member) throw new Error('成员不存在');
    if (!this.canEditMember(member)) throw new Error('只有本人或家庭创建者可以修改成员信息');

    await this.db.updateMember(this.buildUpdatedMember(member, { name: trimmed, role: role }));

    // 改的是本人 → 刷新 AuthService 内存缓存，其他页面（首页问候等）立即读到新名字
    const uid = this.auth.getCurrentUserId();
    if (member.userId === uid) {
      this.auth.reloadCurrentMember();
    }
  }

  getInviteCode(): string {
    const family = this.getCurrentFamily();
    return family?.inviteCode ?? '';
  }

  async refreshInviteCode(): Promise<string> {
    const family = this.getCurrentFamily();
    if (!family) return '';
    const code = await generateSecureCode();
    const now = new Date().toISOString();
    const updated = new Family();
    updated.id = family.id;
    updated.name = family.name;
    updated.creatorId = family.creatorId;
    updated.inviteCode = code;
    updated.inviteCodeExpiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
    updated.createdAt = family.createdAt;
    updated.updatedAt = now;
    updated.syncStatus = family.syncStatus;
    await this.auth.saveFamily(updated);
    return code;
  }

  getAvailableColors(): string[] {
    const usedColors = this.getFamilyMembers().map(m => m.color);
    return MEMBER_COLORS.filter(c => !usedColors.includes(c));
  }

  /** 获取指定成员的认领令牌（如果该成员处于待认领状态） */
  getMemberClaimToken(memberId: string): string {
    const members = this.getFamilyMembers();
    const member = members.find(m => m.id === memberId);
    return (member && member.status === MemberStatus.UNCLAIMED) ? member.claimToken : '';
  }

  /** 获取所有待认领的成员 */
  getUnclaimedMembers(): FamilyMember[] {
    return this.getFamilyMembers().filter(m => m.status === MemberStatus.UNCLAIMED);
  }

  /** 通过认领令牌认领成员身份 */
  async claimMember(claimToken: string): Promise<FamilyMember | null> {
    return await this.auth.claimMemberByToken(claimToken);
  }

  /** 为指定成员重新生成认领令牌 */
  async refreshClaimToken(memberId: string): Promise<string> {
    const family = this.getCurrentFamily();
    if (!family) return '';
    const members = this.db.getMembersByFamilyId(family.id);
    const member = members.find(m => m.id === memberId);
    if (member && member.status === MemberStatus.UNCLAIMED) {
      const newToken = await generateSecureCode();
      await this.db.updateMember(this.buildUpdatedMember(member, { claimToken: newToken }));
      return newToken;
    }
    return '';
  }

  async leaveFamily(): Promise<void> {
    await this.auth.leaveFamily();
  }
}
