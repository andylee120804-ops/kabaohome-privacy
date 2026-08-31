/**
 * 姨妈周期记录
 */
import { BaseRecord } from './BaseRecord';
import { PregnancyRisk } from '../common/Constants';

export class PeriodRecord extends BaseRecord {
  startDate: string = '';
  endDate: string = '';
  cycleLength: number = 28;
  duration: number = 5;
  symptoms: string[] = [];
  mood: string = '';
  note: string = '';
}

export class IntimacyRecord extends BaseRecord {
  date: string = '';
  pregnancyRisk: PregnancyRisk = PregnancyRisk.LOW;
  cycleDay: number = 0;
  note: string = '';
}

export interface PeriodReminderSettings {
  remind3DaysBefore: boolean;
  remind1DayBefore: boolean;
  remindOvulation: boolean;
  remindFertile: boolean;
  /** 是否显式记录自己的姨妈（覆盖"无记录自动进入仅查看模式"）。可选：旧 JSON 无此字段视为 false */
  recordSelf?: boolean;
}
