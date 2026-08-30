/**
 * 照片互动模型 - 点赞/评论（每条互动独立记录，避免并发覆盖）
 */
import { BaseRecord } from './BaseRecord';

export class PhotoComment extends BaseRecord {
  photoId: string = '';
  isLike: boolean = false;
  content: string = '';
}
