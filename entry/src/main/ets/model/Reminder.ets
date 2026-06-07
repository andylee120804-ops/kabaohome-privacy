/**
 * 提醒事项模型
 */
import { BaseRecord } from './BaseRecord';

export class Reminder extends BaseRecord {
  title: string = '';
  description: string = '';
  reminderType: string = '';
  dueTime: string = '';
  isRecurring: boolean = false;
  recurrenceRule: string = '';
  isCompleted: boolean = false;
  completedAt: string = '';
  reminderSettings: string[] = [];
}
