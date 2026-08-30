/**
 * 家庭邀请模型
 */
import { InviteMethod, InviteStatus } from '../common/Constants';

export class FamilyInvitation {
  id: string = '';
  familyId: string = '';
  inviterId: string = '';
  inviteeId: string = '';
  inviteePhone: string = '';
  inviteCode: string = '';
  inviteMethod: InviteMethod = InviteMethod.CODE;
  status: InviteStatus = InviteStatus.PENDING;
  expiresAt: string = '';
  createdAt: string = '';
  respondedAt: string = '';
}
