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
  /** 是否上墙展示（家庭相册轮播） */
  isOnWall: boolean = false;
  /** 原始图片宽高（上传时记录，供列表布局占位） */
  width: number = 0;
  height: number = 0;
}
