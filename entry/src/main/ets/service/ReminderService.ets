/**
 * 提醒服务 - 对接系统提醒代理 (ReminderRequestManager)
 *
 * 优先使用 @kit.ReminderAgentKit 发布系统级提醒：
 * - 应用退出后仍可触发
 * - 锁屏状态可见
 * - 支持重复规则（每日用药、周期提醒等）
 * - 系统级通知，不会被应用进程杀掉
 *
 * 降级策略：系统提醒 API 失败时（如调试签名），自动降级为本地 setTimeout。
 *
 * @example
 * ```typescript
 * const service = ReminderService.getInstance();
 * await service.refreshAllReminders(); // 在 EntryAbility.onForeground 调用
 * service.cancelAllReminders();         // 退出家庭时调用
 * ```
 */
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalDbService } from './LocalDbService';
import { Medication } from '../model/Medication';
import { Reminder } from '../model/Reminder';
import { toDateAtLocalMidnight, toDateTime, formatDate } from '../common/Utils';

const TAG = '[ReminderService]';
const DOMAIN = 0x0000;

/** 已发布的提醒ID映射（本地ID → 系统提醒ID） */
interface PublishedReminder {
  localId: string;
  systemId: number;
  type: 'medication' | 'reminder';
}

export class ReminderService {
  private static instance: ReminderService | null = null;
  private db: LocalDbService = LocalDbService.getInstance();
  private timerIds: number[] = [];
  private publishedReminders: PublishedReminder[] = [];
  private useSystemReminder: boolean = true;

  private constructor() {
    // 从本地恢复已发布的提醒ID映射
    this.loadPublishedReminders();
  }

  static getInstance(): ReminderService {
    if (!ReminderService.instance) {
      ReminderService.instance = new ReminderService();
    }
    return ReminderService.instance;
  }

  // ===== 用药提醒 =====

  /**
   * 发布用药提醒
   * 每个药物的每个时间槽 → 一个系统级日历提醒
   *
   * @param medication - 用药记录（需包含 timeSlots、medicineName、dosage）
   */
  async publishMedicationReminder(medication: Medication): Promise<void> {
    if (this.useSystemReminder) {
      this.publishMedicationSystemReminder(medication);
    } else {
      this.publishMedicationLocalReminder(medication);
    }
  }

  /**
   * 发布提醒事项
   *
   * @param reminder - 提醒记录（需包含 dueTime）
   */
  async publishReminder(reminder: Reminder): Promise<void> {
    if (!reminder.dueTime) return;

    if (this.useSystemReminder) {
      this.publishReminderSystemReminder(reminder);
    } else {
      this.publishReminderLocalReminder(reminder);
    }
  }

  /**
   * 取消所有已发布的提醒（系统级 + 本地定时器）
   */
  cancelAllReminders(): void {
    // 取消系统级提醒
    for (const published of this.publishedReminders) {
      this.cancelSystemReminder(published.systemId);
    }
    this.publishedReminders = [];
    this.savePublishedReminders();

    // 取消本地定时器
    for (const id of this.timerIds) {
      clearTimeout(id);
    }
    this.timerIds = [];
  }

  /**
   * 刷新所有提醒（应用启动/前台切换时调用）
   * 顺序执行发布，避免并发超出系统提醒数量限制
   */
  async refreshAllReminders(): Promise<void> {
    this.cancelAllReminders();

    const medications = this.db.getMedications().filter(m => m.isActive);
    for (const med of medications) {
      await this.publishMedicationReminder(med);
    }

    const reminders = this.db.getReminders().filter(r => !r.isCompleted);
    for (const reminder of reminders) {
      await this.publishReminder(reminder);
    }

    hilog.info(DOMAIN, TAG, 'All reminders refreshed: %{public}d medications, %{public}d reminders',
      medications.length, reminders.length);
  }

  // ===== 系统级提醒实现 =====

  /**
   * 发布用药系统提醒（日历类型，支持重复）
   */
  private async publishMedicationSystemReminder(medication: Medication): Promise<void> {
    const memberName = this.getMemberName(medication.forMemberId);
    const title = '💊 用药提醒';
    const content = `${memberName} · ${medication.medicineName} (${medication.dosage})`;

    for (const timeSlot of medication.timeSlots) {
      const parts: string[] = timeSlot.split(':');
      if (parts.length < 1 || parts[0] === '') {
        hilog.warn(DOMAIN, TAG, 'Invalid timeSlot format: %{public}s', timeSlot);
        continue;
      }
      const hour: number = parseInt(parts[0]);
      const minute: number = parts.length > 1 ? parseInt(parts[1]) : 0;
      if (isNaN(hour) || isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        hilog.warn(DOMAIN, TAG, 'Invalid timeSlot values: %{public}s', timeSlot);
        continue;
      }

      // 先取消同一药物的旧提醒
      const existKey = `med_${medication.id}_${timeSlot}`;
      const existing = this.publishedReminders.find(r => r.localId === existKey);
      if (existing) {
        this.cancelSystemReminder(existing.systemId);
        this.publishedReminders = this.publishedReminders.filter(r => r.localId !== existKey);
      }

      try {
        // 计算下一次触发时间的真实日期
        const now = new Date();
        const nextDate = toDateAtLocalMidnight(formatDate(now));
        nextDate.setHours(hour, minute, 0, 0);
        if (nextDate.getTime() <= now.getTime()) {
          nextDate.setDate(nextDate.getDate() + 1);
        }

        const dateTime: reminderAgentManager.LocalDateTime = {
          year: nextDate.getFullYear(),
          month: nextDate.getMonth() + 1, // API 月份从1开始
          day: nextDate.getDate(),
          hour: hour,
          minute: minute
        };

        let request: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          dateTime: dateTime,
          repeatMonths: [],
          repeatDays: medication.frequency === 'daily' ?
            [1, 2, 3, 4, 5, 6, 7] : // 每天
            [1, 3, 5], // 隔天（简化）
          title: title,
          content: content,
          expiredContent: `${medication.medicineName} 用药时间已过`,
          slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
        };

        const reminderId: number = await reminderAgentManager.publishReminder(request);
        this.publishedReminders.push({
          localId: existKey,
          systemId: reminderId,
          type: 'medication'
        });

        hilog.info(DOMAIN, TAG,
          'Published medication reminder: %{public}s at %{public}s, systemId=%{public}d',
          medication.medicineName, timeSlot, reminderId);
      } catch (err) {
        const e = err as BusinessError;
        hilog.warn(DOMAIN, TAG,
          'Failed to publish medication reminder: code=%{public}s, msg=%{public}s',
          e.code, e.message);
        // 降级到本地定时器
        this.publishMedicationLocalTimer(medication, timeSlot, content);
      }
    }

    this.savePublishedReminders();
  }

  /**
   * 发布提醒事项系统提醒
   * - 一次性提醒：日历类型，绑定完整日期时间，仅在到期时刻触发一次。
   *   不能用闹钟类型：它只含时分不含日期，一次性提醒会错日触发/每天重复触发
   * - 重复提醒：闹钟类型，按星期重复
   */
  private async publishReminderSystemReminder(reminder: Reminder): Promise<void> {
    if (!reminder.dueTime) return;

    const dueTime = toDateTime(reminder.dueTime);
    const delayMs = dueTime.getTime() - Date.now();
    if (delayMs <= 0) return;

    // 先取消旧提醒
    const existKey = `rem_${reminder.id}`;
    const existing = this.publishedReminders.find(r => r.localId === existKey);
    if (existing) {
      this.cancelSystemReminder(existing.systemId);
      this.publishedReminders = this.publishedReminders.filter(r => r.localId !== existKey);
    }

    try {
      let reminderId: number;

      if (reminder.isRecurring && reminder.recurrenceRule) {
        // 重复提醒：闹钟类型（按星期重复）
        const rule = reminder.recurrenceRule.toLowerCase();
        const daysOfWeek: number[] = rule === 'weekly'
          ? [1, 2, 3, 4, 5] // 周一至周五（每周重复）
          : [1, 2, 3, 4, 5, 6, 7]; // 每天 / monthly / yearly / 默认
        const alarmRequest: reminderAgentManager.ReminderRequestAlarm = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
          hour: dueTime.getHours(),
          minute: dueTime.getMinutes(),
          daysOfWeek: daysOfWeek,
          title: '📋 ' + reminder.title,
          content: reminder.description || '家庭提醒',
          expiredContent: `提醒已过期: ${reminder.title}`,
          slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
        };
        reminderId = await reminderAgentManager.publishReminder(alarmRequest);
      } else {
        // 一次性提醒：日历类型，绑定具体日期时间，只触发一次
        const dateTime: reminderAgentManager.LocalDateTime = {
          year: dueTime.getFullYear(),
          month: dueTime.getMonth() + 1, // API 月份从1开始
          day: dueTime.getDate(),
          hour: dueTime.getHours(),
          minute: dueTime.getMinutes()
        };
        const calendarRequest: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          dateTime: dateTime,
          repeatMonths: [],
          repeatDays: [],
          title: '📋 ' + reminder.title,
          content: reminder.description || '家庭提醒',
          expiredContent: `提醒已过期: ${reminder.title}`,
          slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
        };
        reminderId = await reminderAgentManager.publishReminder(calendarRequest);
      }

      this.publishedReminders.push({
        localId: existKey,
        systemId: reminderId,
        type: 'reminder'
      });

      hilog.info(DOMAIN, TAG,
        'Published reminder: %{public}s, systemId=%{public}d',
        reminder.title, reminderId);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG,
        'Failed to publish system reminder: code=%{public}s, msg=%{public}s',
        e.code, e.message);
      // 降级到本地定时器
      this.publishReminderLocalReminder(reminder);
    }

    this.savePublishedReminders();
  }

  /**
   * 取消单个系统提醒
   */
  private cancelSystemReminder(systemId: number): void {
    try {
      reminderAgentManager.cancelReminder(systemId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Cancel reminder %{public}d failed: %{public}s',
        systemId, (err as Error).message);
    }
  }

  // ===== 降级方案：本地定时器 =====

  private publishMedicationLocalReminder(medication: Medication): void {
    const memberName = this.getMemberName(medication.forMemberId);
    for (const timeSlot of medication.timeSlots) {
      const content = `${memberName} · ${medication.medicineName} (${medication.dosage})`;
      this.publishMedicationLocalTimer(medication, timeSlot, content);
    }
  }

  private publishMedicationLocalTimer(medication: Medication, timeSlot: string, content: string): void {
    const parts: string[] = timeSlot.split(':');
    const hour: number = parseInt(parts[0]);
    const minute: number = parts.length > 1 ? parseInt(parts[1]) : 0;
    const delayMs = this.calculateMillisFromNow(hour, minute);

    if (delayMs > 0) {
      const timerId = setTimeout(() => {
        hilog.info(DOMAIN, TAG, '💊 Medication reminder (local): %{public}s', content);
      }, delayMs);
      this.timerIds.push(timerId);
    }
  }

  private publishReminderLocalReminder(reminder: Reminder): void {
    if (!reminder.dueTime) return;
    const dueTime = toDateTime(reminder.dueTime);
    const delayMs = dueTime.getTime() - Date.now();
    if (delayMs <= 0) return;

    const timerId = setTimeout(() => {
      hilog.info(DOMAIN, TAG, '📋 Reminder (local): %{public}s', reminder.title);
    }, delayMs);
    this.timerIds.push(timerId);
  }

  // ===== 工具方法 =====

  private calculateMillisFromNow(hour: number, minute: number): number {
    const now = new Date();
    const today = formatDate(now);
    const target = toDateAtLocalMidnight(today);
    target.setHours(hour, minute, 0, 0);
    if (target.getTime() <= now.getTime()) {
      target.setDate(target.getDate() + 1);
    }
    return target.getTime() - now.getTime();
  }

  private getMemberName(memberId: string): string {
    const family = this.db.getCurrentFamily();
    if (!family) return '家人';
    const members = this.db.getMembersByFamilyId(family.id);
    const member = members.find(m => m.id === memberId);
    return member?.name ?? '家人';
  }

  // ===== 已发布提醒持久化 =====

  private loadPublishedReminders(): void {
    try {
      const raw = this.db.getPublishedReminderIds();
      // 恢复时取消旧的系统提醒（它们会在 refreshAllReminders 中重新发布）
      if (raw.length > 0) {
        hilog.info(DOMAIN, TAG, 'Cleaning up %{public}d stale reminder IDs', raw.length);
        for (const id of raw) {
          this.cancelSystemReminder(id);
        }
        // 清空持久化的ID，避免重复清理
        this.db.savePublishedReminderIds([]);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Load published reminders failed: %{public}s',
        (err as Error).message);
    }
  }

  private savePublishedReminders(): void {
    try {
      const systemIds = this.publishedReminders.map(r => r.systemId);
      this.db.savePublishedReminderIds(systemIds);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Save published reminders failed: %{public}s',
        (err as Error).message);
    }
  }
}
