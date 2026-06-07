/**
 * 健康指标模型
 */
import { BaseRecord } from './BaseRecord';

export class HealthMetric extends BaseRecord {
  forMemberId: string = '';
  metricType: string = '';
  value: number = 0;
  unit: string = '';
  measuredAt: string = '';
  isAbnormal: boolean = false;
  note: string = '';
}
