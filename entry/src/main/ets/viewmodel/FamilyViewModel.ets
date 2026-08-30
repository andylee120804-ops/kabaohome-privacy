/**
 * 家庭数据ViewModel
 */
import { LocalDbService } from '../service/LocalDbService';
import { AuthService } from '../service/AuthService';
import { FamilyMember } from '../model/FamilyMember';
import { Family } from '../model/Family';
import { MemberRole, MemberStatus, MEMBER_COLORS } from '../common/Constants';
import { generateSecureCode } from '../common/Utils';

export class FamilyViewModel {
  private db: LocalDbService = LocalDbService.getInstance();
  private auth: AuthService = AuthService.getInstance();

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
      const updated: FamilyMember = { ...member, color, updatedAt: new Date().toISOString() };
      await this.db.updateMember(updated);
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
    const updated: Family = {
      ...family,
      inviteCode: code,
      inviteCodeExpiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
      updatedAt: now
    };
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
      const updated: FamilyMember = {
        ...member,
        claimToken: newToken,
        updatedAt: new Date().toISOString()
      };
      await this.db.updateMember(updated);
      return newToken;
    }
    return '';
  }

  async leaveFamily(): Promise<void> {
    await this.db.clearAllData();
    this.auth.resetState();
  }
}
