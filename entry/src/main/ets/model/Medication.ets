/**
 * 用药提醒模型
 */
import { BaseRecord } from './BaseRecord';

export class Medication extends BaseRecord {
  forMemberId: string = '';
  medicineName: string = '';
  dosage: string = '';
  frequency: string = '';
  timeSlots: string[] = [];
  startDate: string = '';
  endDate: string = '';
  isActive: boolean = true;
  note: string = '';
}

/**
 * 服药记录
 */
export class MedicationLog extends BaseRecord {
  medicationId: string = '';
  timeSlot: string = '';
  /** 实际服药的家庭成员ID（非userId），默认取Medication.forMemberId */
  takenBy: string = '';
  takenAt: string = '';
  /** 'taken' | 'late' | 'skipped' */
  status: string = '';
  note: string = '';
}
