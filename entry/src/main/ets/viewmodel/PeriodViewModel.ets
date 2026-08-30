/**
 * 姨妈周期ViewModel - 包含周期计算和排卵预测逻辑
 */
import { LocalDbService } from '../service/LocalDbService';
import { PeriodRecord, IntimacyRecord } from '../model/PeriodRecord';
import { PregnancyRisk, Visibility } from '../common/Constants';
import { formatDate, daysBetween, generateId } from '../common/Utils';
import { MarkedDate } from '../components/CalendarView';
import { Reminder } from '../model/Reminder';

const MIN_VALID_CYCLE_LENGTH = 21;
const MAX_VALID_CYCLE_LENGTH = 45;
const NORMAL_CYCLE_MAX_LENGTH = 35;
const TREND_BAR_FULL_WIDTH_CYCLE_LENGTH = 35;
const ADAPTIVE_CYCLE_LIMIT = 6;
const MIN_ADAPTIVE_CYCLE_COUNT = 3;

export interface AdaptivePeriodPrediction {
  predictedCycleLength: number;
  nextPeriodDate: string;
  earliestPeriodDate: string;
  latestPeriodDate: string;
  confidenceDays: number;
  validCycleCount: number;
  isAdaptive: boolean;
}

export interface CycleTrendRow {
  startDate: string;
  displayDate: string;
  cycleLength: number;
  cycleLabel: string;
  punctualityLabel: string;
  isCurrentCycle: boolean;
  isNormalRange: boolean;
  barWidthPercent: number;
}

export function calculateCycleTrendRows(records: PeriodRecord[], limit: number = 12): CycleTrendRow[] {
  const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate)).slice(0, limit);
  const rows: CycleTrendRow[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const current = sorted[i];
    const next = i > 0 ? sorted[i - 1] : null;
    const cycleLength = next ? daysBetween(new Date(current.startDate), new Date(next.startDate)) : 0;
    const isCurrentCycle = i === 0;
    const barWidthPercent = cycleLength > 0 ? Math.max(42, Math.min(100, Math.round(cycleLength / TREND_BAR_FULL_WIDTH_CYCLE_LENGTH * 100))) : 22;
    rows.push({
      startDate: current.startDate,
      displayDate: formatMonthDay(current.startDate),
      cycleLength,
      cycleLabel: isCurrentCycle ? '本周期' : `${cycleLength}天`,
      punctualityLabel: isCurrentCycle ? '' : getPunctualityLabel(current.cycleLength || 28, cycleLength),
      isCurrentCycle,
      isNormalRange: cycleLength >= MIN_VALID_CYCLE_LENGTH && cycleLength <= NORMAL_CYCLE_MAX_LENGTH,
      barWidthPercent
    });
  }
  return rows;
}

function getPunctualityLabel(expectedCycleLength: number, actualCycleLength: number): string {
  const diff = actualCycleLength - expectedCycleLength;
  if (diff === 0) return '准时';
  if (diff > 0) return `推迟${diff}天`;
  return `提前${Math.abs(diff)}天`;
}

function formatMonthDay(dateStr: string): string {
  const parts = dateStr.split('-');
  return `${Number(parts[1])}月${Number(parts[2])}日`;
}

export function calculateAdaptivePeriodPrediction(records: PeriodRecord[]): AdaptivePeriodPrediction {
  const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
  if (sorted.length === 0) {
    return {
      predictedCycleLength: 28,
      nextPeriodDate: '',
      earliestPeriodDate: '',
      latestPeriodDate: '',
      confidenceDays: 0,
      validCycleCount: 0,
      isAdaptive: false
    };
  }

  const latest = sorted[0];
  const cycleLengths: number[] = [];
  for (let i = 0; i < sorted.length - 1 && cycleLengths.length < ADAPTIVE_CYCLE_LIMIT; i++) {
    const currentStart = new Date(sorted[i].startDate);
    const previousStart = new Date(sorted[i + 1].startDate);
    const gap = daysBetween(previousStart, currentStart);
    if (gap >= MIN_VALID_CYCLE_LENGTH && gap <= MAX_VALID_CYCLE_LENGTH) {
      cycleLengths.push(gap);
    }
  }

  let predictedCycleLength = latest.cycleLength || 28;
  let isAdaptive = false;
  if (cycleLengths.length >= MIN_ADAPTIVE_CYCLE_COUNT) {
    let weightedTotal = 0;
    let weightTotal = 0;
    cycleLengths.forEach((cycleLength, index) => {
      const weight = ADAPTIVE_CYCLE_LIMIT - index;
      weightedTotal += cycleLength * weight;
      weightTotal += weight;
    });
    predictedCycleLength = Math.round(weightedTotal / weightTotal);
    isAdaptive = true;
  }

  const confidenceDays = isAdaptive ? calculateConfidenceDays(cycleLengths) : 3;
  const nextPeriodDate = addDays(latest.startDate, predictedCycleLength);
  return {
    predictedCycleLength,
    nextPeriodDate,
    earliestPeriodDate: addDays(nextPeriodDate, -confidenceDays),
    latestPeriodDate: addDays(nextPeriodDate, confidenceDays),
    confidenceDays,
    validCycleCount: cycleLengths.length,
    isAdaptive
  };
}

function calculateConfidenceDays(cycleLengths: number[]): number {
  if (cycleLengths.length < MIN_ADAPTIVE_CYCLE_COUNT) return 3;
  const average = cycleLengths.reduce((sum, value) => sum + value, 0) / cycleLengths.length;
  const variance = cycleLengths.reduce((sum, value) => sum + Math.pow(value - average, 2), 0) / cycleLengths.length;
  return Math.max(1, Math.min(5, Math.round(Math.sqrt(variance))));
}

function addDays(dateStr: string, days: number): string {
  const parts = dateStr.split('-');
  const year = Number(parts[0]);
  const month = Number(parts[1]);
  const day = Number(parts[2]);
  const date = new Date(year, month - 1, day);
  date.setDate(date.getDate() + days);
  return formatDate(date);
}

export class PeriodViewModel {
  private db: LocalDbService = LocalDbService.getInstance();

  getRecords(): PeriodRecord[] {
    return this.db.getPeriodRecords();
  }

  getIntimacyRecords(): IntimacyRecord[] {
    return this.db.getIntimacyRecords();
  }

  getCycleTrendRows(): CycleTrendRow[] {
    return calculateCycleTrendRows(this.getRecords());
  }

  async savePeriodRecord(startDate: string, duration: number, cycleLength: number,
    symptoms: string[] = [], mood: string = '', note: string = ''): Promise<PeriodRecord> {
    // 新记录时 endDate 暂等于 startDate，表示经期尚未结束
    // 用户点"记录结束"时会更新 endDate 和实际 duration
    const now = new Date().toISOString();
    const userId = this.db.getCurrentUserId();
    const family = this.db.getCurrentFamily();

    const record: PeriodRecord = {
      id: generateId('pr'),
      familyId: family?.id ?? '',
      creatorId: userId,
      visibility: Visibility.PRIVATE,
      visibleMembers: [],
      version: 1,
      createdAt: now,
      updatedAt: now,
      startDate,
      endDate: '', // 空字符串表示经期尚未结束
      cycleLength,
      duration,
      symptoms,
      mood,
      note
    };
    await this.db.savePeriodRecord(record);
    return record;
  }

  async saveIntimacyRecord(date: string, note: string): Promise<IntimacyRecord> {
    const cycleDay = this.getCycleDay(date);
    const risk = this.calculatePregnancyRisk(cycleDay);
    const now = new Date().toISOString();
    const userId = this.db.getCurrentUserId();
    const family = this.db.getCurrentFamily();

    const record: IntimacyRecord = {
      id: generateId('ir'),
      familyId: family?.id ?? '',
      creatorId: userId,
      visibility: Visibility.PRIVATE,
      visibleMembers: [],
      version: 1,
      createdAt: now,
      updatedAt: now,
      date,
      pregnancyRisk: risk,
      cycleDay,
      note
    };
    await this.db.saveIntimacyRecord(record);
    return record;
  }

  /**
   * 记录经期结束日期 — 更新最近一条经期记录的 endDate 和 duration，
   * 同时根据与上次经期的间隔更新 cycleLength，精准修正周期和排卵预测
   */
  async endPeriod(endDate: string): Promise<PeriodRecord | null> {
    const records = this.getRecords();
    if (records.length === 0) return null;

    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];

    // 计算实际持续天数
    const start = new Date(latest.startDate);
    const end = new Date(endDate);
    const actualDuration = daysBetween(start, end) + 1;
    if (actualDuration < 1) return null;

    // 计算实际周期长度（如果有上一次经期记录）
    let actualCycleLength = latest.cycleLength;
    if (sorted.length >= 2) {
      const prev = sorted[1];
      const prevStart = new Date(prev.startDate);
      const gap = daysBetween(prevStart, start);
      if (gap > 0 && gap < 60) {
        actualCycleLength = gap;
      }
    }

    const now = new Date().toISOString();
    const updatedRecord: PeriodRecord = {
      id: latest.id,
      familyId: latest.familyId,
      creatorId: latest.creatorId,
      visibility: latest.visibility,
      visibleMembers: latest.visibleMembers,
      version: latest.version + 1,
      createdAt: latest.createdAt,
      updatedAt: now,
      startDate: latest.startDate,
      endDate: endDate,
      cycleLength: actualCycleLength,
      duration: actualDuration,
      symptoms: latest.symptoms,
      mood: latest.mood,
      note: latest.note
    };
    await this.db.updatePeriodRecord(updatedRecord);
    return updatedRecord;
  }

  /**
   * 判断当前是否处于经期中（最近一条经期记录尚未标记结束）
   */
  isPeriodInProgress(): boolean {
    const records = this.getRecords();
    if (records.length === 0) return false;
    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];
    // 没有 endDate 或 endDate 为空字符串表示经期尚未结束
    if (!latest.endDate || latest.endDate === '') return true;
    return false;
  }

  /**
   * 获取当前周期状态
   */
  getCurrentCycleStatus(): CycleStatus {
    const records = this.getRecords();
    if (records.length === 0) {
      return { currentDay: 0, cycleLength: 28, duration: 5, phase: 'unknown', nextPeriodDate: '' };
    }

    // 按 startDate 降序排序，确保取到最近一次周期记录
    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];
    const startDate = new Date(latest.startDate);
    const today = new Date();
    const currentDay = daysBetween(startDate, today) + 1;
    const prediction = calculateAdaptivePeriodPrediction(sorted);
    const cycleLength = prediction.predictedCycleLength;

    const duration = this.calculateAdaptiveDuration(sorted);
    const phase = this.getPhase(currentDay, cycleLength, duration);

    return {
      currentDay,
      cycleLength,
      duration,
      phase,
      nextPeriodDate: prediction.nextPeriodDate,
      earliestPeriodDate: prediction.earliestPeriodDate,
      latestPeriodDate: prediction.latestPeriodDate,
      confidenceDays: prediction.confidenceDays,
      validCycleCount: prediction.validCycleCount,
      isAdaptive: prediction.isAdaptive
    };
  }

  /**
   * 计算月历上的标记日期
   * 支持同一天显示多个 emoji（姨妈开始 🩸、姨妈结束 🌸、啪啪 💗）
   */
  getCalendarMarks(year: number, month: number): MarkedDate[] {
    const marks: MarkedDate[] = [];
    const records = this.getRecords();
    const intimacyRecords = this.getIntimacyRecords();

    if (records.length === 0) return marks;

    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];
    const prediction = calculateAdaptivePeriodPrediction(sorted);
    const cycleLength = prediction.predictedCycleLength;
    const duration = this.calculateAdaptiveDuration(sorted);
    const startDate = new Date(latest.startDate);

    // 构建经期结束日期集合（从所有已结束的记录中收集实际结束日期）
    const periodEndDates = new Set<string>();
    for (const record of records) {
      if (record.endDate && record.endDate !== '') {
        periodEndDates.add(record.endDate);
      }
    }

    const daysInMonth = new Date(year, month, 0).getDate();

    for (let d = 1; d <= daysInMonth; d++) {
      const dateStr = `${year}-${month.toString().padStart(2, '0')}-${d.toString().padStart(2, '0')}`;
      const date = new Date(year, month - 1, d);
      const dayDiff = daysBetween(startDate, date) + 1;

      // 计算该日期所在的周期天数（可能跨多个周期）
      let cycleDay: number;
      if (dayDiff > 0) {
        cycleDay = ((dayDiff - 1) % cycleLength) + 1;
      } else {
        const absDiff = Math.abs(dayDiff) + 1;
        const offsetInCycle = ((absDiff - 1) % cycleLength);
        cycleDay = cycleLength - offsetInCycle;
        if (cycleDay > cycleLength) cycleDay -= cycleLength;
        if (cycleDay <= 0) cycleDay += cycleLength;
      }

      // 经期标记 — 实心圆 + 周期天数标签 + 起始/结束 emoji
      if (cycleDay >= 1 && cycleDay <= duration) {
        const isStart = (cycleDay === 1);
        const icons: string[] = [];
        if (isStart) {
          icons.push('🩸'); // 姨妈开始
        }
        if (periodEndDates.has(dateStr)) {
          icons.push('🌸'); // 姨妈结束
        }
        marks.push({
          date: dateStr,
          color: '#E91E63',
          icons: icons.length > 0 ? icons : undefined,
          label: `${cycleDay}`,
          isPeriodStart: isStart
        });
        // 不 continue，让后面的啪啪记录也能添加到同一天
      } else {
        // 非经期日期的周期阶段标记
        const ovulationDay = cycleLength - 14;
        if (cycleDay >= ovulationDay - 5 && cycleDay <= ovulationDay + 1) {
          if (cycleDay === ovulationDay) {
            marks.push({ date: dateStr, color: '#FFD600', icons: ['⭐'] });
          } else {
            marks.push({ date: dateStr, color: '#FF9800' });
          }
        } else if (cycleDay > duration && cycleDay < ovulationDay - 5) {
          marks.push({ date: dateStr, color: '#4CAF50' });
        } else if (cycleDay > ovulationDay + 1) {
          marks.push({ date: dateStr, color: '#4CAF50' });
        }
      }
    }

    // 啪啪记录标记 — 支持与经期 emoji 共存
    for (const ir of intimacyRecords) {
      const irDate = ir.date;
      if (irDate.startsWith(`${year}-${month.toString().padStart(2, '0')}`)) {
        const existingIndex = marks.findIndex(m => m.date === irDate);
        if (existingIndex === -1) {
          marks.push({ date: irDate, color: '#F48FB1', icons: ['💗'] });
        } else {
          const m: MarkedDate = marks[existingIndex];
          if (!m.icons) {
            m.icons = [];
          }
          if (!m.icons.includes('💗')) {
            m.icons.push('💗');
          }
          marks[existingIndex] = m;
        }
      }
    }

    return marks;
  }

  private calculateAdaptiveDuration(records: PeriodRecord[]): number {
    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const durations = sorted
      .filter(record => record.duration >= 1 && record.duration <= 10)
      .slice(0, ADAPTIVE_CYCLE_LIMIT)
      .map(record => record.duration);
    if (durations.length < MIN_ADAPTIVE_CYCLE_COUNT) {
      return sorted[0].duration || 5;
    }
    let weightedTotal = 0;
    let weightTotal = 0;
    durations.forEach((duration, index) => {
      const weight = ADAPTIVE_CYCLE_LIMIT - index;
      weightedTotal += duration * weight;
      weightTotal += weight;
    });
    return Math.round(weightedTotal / weightTotal);
  }

  private getPhase(currentDay: number, cycleLength: number, duration: number): string {
    if (currentDay <= duration) return 'menstrual';
    const ovulationDay = cycleLength - 14;
    if (currentDay >= ovulationDay - 5 && currentDay <= ovulationDay + 1) {
      return currentDay === ovulationDay ? 'ovulation' : 'fertile';
    }
    if (currentDay > duration && currentDay < ovulationDay - 5) return 'safe_before';
    if (currentDay > ovulationDay + 1) return 'safe_after';
    return 'unknown';
  }

  private getCycleDay(dateStr: string): number {
    const records = this.getRecords();
    if (records.length === 0) return 0;
    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];
    const startDate = new Date(latest.startDate);
    const targetDate = new Date(dateStr);
    const diff = daysBetween(startDate, targetDate) + 1;
    const cycleLength = calculateAdaptivePeriodPrediction(sorted).predictedCycleLength;
    if (diff > 0) {
      return ((diff - 1) % cycleLength) + 1;
    }
    const absDiff = Math.abs(diff) + 1;
    const offsetInCycle = ((absDiff - 1) % cycleLength);
    let cycleDay = cycleLength - offsetInCycle;
    if (cycleDay <= 0) cycleDay += cycleLength;
    return cycleDay;
  }

  private calculatePregnancyRisk(cycleDay: number): PregnancyRisk {
    const records = this.getRecords();
    if (records.length === 0) return PregnancyRisk.LOW;
    const cycleLength = calculateAdaptivePeriodPrediction(records).predictedCycleLength;
    const ovulationDay = cycleLength - 14;

    if (cycleDay >= ovulationDay - 5 && cycleDay <= ovulationDay + 1) {
      return PregnancyRisk.HIGH;
    }
    if (cycleDay >= ovulationDay - 7 && cycleDay <= ovulationDay + 3) {
      return PregnancyRisk.MEDIUM;
    }
    return PregnancyRisk.LOW;
  }

  /**
   * 同步周期提醒到 Reminder 记录表
   * 根据 PeriodReminderSettings 和当前周期数据，自动创建/删除周期相关的 Reminder
   * Reminder 记录将自动出现在首页待办列表，并可通过 ReminderService 发布系统通知
   * （CloudService v2 上线后，这些 Reminder 记录会自动同步到华为云）
   */
  async syncPeriodReminders(): Promise<void> {
    const settings = this.db.getPeriodReminderSettings();
    const cycleStatus = this.getCurrentCycleStatus();
    const records = this.getRecords();

    const now = new Date().toISOString();
    const userId = this.db.getCurrentUserId();
    const family = this.db.getCurrentFamily();
    const familyId = family?.id ?? '';

    // 删除所有当前用户已有的周期提醒（按 reminderType === 'period' 筛选）
    const existingReminders = this.db.getReminders()
      .filter(r => r.reminderType === 'period' && r.creatorId === userId);
    for (const r of existingReminders) {
      await this.db.deleteReminder(r.id);
    }

    // 没有周期记录或没有有效预测日期时，不创建提醒
    if (cycleStatus.currentDay <= 0 || !cycleStatus.nextPeriodDate) return;

    const nextPeriodDate = new Date(cycleStatus.nextPeriodDate);
    const ovulationDay = cycleStatus.cycleLength - 14;

    // 经期前3天提醒
    if (settings.remind3DaysBefore) {
      const threeDaysBefore = new Date(nextPeriodDate);
      threeDaysBefore.setDate(threeDaysBefore.getDate() - 3);
      await this.db.saveReminder({
        id: generateId('per'),
        familyId, creatorId: userId,
        visibility: Visibility.PRIVATE, visibleMembers: [],
        version: 1, createdAt: now, updatedAt: now,
        title: '🌸 经期前3天提醒',
        description: `预计 ${formatDate(nextPeriodDate)} 来姨妈，提前做好准备哦`,
        reminderType: 'period',
        dueTime: `${formatDate(threeDaysBefore)}T09:00:00`,
        isRecurring: false, recurrenceRule: '',
        isCompleted: false, completedAt: '', reminderSettings: []
      });
    }

    // 经期前1天提醒
    if (settings.remind1DayBefore) {
      const oneDayBefore = new Date(nextPeriodDate);
      oneDayBefore.setDate(oneDayBefore.getDate() - 1);
      await this.db.saveReminder({
        id: generateId('per'),
        familyId, creatorId: userId,
        visibility: Visibility.PRIVATE, visibleMembers: [],
        version: 1, createdAt: now, updatedAt: now,
        title: '🌸 经期前1天提醒',
        description: `预计明天 ${formatDate(nextPeriodDate)} 来姨妈，注意休息`,
        reminderType: 'period',
        dueTime: `${formatDate(oneDayBefore)}T09:00:00`,
        isRecurring: false, recurrenceRule: '',
        isCompleted: false, completedAt: '', reminderSettings: []
      });
    }

    // 排卵日提醒
    if (settings.remindOvulation) {
      const ovulationDate = new Date(nextPeriodDate);
      ovulationDate.setDate(ovulationDate.getDate() - 14);
      // 只有未来的排卵日才提醒
      if (ovulationDate > new Date()) {
        await this.db.saveReminder({
          id: generateId('per'),
          familyId, creatorId: userId,
          visibility: Visibility.PRIVATE, visibleMembers: [],
          version: 1, createdAt: now, updatedAt: now,
          title: '⭐ 排卵日提醒',
          description: `今天是排卵日，${this.getPregnancyRiskAdvice(cycleStatus)}`,
          reminderType: 'period',
          dueTime: `${formatDate(ovulationDate)}T09:00:00`,
          isRecurring: false, recurrenceRule: '',
          isCompleted: false, completedAt: '', reminderSettings: []
        });
      }
    }

    // 易孕期提醒
    if (settings.remindFertile) {
      const fertileStart = new Date(nextPeriodDate);
      fertileStart.setDate(fertileStart.getDate() - 19); // 排卵日前5天
      // 只有未来的易孕期开始日才提醒
      if (fertileStart > new Date()) {
        await this.db.saveReminder({
          id: generateId('per'),
          familyId, creatorId: userId,
          visibility: Visibility.PRIVATE, visibleMembers: [],
          version: 1, createdAt: now, updatedAt: now,
          title: '🔶 易孕期提醒',
          description: `易孕窗口已开启，持续至 ${formatDate(new Date(nextPeriodDate.getTime() - 13 * 86400000))}`,
          reminderType: 'period',
          dueTime: `${formatDate(fertileStart)}T09:00:00`,
          isRecurring: false, recurrenceRule: '',
          isCompleted: false, completedAt: '', reminderSettings: []
        });
      }
    }
  }

  /** 获取排卵相关建议文案 */
  private getPregnancyRiskAdvice(status: CycleStatus): string {
    return '怀孕几率较高，备孕可重点关注';
  }

}

export interface CycleStatus {
  currentDay: number;
  cycleLength: number;
  duration: number;
  phase: string; // 'menstrual' | 'fertile' | 'ovulation' | 'safe_before' | 'safe_after' | 'unknown'
  nextPeriodDate: string;
  earliestPeriodDate?: string;
  latestPeriodDate?: string;
  confidenceDays?: number;
  validCycleCount?: number;
  isAdaptive?: boolean;
}
