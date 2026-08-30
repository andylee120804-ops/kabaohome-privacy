/**
 * 本地数据库服务 - 使用 Preferences 进行轻量级本地存储
 * V1阶段使用Preferences简化实现，V2升级到RelationalStore
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { FamilyMember } from '../model/FamilyMember';
import { Family } from '../model/Family';
import { PeriodRecord, IntimacyRecord, PeriodReminderSettings } from '../model/PeriodRecord';
import { Medication, MedicationLog } from '../model/Medication';
import { KidEvent, GrowthRecord } from '../model/KidEvent';
import { Reminder } from '../model/Reminder';
import { HealthMetric } from '../model/HealthMetric';
import { ShoppingItem } from '../model/ShoppingItem';
import { Photo } from '../model/Photo';
import { Memo } from '../model/Memo';
import { FamilyInvitation } from '../model/FamilyInvitation';
import { AccountingRecord, Budget } from '../model/AccountingRecord';
import { LocationPlace, PlaceType } from '../model/LocationPlace';
import { ModuleId, ModuleVisibility, ThemeColor, EmojiStyle, Visibility } from '../common/Constants';
import { filterByVisibility, formatDate } from '../common/Utils';

const PREF_NAME = 'kabao_home_db';

interface PrefStore {
  get(key: string, def: string): Promise<string>;
  put(key: string, value: string): Promise<void>;
  flush(): Promise<void>;
  getSync(key: string, def: Object): Object;
  delete(key: string): Promise<void>;
}

interface HasId {
  id: string;
}

/**
 * 单个成员的位置共享设置
 * - 共享名单是「单向」的：A 把 B 加入 visibleMembers，仅代表 B 能看到 A，不代表 A 能看到 B
 * - 同一份名单同时决定：实时位置的可见范围 + 到达通知的接收人
 */
export interface LocationShareSettings {
  /** 主开关：关闭后任何人都看不到我的位置/到达通知 */
  shareEnabled: boolean;
  /** 共享可见范围 */
  visibility: Visibility;
  /** SELECTED 时指定的家庭成员ID列表 */
  visibleMembers: string[];
  /** 到达常用地点时是否自动给共享名单发通知 */
  notifyOnArrival: boolean;
  /** 上次到达通知触发记录，用于防抖（出入围栏抖动时不重复推） */
  lastNotifiedAt?: ArrivalNotificationRecord[];
}

export interface ArrivalNotificationRecord {
  placeId: string;
  notifiedAt: number;
}

export interface LocationShareEntry {
  memberId: string;
  settings: LocationShareSettings;
}

/** Per-member 位置共享设置存储结构 */
export type LocationShareMap = LocationShareEntry[];

/** 默认设置 */
export function defaultLocationShareSettings(): LocationShareSettings {
  return {
    shareEnabled: true,
    visibility: Visibility.FAMILY,
    visibleMembers: [],
    notifyOnArrival: false,
    lastNotifiedAt: []
  };
}

/**
 * @deprecated 旧的全局位置设置（仅做向后兼容读取，写入时会迁移到 LocationShareSettings）
 */
export interface LocationSettings {
  isSharing: boolean;
  schoolNotification: boolean;
  homeNotification: boolean;
}

export interface BudgetProgressResult {
  budget: number;
  spent: number;
  remaining: number;
  percentage: number;
}

export class LocalDbService {
  private static instance: LocalDbService | null = null;
  private prefs: PrefStore | null = null;
  /** 写后缓存：saveList 写入后立即更新缓存，getList 优先读缓存，避免 async write 与 sync read 竞争 */
  private writeCache: Map<string, string> = new Map();

  private constructor() {}

  static getInstance(): LocalDbService {
    if (!LocalDbService.instance) {
      LocalDbService.instance = new LocalDbService();
    }
    return LocalDbService.instance;
  }

  async init(context: Context): Promise<void> {
    if (this.prefs) {
      return; // 已初始化，幂等返回
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME) as PrefStore;
  }

  isInitialized(): boolean {
    return this.prefs !== null;
  }

  private ensurePrefs(): PrefStore {
    if (!this.prefs) {
      throw new Error('LocalDbService not initialized. Call init() first.');
    }
    return this.prefs;
  }

  // ---- 通用读写 ----
  async saveList<T>(key: string, items: T[]): Promise<void> {
    const p = this.ensurePrefs();
    const json = JSON.stringify(items);
    // 写后立即更新缓存，确保后续 sync getList 能读到最新数据
    this.writeCache.set(key, json);
    await p.put(key, json);
    await p.flush();
  }

  // TODO(V2): 迁移到 RelationalStore 后改为异步 async getList
  private getList<T>(key: string): T[] {
    // 优先读写后缓存，避免 async put 尚未落盘时 sync getSync 读到旧数据
    const cached = this.writeCache.get(key);
    const raw = cached ?? (() => {
      const p = this.ensurePrefs();
      return p.getSync(key, '[]') as string;
    })();
    if (!raw || raw === '[]') return [];
    try {
      return JSON.parse(raw) as T[];
    } catch (_) {
      return [];
    }
  }

  private async saveItem<T extends object>(key: string, item: T): Promise<void> {
    const list = this.getList<T>(key);
    const arr = [...list, item];
    await this.saveList(key, arr);
  }

  private async updateItem<T extends HasId>(key: string, item: T): Promise<void> {
    const list = this.getList<T>(key);
    const updated = list.map(i => i.id === item.id ? item : i);
    await this.saveList(key, updated);
  }

  private async removeItem(key: string, id: string): Promise<void> {
    const list = this.getList<HasId>(key);
    const filtered = list.filter(i => i.id !== id);
    await this.saveList(key, filtered);
  }

  // ---- 家庭 ----
  async saveFamily(family: Family): Promise<void> {
    await this.saveItem('families', family);
  }

  getFamilies(): Family[] {
    return this.getList<Family>('families');
  }

  getCurrentFamily(): Family | null {
    const families = this.getFamilies();
    return families.length > 0 ? families[0] : null;
  }

  /** 获取当前家庭ID，若未加入家庭则返回空字符串 */
  getCurrentFamilyId(): string {
    const family = this.getCurrentFamily();
    return family?.id ?? '';
  }

  // ---- 家庭成员 ----
  async saveMember(member: FamilyMember): Promise<void> {
    await this.saveItem('members', member);
  }

  async updateMember(member: FamilyMember): Promise<void> {
    await this.updateItem('members', member);
  }

  async removeMember(id: string): Promise<void> {
    await this.removeItem('members', id);
  }

  getMembers(): FamilyMember[] {
    return this.getList<FamilyMember>('members');
  }

  getMembersByFamilyId(familyId: string): FamilyMember[] {
    return this.getMembers().filter(m => m.familyId === familyId);
  }

  // ---- 姨妈周期 ----
  async savePeriodRecord(record: PeriodRecord): Promise<void> {
    await this.saveItem('period_records', record);
  }

  getPeriodRecords(): PeriodRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: PeriodRecord[];
    if (!familyId) {
      records = this.getList<PeriodRecord>('period_records');
    } else {
      records = this.getList<PeriodRecord>('period_records').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async deletePeriodRecord(id: string): Promise<void> {
    await this.removeItem('period_records', id);
  }

  async updatePeriodRecord(record: PeriodRecord): Promise<void> {
    await this.updateItem('period_records', record);
  }

  async deleteIntimacyRecord(id: string): Promise<void> {
    await this.removeItem('intimacy_records', id);
  }

  // ---- 啪啪记录 ----
  async saveIntimacyRecord(record: IntimacyRecord): Promise<void> {
    await this.saveItem('intimacy_records', record);
  }

  getIntimacyRecords(): IntimacyRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: IntimacyRecord[];
    if (!familyId) {
      records = this.getList<IntimacyRecord>('intimacy_records');
    } else {
      records = this.getList<IntimacyRecord>('intimacy_records').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  // ---- 用药 ----
  async saveMedication(med: Medication): Promise<void> {
    await this.saveItem('medications', med);
  }

  async updateMedication(med: Medication): Promise<void> {
    await this.updateItem('medications', med);
  }

  getMedications(): Medication[] {
    const familyId = this.getCurrentFamilyId();
    let records: Medication[];
    if (!familyId) {
      records = this.getList<Medication>('medications');
    } else {
      records = this.getList<Medication>('medications').filter(m => m.familyId === familyId || m.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  getMedicationsByMember(memberId: string): Medication[] {
    return this.getMedications().filter(m => m.forMemberId === memberId);
  }

  async deleteMedication(id: string): Promise<void> {
    await this.removeItem('medications', id);
  }

  // ---- 服药记录 ----
  async saveMedicationLog(log: MedicationLog): Promise<void> {
    await this.saveItem('medication_logs', log);
  }

  getMedicationLogs(): MedicationLog[] {
    const familyId = this.getCurrentFamilyId();
    let records: MedicationLog[];
    if (!familyId) {
      records = this.getList<MedicationLog>('medication_logs');
    } else {
      records = this.getList<MedicationLog>('medication_logs').filter(l => l.familyId === familyId || l.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  getTodayLogs(): MedicationLog[] {
    const today = formatDate(new Date());
    return this.getMedicationLogs().filter(l => l.takenAt.startsWith(today));
  }

  async deleteMedicationLog(id: string): Promise<void> {
    await this.removeItem('medication_logs', id);
  }

  /** 删除某药物某时间段的今日服药记录 */
  async deleteTodayMedicationLog(medicationId: string, timeSlot: string): Promise<void> {
    const today = formatDate(new Date());
    const allLogs = this.getList<MedicationLog>('medication_logs');
    const remaining = allLogs.filter(l =>
      !(l.medicationId === medicationId && l.timeSlot === timeSlot && l.takenAt.startsWith(today))
    );
    await this.saveList('medication_logs', remaining);
  }

  // ---- 健康指标 ----
  async saveHealthMetric(metric: HealthMetric): Promise<void> {
    await this.saveItem('health_metrics', metric);
  }

  async updateHealthMetric(metric: HealthMetric): Promise<void> {
    await this.updateItem('health_metrics', metric);
  }

  getHealthMetrics(): HealthMetric[] {
    const familyId = this.getCurrentFamilyId();
    let records: HealthMetric[];
    if (!familyId) {
      records = this.getList<HealthMetric>('health_metrics');
    } else {
      records = this.getList<HealthMetric>('health_metrics').filter(m => m.familyId === familyId || m.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  getHealthMetricsByMember(memberId: string): HealthMetric[] {
    return this.getHealthMetrics().filter(m => m.forMemberId === memberId);
  }

  async deleteHealthMetric(id: string): Promise<void> {
    await this.removeItem('health_metrics', id);
  }

  // ---- 孩子事项 ----
  async saveKidEvent(event: KidEvent): Promise<void> {
    await this.saveItem('kid_events', event);
  }

  async updateKidEvent(event: KidEvent): Promise<void> {
    await this.updateItem('kid_events', event);
  }

  getKidEvents(): KidEvent[] {
    const familyId = this.getCurrentFamilyId();
    let records: KidEvent[];
    if (!familyId) {
      records = this.getList<KidEvent>('kid_events');
    } else {
      records = this.getList<KidEvent>('kid_events').filter(e => e.familyId === familyId || e.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  getKidEventsByMember(memberId: string): KidEvent[] {
    return this.getKidEvents().filter(e => e.forMemberId === memberId);
  }

  async deleteKidEvent(id: string): Promise<void> {
    await this.removeItem('kid_events', id);
  }

  // ---- 成长记录 ----
  async saveGrowthRecord(record: GrowthRecord): Promise<void> {
    await this.saveItem('growth_records', record);
  }

  getGrowthRecordsByMember(memberId: string): GrowthRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: GrowthRecord[];
    if (!familyId) {
      records = this.getList<GrowthRecord>('growth_records').filter(r => r.forMemberId === memberId);
    } else {
      records = this.getList<GrowthRecord>('growth_records')
        .filter(r => r.forMemberId === memberId && (r.familyId === familyId || r.familyId === ''));
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async updateGrowthRecord(record: GrowthRecord): Promise<void> {
    await this.updateItem('growth_records', record);
  }

  async deleteGrowthRecord(id: string): Promise<void> {
    await this.removeItem('growth_records', id);
  }

  // ---- 提醒事项 ----
  async saveReminder(reminder: Reminder): Promise<void> {
    await this.saveItem('reminders', reminder);
  }

  async updateReminder(reminder: Reminder): Promise<void> {
    await this.updateItem('reminders', reminder);
  }

  getReminders(): Reminder[] {
    const familyId = this.getCurrentFamilyId();
    let records: Reminder[];
    if (!familyId) {
      records = this.getList<Reminder>('reminders');
    } else {
      records = this.getList<Reminder>('reminders').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async deleteReminder(id: string): Promise<void> {
    await this.removeItem('reminders', id);
  }

  // ---- 购物清单 ----
  async saveShoppingItem(item: ShoppingItem): Promise<void> {
    await this.saveItem('shopping_items', item);
  }

  async updateShoppingItem(item: ShoppingItem): Promise<void> {
    await this.updateItem('shopping_items', item);
  }

  getShoppingItems(): ShoppingItem[] {
    const familyId = this.getCurrentFamilyId();
    let records: ShoppingItem[];
    if (!familyId) {
      records = this.getList<ShoppingItem>('shopping_items');
    } else {
      records = this.getList<ShoppingItem>('shopping_items').filter(i => i.familyId === familyId || i.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async deleteShoppingItem(id: string): Promise<void> {
    await this.removeItem('shopping_items', id);
  }

  // ---- 家庭相册 ----
  async savePhoto(photo: Photo): Promise<void> {
    await this.saveItem('photos', photo);
  }

  getPhotos(): Photo[] {
    const familyId = this.getCurrentFamilyId();
    let records: Photo[];
    if (!familyId) {
      records = this.getList<Photo>('photos');
    } else {
      records = this.getList<Photo>('photos').filter(p => p.familyId === familyId || p.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async updatePhoto(photo: Photo): Promise<void> {
    await this.updateItem('photos', photo);
  }

  async deletePhoto(id: string): Promise<void> {
    await this.removeItem('photos', id);
  }

  // ---- 家庭备忘 ----
  async saveMemo(memo: Memo): Promise<void> {
    await this.saveItem('memos', memo);
  }

  async updateMemo(memo: Memo): Promise<void> {
    await this.updateItem('memos', memo);
  }

  getMemos(): Memo[] {
    const familyId = this.getCurrentFamilyId();
    let records: Memo[];
    if (!familyId) {
      records = this.getList<Memo>('memos');
    } else {
      records = this.getList<Memo>('memos').filter(m => m.familyId === familyId || m.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async deleteMemo(id: string): Promise<void> {
    await this.removeItem('memos', id);
  }

  // ---- 邀请 ----
  async saveInvitation(inv: FamilyInvitation): Promise<void> {
    await this.saveItem('invitations', inv);
  }

  getInvitations(): FamilyInvitation[] {
    return this.getList<FamilyInvitation>('invitations');
  }

  // ---- 模块启用状态 ----
  async saveEnabledModules(modules: ModuleId[]): Promise<void> {
    await this.saveList('enabled_modules', modules);
  }

  getEnabledModules(): ModuleId[] {
    return this.getList<ModuleId>('enabled_modules');
  }

  // ---- 模块共享配置 ----
  async saveModuleVisibilityConfig(config: ModuleVisibility): Promise<void> {
    const configs = this.getModuleVisibilityConfigs();
    const idx = configs.findIndex(c => c.moduleId === config.moduleId);
    const updated = idx >= 0
      ? [...configs.slice(0, idx), config, ...configs.slice(idx + 1)]
      : [...configs, config];
    await this.saveList('module_visibility_configs', updated);
  }

  getModuleVisibilityConfigs(): ModuleVisibility[] {
    return this.getList<ModuleVisibility>('module_visibility_configs');
  }

  getModuleVisibilityConfig(moduleId: ModuleId): ModuleVisibility | null {
    return this.getModuleVisibilityConfigs().find(c => c.moduleId === moduleId) || null;
  }

  async removeModuleVisibilityConfig(moduleId: ModuleId): Promise<void> {
    const configs = this.getModuleVisibilityConfigs();
    await this.saveList('module_visibility_configs', configs.filter(c => c.moduleId !== moduleId));
  }

  // ---- 当前用户 ----
  async saveCurrentUserId(userId: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('current_user_id', userId);
    await p.flush();
  }

  getCurrentUserId(): string {
    const p = this.ensurePrefs();
    return p.getSync('current_user_id', '') as string;
  }

  // ---- AGC用户ID ----
  async saveAgcUserId(uid: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('agc_user_id', uid);
    await p.flush();
  }

  getAgcUserId(): string {
    const p = this.ensurePrefs();
    return p.getSync('agc_user_id', '') as string;
  }

  // ---- 姨妈周期提醒设置 ----
  async savePeriodReminderSettings(settings: PeriodReminderSettings): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('period_reminder_settings', JSON.stringify(settings));
    await p.flush();
  }

  getPeriodReminderSettings(): PeriodReminderSettings {
    const p = this.ensurePrefs();
    const raw = p.getSync('period_reminder_settings', '') as string;
    if (!raw) {
      return { remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false };
    }
    try {
      return JSON.parse(raw) as PeriodReminderSettings;
    } catch (_) {
      return { remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false };
    }
  }

  // ---- 是否已加入家庭 ----
  async saveHasFamily(hasFamily: boolean): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('has_family', hasFamily ? 'true' : 'false');
    await p.flush();
  }

  hasFamily(): boolean {
    const p = this.ensurePrefs();
    const value = p.getSync('has_family', 'false');
    return value === 'true' || value === true;
  }

  // ---- 家庭记账 ----
  async saveAccountingRecord(record: AccountingRecord): Promise<void> {
    await this.saveItem('accounting_records', record);
  }

  getAccountingRecords(): AccountingRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: AccountingRecord[];
    if (!familyId) {
      records = this.getList<AccountingRecord>('accounting_records');
    } else {
      records = this.getList<AccountingRecord>('accounting_records').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  async updateAccountingRecord(record: AccountingRecord): Promise<void> {
    await this.updateItem('accounting_records', record);
  }

  async deleteAccountingRecord(id: string): Promise<void> {
    await this.removeItem('accounting_records', id);
  }

  // ---- 预算 ----
  async saveBudget(budget: Budget): Promise<void> {
    const budgets = this.getList<Budget>('budgets');
    const idx = budgets.findIndex(b => b.year === budget.year && b.month === budget.month);
    const updated = idx >= 0
      ? [...budgets.slice(0, idx), budget, ...budgets.slice(idx + 1)]
      : [...budgets, budget];
    await this.saveList('budgets', updated);
  }

  getBudget(year: number, month: number): Budget | null {
    const familyId = this.getCurrentFamilyId();
    if (!familyId) return null;
    const budgets = this.getList<Budget>('budgets');
    return budgets.find(b => b.year === year && b.month === month && b.familyId === familyId) ?? null;
  }

  // ---- 通知确认时间 ----
  async saveLastNotificationAckTime(time: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('last_notification_ack_time', time);
    await p.flush();
  }

  getLastNotificationAckTime(): string {
    const p = this.ensurePrefs();
    return p.getSync('last_notification_ack_time', '') as string;
  }

  // ---- 今日已确认/忽略的待办ID列表（每日重置） ----
  async saveDismissedTodayIds(ids: string[]): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('dismissed_today_ids', JSON.stringify(ids));
    await p.flush();
  }

  getDismissedTodayIds(): string[] {
    const p = this.ensurePrefs();
    const raw = p.getSync('dismissed_today_ids', '[]') as string;
    try {
      const data = JSON.parse(raw) as string[];
      // 检查是否今日的数据（过期则清空）
      const savedDate = p.getSync('dismissed_today_date', '') as string;
      const today = formatDate(new Date());
      if (savedDate !== today) return [];
      return data;
    } catch (_) {
      return [];
    }
  }

  async addDismissedTodayId(id: string): Promise<void> {
    const ids = this.getDismissedTodayIds();
    if (!ids.includes(id)) {
      ids.push(id);
    }
    const p = this.ensurePrefs();
    const today = formatDate(new Date());
    await p.put('dismissed_today_ids', JSON.stringify(ids));
    await p.put('dismissed_today_date', today);
    await p.flush();
  }

  // ---- 欢迎卡是否已关闭（永久标记） ----
  isWelcomeDismissed(): boolean {
    const p = this.ensurePrefs();
    return p.getSync('welcome_dismissed', 'false') === 'true';
  }

  async setWelcomeDismissed(): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('welcome_dismissed', 'true');
    await p.flush();
  }

  // ---- 已发布的提醒ID（持久化，避免重启丢失） ----
  async savePublishedReminderIds(ids: number[]): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('published_reminder_ids', JSON.stringify(ids));
    await p.flush();
  }

  getPublishedReminderIds(): number[] {
    const p = this.ensurePrefs();
    const raw = p.getSync('published_reminder_ids', '[]') as string;
    try {
      return JSON.parse(raw) as number[];
    } catch (_) {
      return [];
    }
  }

  // ---- 家庭色系偏好 ----
  async saveThemeColor(theme: ThemeColor): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('theme_color', theme);
    await p.flush();
  }

  getThemeColor(): ThemeColor {
    const p = this.ensurePrefs();
    return p.getSync('theme_color', ThemeColor.WARM_CORAL) as ThemeColor;
  }

  // ---- 表情风格偏好 ----
  async saveEmojiStyle(style: EmojiStyle): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('emoji_style', style);
    await p.flush();
  }

  getEmojiStyle(): EmojiStyle {
    const p = this.ensurePrefs();
    return p.getSync('emoji_style', EmojiStyle.KABAO) as EmojiStyle;
  }

  // ---- 清除所有数据（退出家庭时使用） ----
  async clearAllData(): Promise<void> {
    // 清空写后缓存，避免 clearAllData 后 getList 返回过期数据
    this.writeCache.clear();
    const p = this.ensurePrefs();
    // 清除所有列表数据
    const listKeys = [
      'families', 'members', 'period_records', 'intimacy_records',
      'medications', 'medication_logs', 'health_metrics',
      'kid_events', 'growth_records', 'reminders',
      'shopping_items', 'photos', 'memos', 'invitations',
      'enabled_modules', 'module_visibility_configs',
      'accounting_records', 'budgets', 'location_places'
    ];
    for (const key of listKeys) {
      await p.put(key, '[]');
    }
    // 清除所有标量数据
    const scalarKeys = [
      'current_user_id', 'has_family', 'agc_user_id',
      'period_reminder_settings', 'last_notification_ack_time',
      'published_reminder_ids', 'theme_color', 'emoji_style',
      'location_settings', 'location_share_map', 'dismissed_today_date'
    ];
    for (const key of scalarKeys) {
      await p.delete(key);
    }
    await p.flush();
  }

  // ---- 位置共享设置（per-member） ----
  /**
   * 读取所有成员的位置共享设置 map（V1 本地模拟；V2 由云端同步下发）
   */
  getLocationShareMap(): LocationShareMap {
    const p = this.ensurePrefs();
    const raw = p.getSync('location_share_map', '') as string;
    if (!raw) {
      // 向后兼容：尝试读取旧的全局 location_settings
      const legacyRaw = p.getSync('location_settings', '') as string;
      if (legacyRaw) {
        try {
          const legacy = JSON.parse(legacyRaw) as LocationSettings;
          const uid = this.getCurrentUserId();
          if (uid) {
            const s = defaultLocationShareSettings();
            s.shareEnabled = legacy.isSharing;
            s.notifyOnArrival = legacy.homeNotification || legacy.schoolNotification;
            return [{ memberId: uid, settings: s }];
          }
        } catch (_) {
          // ignore
        }
      }
      return [];
    }
    try {
      return JSON.parse(raw) as LocationShareMap;
    } catch (_) {
      return [];
    }
  }

  /**
   * 读取某个成员的位置共享设置；不存在则返回默认值
   */
  getLocationShareSettings(memberId: string): LocationShareSettings {
    const map = this.getLocationShareMap();
    const entry = map.find(item => item.memberId === memberId);
    return entry ? entry.settings : defaultLocationShareSettings();
  }

  /**
   * 保存某个成员的位置共享设置（一般是当前用户）
   */
  async saveLocationShareSettings(memberId: string, settings: LocationShareSettings): Promise<void> {
    const p = this.ensurePrefs();
    const map = this.getLocationShareMap();
    const idx = map.findIndex(item => item.memberId === memberId);
    const entry: LocationShareEntry = { memberId, settings };
    if (idx >= 0) {
      map[idx] = entry;
    } else {
      map.push(entry);
    }
    await p.put('location_share_map', JSON.stringify(map));
    await p.flush();
  }

  /**
   * @deprecated 旧 API，保留以避免编译破坏；新代码请使用 saveLocationShareSettings
   */
  async saveLocationSettings(settings: LocationSettings): Promise<void> {
    const uid = this.getCurrentUserId();
    if (!uid) return;
    const current = this.getLocationShareSettings(uid);
    current.shareEnabled = settings.isSharing;
    current.notifyOnArrival = settings.homeNotification || settings.schoolNotification;
    await this.saveLocationShareSettings(uid, current);
  }

  /**
   * @deprecated 旧 API
   */
  getLocationSettings(): LocationSettings {
    const uid = this.getCurrentUserId();
    const s = this.getLocationShareSettings(uid);
    return {
      isSharing: s.shareEnabled,
      schoolNotification: s.notifyOnArrival,
      homeNotification: s.notifyOnArrival
    };
  }

  // ---- 常用地点 ----
  async saveLocationPlace(place: LocationPlace): Promise<void> {
    await this.saveItem('location_places', place);
  }

  async updateLocationPlace(place: LocationPlace): Promise<void> {
    await this.updateItem('location_places', place);
  }

  getLocationPlaces(): LocationPlace[] {
    const familyId = this.getCurrentFamilyId();
    let records: LocationPlace[];
    if (!familyId) {
      records = this.getList<LocationPlace>('location_places');
    } else {
      records = this.getList<LocationPlace>('location_places').filter(p => p.familyId === familyId || p.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId());
  }

  getLocationPlacesByMember(memberId: string): LocationPlace[] {
    return this.getLocationPlaces().filter(p => p.forMemberId === memberId);
  }

  getLocationPlacesByType(placeType: PlaceType): LocationPlace[] {
    return this.getLocationPlaces().filter(p => p.placeType === placeType);
  }

  async deleteLocationPlace(id: string): Promise<void> {
    await this.removeItem('location_places', id);
  }
}
