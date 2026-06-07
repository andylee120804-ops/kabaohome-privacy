/**
 * 孩子事项模型
 */
import { BaseRecord } from './BaseRecord';

export class KidEvent extends BaseRecord {
  forMemberId: string = '';
  title: string = '';
  description: string = '';
  eventType: string = '';
  eventTime: string = '';
  location: string = '';
  isRecurring: boolean = false;
  recurrenceRule: string = '';
  reminderSettings: string[] = [];
  isSharedWith: string[] = [];
  isCompleted: boolean = false;
  completedAt: string = '';
}

/**
 * 成长记录
 */
export class GrowthRecord extends BaseRecord {
  forMemberId: string = '';
  height: number = 0;
  weight: number = 0;
  headCircumference: number = 0;
  milestone: string = '';
  recordDate: string = '';
  photoUrl: string = '';
  note: string = '';
}
