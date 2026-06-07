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
}
