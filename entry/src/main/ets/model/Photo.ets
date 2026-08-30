/**
 * 家庭相册模型
 */
import { BaseRecord } from './BaseRecord';

export class Photo extends BaseRecord {
  url: string = '';
  thumbnailUrl: string = '';
  description: string = '';
  eventTag: string = '';
  takenAt: string = '';
}
