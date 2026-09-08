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
  color: string = '#5C5C5C';
  role: MemberRole = MemberRole.DAD;
  birthDate: string = '';
  phone: string = '';
  isCustodial: boolean = false;
  fontSizeMode: FontSizeMode = FontSizeMode.NORMAL;
  /** 认领令牌：非代管成员由家人添加后，凭此令牌认领身份 */
  claimToken: string = '';
  /** 成员状态：ACTIVE=已激活, UNCLAIMED=待认领 */
  status: string = MemberStatus.ACTIVE;
  /** 本地软删标记（退出/移除家庭用；云端 schema 无此字段，上传时由白名单过滤） */
  isDeleted: boolean = false;
  createdAt: string = '';
  updatedAt: string = '';
  syncStatus?: string;
}
