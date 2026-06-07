/**
 * 家庭成员模型
 */
import { MemberRole, FontSizeMode, MemberStatus } from '../common/Constants';

export class FamilyMember {
  id: string = '';
  familyId: string = '';
  userId: string = '';
  name: string = '';
  avatar: string = '';
  color: string = '#1565C0';
  role: MemberRole = MemberRole.DAD;
  birthDate: string = '';
  phone: string = '';
  isCustodial: boolean = false;
  fontSizeMode: FontSizeMode = FontSizeMode.NORMAL;
  /** 认领令牌：非代管成员由家人添加后，凭此令牌认领身份 */
  claimToken: string = '';
  /** 成员状态：ACTIVE=已激活, UNCLAIMED=待认领 */
  status: string = MemberStatus.ACTIVE;
  createdAt: string = '';
  updatedAt: string = '';
  syncStatus?: string;
}
