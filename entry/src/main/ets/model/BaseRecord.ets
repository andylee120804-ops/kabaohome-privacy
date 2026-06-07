/**
 * 基础记录 - 所有数据模型的基类
 */
import { Visibility } from '../common/Constants';

export class BaseRecord {
  id: string = '';
  familyId: string = '';
  creatorId: string = '';
  visibility: Visibility = Visibility.PRIVATE;
  visibleMembers: string[] = [];
  version: number = 1;
  createdAt: string = '';
  updatedAt: string = '';
  isDeleted?: boolean;
}
