/**
 * 姨妈周期ViewModel - 包含周期计算和排卵预测逻辑
 */
import { LocalDbService } from '../service/LocalDbService';
import { PeriodRecord, IntimacyRecord, PeriodReminderSettings } from '../model/PeriodRecord';
import { BaseRecord } from '../model/BaseRecord';
import { PregnancyRisk, Visibility, PERIOD_MARK_COLORS, ModuleId } from '../common/Constants';
import { formatDate, daysBetween, generateId, addDaysToDateStr, daysBetweenDateStrings, toDateAtLocalMidnight } from '../common/Utils';
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

/** 周期自动提醒的期望状态（dueTime 为空表示该开关已关闭，记录应隐藏且不通知） */
export interface PeriodReminderSpec {
  id: string;
  title: string;
  description: string;
  dueTime: string;
}

export function calculateCycleTrendRows(records: PeriodRecord[], limit: number = 12): CycleTrendRow[] {
  const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate)).slice(0, limit);
  const rows: CycleTrendRow[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const current = sorted[i];
    const next = i > 0 ? sorted[i - 1] : null;
    const cycleLength = next ? daysBetweenDateStrings(current.startDate, next.startDate) : 0;
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
    const gap = daysBetweenDateStrings(sorted[i + 1].startDate, sorted[i].startDate);
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
  return addDaysToDateStr(dateStr, days);
}

export class PeriodViewModel {
  private db: LocalDbService = LocalDbService.getInstance();
  /** 正在执行的同步任务，用于合并并发调用 */
  private syncInFlight: Promise<void> | null = null;

  getRecords(): PeriodRecord[] {
    return this.db.getPeriodRecords();
  }

  getIntimacyRecords(): IntimacyRecord[] {
    return this.db.getIntimacyRecords();
  }

  getCycleTrendRows(subjectId?: string): CycleTrendRow[] {
    return calculateCycleTrendRows(this.getRecordsBySubject(subjectId || this.getSelfSubjectId()));
  }

  /**
   * 当前用户作为记录归属主体（经期/啪啪记录的「是谁的周期」）
   * 新格式记录 creatorId 为 memberId（mem_xxx），旧格式为 openID。
   */
  getSelfSubjectId(): string {
    return this.db.getCurrentMemberId() || this.db.getCurrentUserId();
  }

  /** 从记录创建者推导归属主体（mem_xxx 直接用；旧 openID 映射到 memberId） */
  getRecordSubjectId(creatorId: string): string {
    return normalizeSubjectId(creatorId, this.getMembersUserIdMap());
  }

  /** 指定归属主体下的经期记录（已按可见性过滤） */
  getRecordsBySubject(subjectId: string): PeriodRecord[] {
    return filterRecordsBySubject(this.getRecords(), subjectId, this.getMembersUserIdMap());
  }

  /** 指定归属主体下的啪啪记录（已按可见性过滤） */
  getIntimacyRecordsBySubject(subjectId: string): IntimacyRecord[] {
    return filterRecordsBySubject(this.getIntimacyRecords(), subjectId, this.getMembersUserIdMap());
  }

  /** 构建 openID → memberId 映射（用于旧格式 creatorId 归一化到当前家庭的成员标识） */
  private getMembersUserIdMap(): Map<string, string> {
    const map = new Map<string, string>();
    const members = this.db.getMembers();
    for (const m of members) {
      if (m.userId && m.id) {
        map.set(m.userId, m.id);
      }
    }
    return map;
  }

  async savePeriodRecord(startDate: string, duration: number, cycleLength: number,
    symptoms: string[] = [], mood: string = '', note: string = ''): Promise<PeriodRecord> {
    // 新记录时 endDate 暂等于 startDate，表示经期尚未结束
    // 用户点"记录结束"时会更新 endDate 和实际 duration
    const now = new Date().toISOString();
    const memberId = this.db.getCurrentMemberId();
    const family = this.db.getCurrentFamily();

    const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.PERIOD, Visibility.PRIVATE);
    const record: PeriodRecord = {
      id: generateId('pr'),
      familyId: family?.id ?? '',
      creatorId: memberId,
      visibility: vis.visibility,
      visibleMembers: vis.visibleMembers,
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
    const memberId = this.db.getCurrentMemberId();
    const family = this.db.getCurrentFamily();

    const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.PERIOD, Visibility.PRIVATE);
    const record: IntimacyRecord = {
      id: generateId('ir'),
      familyId: family?.id ?? '',
      creatorId: memberId,
      visibility: vis.visibility,
      visibleMembers: vis.visibleMembers,
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
  async endPeriod(endDate: string, subjectId?: string): Promise<PeriodRecord | null> {
    const records = this.getRecordsBySubject(subjectId || this.getSelfSubjectId());
    if (records.length === 0) return null;

    // 按 startDate 降序 + createdAt 降序排序：同一天有多条记录时，最新创建的排在前
    // （修复"结束后再点来了"场景：旧记录与新记录 startDate 相同，单纯按 startDate 排序
    // 不稳定，可能取到已结束的旧记录导致 endPeriod 覆盖错误记录）
    const sorted = [...records].sort((a, b) => {
      const cmp = b.startDate.localeCompare(a.startDate);
      if (cmp !== 0) return cmp;
      return b.createdAt.localeCompare(a.createdAt);
    });
    // 取最新的未结束记录（endDate 为空）
    const latest = sorted.find(r => !r.endDate || r.endDate === '');
    if (!latest) return null;

    // 计算实际持续天数
    const start = toDateAtLocalMidnight(latest.startDate);
    const end = toDateAtLocalMidnight(endDate);
    const actualDuration = daysBetween(start, end) + 1;
    if (actualDuration < 1) return null;

    // 计算实际周期长度（取上一条记录，跳过当前 latest）
    let actualCycleLength = latest.cycleLength;
    const prev = sorted.find(r => r.id !== latest.id);
    if (prev) {
      const prevStart = toDateAtLocalMidnight(prev.startDate);
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
   * 判断当前是否处于经期中（存在尚未标记结束的经期记录）
   *
   * 不只看 sorted[0]：当同一天有多条记录（如"结束后再点来了"产生的新记录与旧记录
   * startDate 相同），按 startDate 降序排序不稳定，可能取到已结束的旧记录导致误判
   * periodInProgress=false，结束按钮无法激活。改为检查是否存在任意 endDate 为空的记录。
   */
  isPeriodInProgress(subjectId?: string): boolean {
    const records = this.getRecordsBySubject(subjectId || this.getSelfSubjectId());
    if (records.length === 0) return false;
    return records.some(r => !r.endDate || r.endDate === '');
  }

  /**
   * 获取当前周期状态
   */
  getCurrentCycleStatus(subjectId?: string): CycleStatus {
    const records = this.getRecordsBySubject(subjectId || this.getSelfSubjectId());
    if (records.length === 0) {
      return { currentDay: 0, cycleLength: 28, duration: 5, phase: 'unknown', nextPeriodDate: '' };
    }

    // 按 startDate 降序排序，确保取到最近一次周期记录
    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];
    const startDate = toDateAtLocalMidnight(latest.startDate);
    // today 必须规范化到本地午夜，避免与午夜对齐的 startDate 相减后
    // 因 Math.round 把半天向上取整导致 currentDay 多算一天（午后操作即触发）
    const today = toDateAtLocalMidnight(formatDate(new Date()));
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
  getCalendarMarks(year: number, month: number, subjectId?: string): MarkedDate[] {
    const marks: MarkedDate[] = [];
    const records = this.getRecordsBySubject(subjectId || this.getSelfSubjectId());
    const intimacyRecords = this.getIntimacyRecordsBySubject(subjectId || this.getSelfSubjectId());

    // 经期标记仅在有经期记录时计算；啪啪标记无论是否有经期记录都需渲染
    if (records.length > 0) {
      const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
      const latest = sorted[0];
      const prediction = calculateAdaptivePeriodPrediction(sorted);
      const cycleLength = prediction.predictedCycleLength;
      const duration = this.calculateAdaptiveDuration(sorted);
      const startDate = toDateAtLocalMidnight(latest.startDate);

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
            color: PERIOD_MARK_COLORS.PERIOD,
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
              marks.push({ date: dateStr, color: PERIOD_MARK_COLORS.OVULATION, icons: ['⭐'] });
            } else {
              marks.push({ date: dateStr, color: PERIOD_MARK_COLORS.FERTILE });
            }
          } else if (cycleDay > duration && cycleDay < ovulationDay - 5) {
            marks.push({ date: dateStr, color: PERIOD_MARK_COLORS.SAFE });
          } else if (cycleDay > ovulationDay + 1) {
            marks.push({ date: dateStr, color: PERIOD_MARK_COLORS.SAFE });
          }
        }
      }
    }

    // 啪啪记录标记 — 支持与经期 emoji 共存
    for (const ir of intimacyRecords) {
      const irDate = ir.date;
      if (irDate.startsWith(`${year}-${month.toString().padStart(2, '0')}`)) {
        const existingIndex = marks.findIndex(m => m.date === irDate);
        if (existingIndex === -1) {
          marks.push({ date: irDate, color: PERIOD_MARK_COLORS.INTIMACY, icons: ['💗'] });
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
    const records = this.getRecordsBySubject(this.getSelfSubjectId());
    if (records.length === 0) return 0;
    const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
    const latest = sorted[0];
    const startDate = toDateAtLocalMidnight(latest.startDate);
    const targetDate = toDateAtLocalMidnight(dateStr);
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
    const records = this.getRecordsBySubject(this.getSelfSubjectId());
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
   * 根据 PeriodReminderSettings 和当前周期数据，调和自动生成的周期 Reminder。
   *
   * 修复「周期提醒全家重复出现」的要点：
   * 1. 并发合并：进入周期页时 aboutToAppear/refreshData 可能同时触发，
   *    用 in-flight Promise 合并并发调用（旧实现两次交错执行会各自重建一批提醒）
   * 2. 稳定 ID：每种提醒固定 ID（per_3d_{memberId} 等），重复同步就地更新同一条记录，
   *    而不是「全删 + 随机新 ID 重建」——后者在并发/同步滞后时必然产生重复并同步给全家
   * 3. 禁用不删除：开关关闭时置空 dueTime（各列表已过滤、不再发布系统通知），
   *    不删记录——云端「删除 version+1 后重建 version 1」会被版本冲突检测拒绝，
   *    导致记录在云端永久消失
   * 4. 就地更新保留 isCompleted（dueTime 不变时）：非创建者勾选「已读」后，
   *    下一次同步不会把提醒复活成未完成；进入新周期（dueTime 变化）才重置
   * 5. 遗留清理：历史版本随机 ID 的周期提醒（重复记录）在此被删除，
   *    删除操作同步云端后全家各端自动消失
   */
  async syncPeriodReminders(): Promise<void> {
    if (this.syncInFlight) return this.syncInFlight;
    const run = this.doSyncPeriodReminders();
    this.syncInFlight = run;
    try {
      await run;
    } finally {
      this.syncInFlight = null;
    }
  }

  private async doSyncPeriodReminders(): Promise<void> {
    const settings = this.db.getPeriodReminderSettings();
    const cycleStatus = this.getCurrentCycleStatus();

    const now = new Date().toISOString();
    const todayStr = formatDate(new Date());
    const memberId = this.db.getCurrentMemberId();
    const family = this.db.getCurrentFamily();
    const familyId = family?.id ?? '';
    const periodVis = this.db.resolveModuleVisibilityForRecord(ModuleId.PERIOD, Visibility.PRIVATE);

    // 期望状态（纯函数）：按开关与周期预测生成稳定 ID 的提醒列表
    const specs = buildPeriodReminderSpecs(settings, cycleStatus, memberId, todayStr);

    // 当前用户名下的周期提醒（含历史版本随机 ID 产生的重复记录）
    const ownReminders = this.db.getReminders()
      .filter(r => r.reminderType === 'period' && this.db.isRecordCreator(r.creatorId));

    // 调和计划（纯函数）：决定就地更新 / 隐藏 / 删除遗留 / 新建
    const plan = planPeriodReminderSync(ownReminders, specs, memberId,
      periodVis.visibility, periodVis.visibleMembers ?? []);

    for (const u of plan.updates) {
      const target = u.target;
      await this.db.updateReminder({
        id: u.record.id, familyId, creatorId: memberId,
        visibility: periodVis.visibility, visibleMembers: periodVis.visibleMembers,
        version: u.record.version + 1, createdAt: u.record.createdAt, updatedAt: now,
        title: target.title, description: target.description, reminderType: 'period',
        dueTime: target.dueTime,
        isRecurring: false, recurrenceRule: '',
        isCompleted: u.resetCompleted ? false : u.record.isCompleted,
        completedAt: u.resetCompleted ? '' : u.record.completedAt,
        reminderSettings: []
      });
    }

    for (const r of plan.hides) {
      await this.db.updateReminder({
        id: r.id, familyId, creatorId: memberId,
        visibility: periodVis.visibility, visibleMembers: periodVis.visibleMembers,
        version: r.version + 1, createdAt: r.createdAt, updatedAt: now,
        title: r.title, description: r.description, reminderType: 'period',
        dueTime: '',
        isRecurring: false, recurrenceRule: '',
        isCompleted: false, completedAt: '',
        reminderSettings: []
      });
    }

    for (const id of plan.deletes) {
      await this.db.deleteReminder(id);
    }

    for (const spec of plan.creates) {
      await this.db.saveReminder({
        id: spec.id, familyId, creatorId: memberId,
        visibility: periodVis.visibility, visibleMembers: periodVis.visibleMembers,
        version: 1, createdAt: now, updatedAt: now,
        title: spec.title, description: spec.description, reminderType: 'period',
        dueTime: spec.dueTime,
        isRecurring: false, recurrenceRule: '',
        isCompleted: false, completedAt: '', reminderSettings: []
      });
    }
  }

}

// ===== 周期提醒同步 —— 纯函数（可单元测试） =====

/** 排卵相关建议文案 */
const OVULATION_RISK_ADVICE = '怀孕几率较高，备孕可重点关注';

/**
 * 构建当前成员的周期提醒期望状态（稳定 ID + 确定性 dueTime）
 * 纯函数：输入开关与周期预测，输出应存在的提醒列表，无副作用。
 * - 无有效预测（currentDay<=0 或 nextPeriodDate 为空）→ 空列表
 * - 排卵日/易孕期提醒只在对应日期仍为未来时才生成
 */
export function buildPeriodReminderSpecs(settings: PeriodReminderSettings,
  cycleStatus: CycleStatus, memberId: string, todayStr: string): PeriodReminderSpec[] {
  const specs: PeriodReminderSpec[] = [];
  if (cycleStatus.currentDay <= 0 || !cycleStatus.nextPeriodDate) {
    return specs;
  }
  const nextPeriodDate = cycleStatus.nextPeriodDate;
  // 与排卵日/易孕期开始日（均已规范化到本地午夜）比较时，today 也必须规范化到本地午夜，
  // 否则一天内的时刻会左右 ">" 判定（如排卵当天午后 today > 午夜排卵日，导致漏建提醒）
  const today = toDateAtLocalMidnight(todayStr);

  // 经期前3天提醒
  if (settings.remind3DaysBefore) {
    specs.push({
      id: `per_3d_${memberId}`,
      title: '🌸 经期前3天提醒',
      description: `预计 ${nextPeriodDate} 来姨妈，提前做好准备哦`,
      dueTime: `${addDaysToDateStr(nextPeriodDate, -3)}T09:00:00`
    });
  }

  // 经期前1天提醒
  if (settings.remind1DayBefore) {
    specs.push({
      id: `per_1d_${memberId}`,
      title: '🌸 经期前1天提醒',
      description: `预计明天 ${nextPeriodDate} 来姨妈，注意休息`,
      dueTime: `${addDaysToDateStr(nextPeriodDate, -1)}T09:00:00`
    });
  }

  // 排卵日提醒（只有未来的排卵日才提醒）
  if (settings.remindOvulation) {
    const ovulationDate = toDateAtLocalMidnight(addDaysToDateStr(nextPeriodDate, -14));
    if (ovulationDate > today) {
      specs.push({
        id: `per_ov_${memberId}`,
        title: '⭐ 排卵日提醒',
        description: `今天是排卵日，${OVULATION_RISK_ADVICE}`,
        dueTime: `${addDaysToDateStr(nextPeriodDate, -14)}T09:00:00`
      });
    }
  }

  // 易孕期提醒（只有未来的易孕期开始日才提醒）
  if (settings.remindFertile) {
    const fertileStart = toDateAtLocalMidnight(addDaysToDateStr(nextPeriodDate, -19)); // 排卵日前5天
    if (fertileStart > today) {
      specs.push({
        id: `per_ft_${memberId}`,
        title: '🔶 易孕期提醒',
        description: `易孕窗口已开启，持续至 ${addDaysToDateStr(nextPeriodDate, -13)}`,
        dueTime: `${addDaysToDateStr(nextPeriodDate, -19)}T09:00:00`
      });
    }
  }

  return specs;
}

/** 判断 id 是否为当前用户的周期提醒稳定 ID（per_3d_/per_1d_/per_ov_/per_ft_ 四种） */
export function isManagedPeriodReminderId(id: string, memberId: string): boolean {
  return id === `per_3d_${memberId}` || id === `per_1d_${memberId}`
    || id === `per_ov_${memberId}` || id === `per_ft_${memberId}`;
}

/** 就地更新项：record 为现有记录（保留其 isCompleted/createdAt/version），target 为目标状态 */
export interface PeriodReminderUpdate {
  record: Reminder;
  target: PeriodReminderSpec;
  resetCompleted: boolean;
}

/** 周期提醒调和计划：对现有记录分类处置 */
export interface PeriodReminderSyncPlan {
  updates: PeriodReminderUpdate[];
  hides: Reminder[];
  deletes: string[];
  creates: PeriodReminderSpec[];
}

/**
 * 计算周期提醒的调和计划：与现有记录比对，决定就地更新 / 隐藏 / 删除遗留 / 新建。
 * 纯函数：只返回计划不写库，可单元测试。
 * - updates：稳定 ID 存在且目标状态有差异 → 就地更新（dueTime 变化视为进入新周期，重置完成状态）
 * - hides：稳定 ID 但对应开关已关闭（或无有效预测）→ 置空 dueTime 隐藏（不删除，避免云端版本冲突）
 * - deletes：历史版本随机 ID 的重复记录 → 删除清理
 * - creates：缺失的稳定 ID 记录 → 新建
 */
export function planPeriodReminderSync(ownReminders: Reminder[], specs: PeriodReminderSpec[],
  memberId: string, visibility: Visibility, visibleMembers: string[]): PeriodReminderSyncPlan {
  const updates: PeriodReminderUpdate[] = [];
  const hides: Reminder[] = [];
  const deletes: string[] = [];
  const creates: PeriodReminderSpec[] = [];

  const targetVisibleStr = JSON.stringify(visibleMembers ?? []);

  for (const r of ownReminders) {
    let spec: PeriodReminderSpec | null = null;
    for (const s of specs) {
      if (s.id === r.id) { spec = s; break; }
    }
    if (spec) {
      // 稳定 ID 记录：就地更新。进入新周期（dueTime 变化）时重置完成状态，
      // 否则保留 isCompleted（非创建者勾选「已读」后不被复活）
      const isCycleChanged = r.dueTime !== spec.dueTime;
      const needsUpdate = isCycleChanged || r.title !== spec.title
        || r.description !== spec.description
        || r.visibility !== visibility
        || JSON.stringify(r.visibleMembers ?? []) !== targetVisibleStr;
      if (needsUpdate) {
        updates.push({ record: r, target: spec, resetCompleted: isCycleChanged });
      }
    } else if (isManagedPeriodReminderId(r.id, memberId)) {
      // 稳定 ID 但对应开关已关闭（或无有效预测）：置空 dueTime 隐藏（不删除）
      if (r.dueTime !== '') {
        hides.push(r);
      }
    } else {
      // 历史版本随机 ID 的周期提醒（重复记录）：删除，云端同步后全家消失
      deletes.push(r.id);
    }
  }

  // 缺失的稳定 ID 记录：新建
  for (const spec of specs) {
    let exists = false;
    for (const r of ownReminders) {
      if (r.id === spec.id) { exists = true; break; }
    }
    if (!exists) {
      creates.push(spec);
    }
  }

  return { updates, hides, deletes, creates };
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

/** 「来了」误触确认：距上次经期比预计周期提前超过该天数时弹窗确认（如周期28天、第15天点来了） */
export const EARLY_PERIOD_CONFIRM_DAYS = 7;

/** 「来了」点击确认检查结果 */
export interface PeriodRecordConfirm {
  needsConfirm: boolean;
  message: string;
}

/**
 * 判断点「来了」前是否需要弹窗确认（误触保护，纯函数）
 * - 经期进行中再点「来了」→ 会创建重复的进行中记录，需确认
 * - 距上次经期比预计周期提前超过 EARLY_PERIOD_CONFIRM_DAYS 天 → 需确认
 * - 无任何记录（首次记录）→ 不确认
 */
export function checkPeriodRecordConfirm(records: PeriodRecord[], selectedDate: string): PeriodRecordConfirm {
  const sorted = [...records].sort((a, b) => b.startDate.localeCompare(a.startDate));
  if (sorted.length === 0) {
    return { needsConfirm: false, message: '' };
  }
  const latest = sorted[0];
  if (!latest.endDate || latest.endDate === '') {
    return {
      needsConfirm: true,
      message: `经期正在进行中（开始于 ${latest.startDate}）。\n再次记录会创建一条新的经期记录，确认继续吗？`
    };
  }
  const day = daysBetweenDateStrings(latest.startDate, selectedDate) + 1;
  const cycleLength = calculateAdaptivePeriodPrediction(sorted).predictedCycleLength;
  const earlyDays = cycleLength - day;
  if (earlyDays >= EARLY_PERIOD_CONFIRM_DAYS) {
    return {
      needsConfirm: true,
      message: `距上次经期（${latest.startDate}）仅 ${day} 天，比预计周期（${cycleLength}天）提前了 ${earlyDays} 天。\n确认 ${selectedDate} 开始经期吗？`
    };
  }
  return { needsConfirm: false, message: '' };
}

// ===== 记录归属主体（subject）—— 谁记录的周期 =====

/**
 * 归一化记录归属主体：
 * - 新格式 creatorId 直接是 memberId（mem_xxx 前缀），原样返回
 * - 旧格式 creatorId 是 openID（华为账号），通过成员表映射到 memberId
 * - 映射不到时原样返回（兼容旧数据展示）
 */
export function normalizeSubjectId(creatorId: string, membersByUserId: Map<string, string>): string {
  if (!creatorId) return '';
  if (creatorId.startsWith('mem_')) return creatorId;
  const memberId = membersByUserId.get(creatorId);
  return memberId ?? creatorId;
}

/** 按归属主体过滤记录（纯函数）；subjectId 为空时返回全部 */
export function filterRecordsBySubject<T extends BaseRecord>(records: T[], subjectId: string,
  membersByUserId: Map<string, string>): T[] {
  if (!subjectId) return records;
  return records.filter(r => normalizeSubjectId(r.creatorId, membersByUserId) === subjectId);
}

// ===== 归属主体选项 + 查看者模式判定 =====

/** 归属主体选项：memberId 为记录归属主体（我或共享成员），name 为展示名 */
export interface SubjectOption {
  memberId: string;
  name: string;
}

/**
 * 判断当前用户是否应进入"仅查看家人"模式（纯函数）：
 * 未开启"我要记录自己的姨妈"（recordSelf=false）且没有自己的归属数据（经期/啪啪）时进入
 */
export function shouldEnterViewerMode(selfHasRecords: boolean, recordSelf: boolean): boolean {
  return !recordSelf && !selfHasRecords;
}

/**
 * 构建归属主体选项（纯函数）：
 * - viewerMode=true：排除自己，只列有可见记录的其他成员（仅查看家人）
 * - viewerMode=false：自己在最前，其后是有可见记录的其他成员
 * membersById：memberId → 成员名；membersByUserId：openID → memberId（旧格式 creatorId 归一化）
 */
export function buildSubjectOptions(selfId: string,
  records: PeriodRecord[],
  intimacyRecords: IntimacyRecord[],
  membersById: Map<string, string>,
  membersByUserId: Map<string, string>,
  viewerMode: boolean): SubjectOption[] {
  const options: SubjectOption[] = [];
  const seen = new Set<string>();
  if (!viewerMode) {
    seen.add(selfId);
    options.push({ memberId: selfId, name: '我' });
  }
  const addSubject = (creatorId: string): void => {
    const s = normalizeSubjectId(creatorId, membersByUserId);
    if (s && (viewerMode ? s !== selfId : true) && !seen.has(s)) {
      seen.add(s);
      options.push({ memberId: s, name: membersById.get(s) || '成员' });
    }
  };
  for (const r of records) {
    addSubject(r.creatorId);
  }
  for (const r of intimacyRecords) {
    addSubject(r.creatorId);
  }
  return options;
}
