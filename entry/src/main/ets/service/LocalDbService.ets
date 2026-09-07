/**
 * 本地数据库服务 - 云端优先架构的本地缓存层
 *
 * 架构：云端优先（Cloud-first）+ 本地缓存
 * - 所有写操作：先写本地缓存，再异步通过 CloudService 推送到云端
 * - 所有读操作：从本地缓存读取（后台由 CloudService 定期从云端拉取合并）
 * - 登录恢复：新设备/重装后登录 → CloudService 从云端全量拉取 → syncFromCloud 写入本地
 *
 * 推送是自动的：每个 save/update/delete 方法内部都会调用 pushToCloud()，
 * ViewModel 和页面代码无需关心云端同步。
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CloudService } from './CloudService';
import { toCloudType, toLocalKey } from '../common/CloudTypes';
import { FamilyMember } from '../model/FamilyMember';
import { Family } from '../model/Family';
import { PeriodRecord, IntimacyRecord, PeriodReminderSettings } from '../model/PeriodRecord';
import { Medication, MedicationLog } from '../model/Medication';
import { KidEvent, GrowthRecord } from '../model/KidEvent';
import { Reminder } from '../model/Reminder';
import { HealthMetric } from '../model/HealthMetric';
import { ShoppingItem } from '../model/ShoppingItem';
import { Photo } from '../model/Photo';
import { PhotoComment } from '../model/PhotoComment';
import { Memo } from '../model/Memo';
import { FamilyInvitation } from '../model/FamilyInvitation';
import { AccountingRecord, Budget } from '../model/AccountingRecord';
import { LocationPlace, PlaceType } from '../model/LocationPlace';
import { ModuleId, ModuleVisibility, ResolvedVisibility, ThemeColor, EmojiStyle, Visibility, MemberStatus } from '../common/Constants';
import { filterByVisibility, formatDate, isRecordCreator as isCreatorOf, toLocalDateKey } from '../common/Utils';

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
  /** 上次成功上报坐标（LocationReporter 维护）：暂停共享时实时定位不可用则用其兜底推关闭态 */
  lastLat?: number;
  lastLon?: number;
  lastReportAt?: number;
  /** 关闭态（暂停/仅自己）尚未成功同步到云端（LocationReporter 维护，跨重启持久） */
  cloudSharePending?: boolean;
}

export interface ArrivalNotificationRecord {
  placeId: string;
  notifiedAt: number;
}

/** 位置共享隐私同意记录（本机，按当前用户；退出/登出时清除，重新确认） */
export interface LocationConsent {
  userId: string;
  grantedAt: number;
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

  /** 获取 Preferences 实例（供 PushService 等外部服务使用） */
  getPrefs(): PrefStore {
    return this.ensurePrefs();
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

  /** 通用布尔设置（UI 记忆类，如页面视图密度），键加 setting_ 前缀与业务列表隔离 */
  async saveSetting(key: string, value: boolean): Promise<void> {
    const p = this.ensurePrefs();
    const k = 'setting_' + key;
    this.writeCache.set(k, value ? '1' : '0');
    await p.put(k, value ? '1' : '0');
    await p.flush();
  }

  getSetting(key: string, defValue: boolean): boolean {
    const k = 'setting_' + key;
    const cached = this.writeCache.get(k);
    const raw = cached ?? this.ensurePrefs().getSync(k, defValue ? '1' : '0') as string;
    return raw === '1';
  }

  // TODO(V2): 迁移到 RelationalStore 后改为异步 async getList
  getList<T>(key: string): T[] {
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
    this.pushToCloud('families', family, 1);
  }

  getFamilies(): Family[] {
    return this.getList<Family>('families');
  }

  getCurrentFamily(): Family | null {
    const userId = this.getCurrentUserId();
    const families = this.getFamilies();

    // 当前无已登录用户或家庭列表为空时，不返回任何家庭
    if (!userId || families.length === 0) {
      return null;
    }

    // 优先返回当前用户所属的家庭（支持多账号切换场景）
    const members = this.getMembers();
    const memberRecord = members.find(m => m.userId === userId && m.status === MemberStatus.ACTIVE);
    if (memberRecord) {
      const family = families.find(f => f.id === memberRecord.familyId);
      if (family) return family;
    }

    // 其次查找以当前用户为创建者的家庭
    const ownedFamily = families.find(f => f.creatorId === userId);
    if (ownedFamily) return ownedFamily;

    // 兜底：返回第一个家庭（单家庭场景）
    return families[0];
  }

  /** 获取当前家庭ID，若未加入家庭则返回空字符串 */
  getCurrentFamilyId(): string {
    const family = this.getCurrentFamily();
    return family?.id ?? '';
  }

  /**
   * 获取当前用户在当前家庭中的成员ID（FamilyMember.id）
   *
   * 用于记录的 creatorId 字段：新格式存 memberId 而非 openID，
   * 这样退出家庭后重新加入（获得新 memberId）时，旧记录的 creatorId 不再匹配，
   * 实现角色级隐私隔离。
   */
  getCurrentMemberId(): string {
    const userId = this.getCurrentUserId();
    if (!userId) return '';
    const members = this.getMembers();
    const member = members.find(m => m.userId === userId && m.status === MemberStatus.ACTIVE);
    return member?.id ?? '';
  }

  /**
   * 判断当前用户是否为某条记录的创建者
   *
   * 兼容两种 creatorId 格式：
   * - 新格式（mem_xxx）：FamilyMember.id，角色级标识
   * - 旧格式（openID）：华为账号 openID，账号级标识
   */
  isRecordCreator(creatorId: string): boolean {
    return isCreatorOf(creatorId, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  // ---- 家庭成员 ----
  async saveMember(member: FamilyMember): Promise<void> {
    await this.saveItem('members', member);
    this.pushToCloud('members', member, 1);
  }

  async updateMember(member: FamilyMember): Promise<void> {
    await this.updateItem('members', member);
    this.pushToCloud('members', member, 1);
  }

  async removeMember(id: string): Promise<void> {
    const members = this.getList<FamilyMember>('members');
    const member = members.find(m => m.id === id);
    await this.removeItem('members', id);
    if (member) {
      member.isDeleted = true;
      this.pushToCloud('members', member, 1, 'delete');
    }
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
    this.pushToCloud('period_records', record, record.version);
  }

  getPeriodRecords(): PeriodRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: PeriodRecord[];
    if (!familyId) {
      records = this.getList<PeriodRecord>('period_records');
    } else {
      records = this.getList<PeriodRecord>('period_records').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  async deletePeriodRecord(id: string): Promise<void> {
    const records = this.getList<PeriodRecord>('period_records');
    const record = records.find(r => r.id === id);
    await this.removeItem('period_records', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('period_records', record, record.version + 1, 'delete');
    }
  }

  async updatePeriodRecord(record: PeriodRecord): Promise<void> {
    await this.updateItem('period_records', record);
    this.pushToCloud('period_records', record, record.version);
  }

  async deleteIntimacyRecord(id: string): Promise<void> {
    const records = this.getList<IntimacyRecord>('intimacy_records');
    const record = records.find(r => r.id === id);
    await this.removeItem('intimacy_records', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('intimacy_records', record, record.version + 1, 'delete');
    }
  }

  // ---- 啪啪记录 ----
  async saveIntimacyRecord(record: IntimacyRecord): Promise<void> {
    await this.saveItem('intimacy_records', record);
    this.pushToCloud('intimacy_records', record, record.version);
  }

  getIntimacyRecords(): IntimacyRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: IntimacyRecord[];
    if (!familyId) {
      records = this.getList<IntimacyRecord>('intimacy_records');
    } else {
      records = this.getList<IntimacyRecord>('intimacy_records').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  // ---- 用药 ----
  async saveMedication(med: Medication): Promise<void> {
    await this.saveItem('medications', med);
    this.pushToCloud('medications', med, med.version);
  }

  async updateMedication(med: Medication): Promise<void> {
    await this.updateItem('medications', med);
    this.pushToCloud('medications', med, med.version);
  }

  getMedications(): Medication[] {
    const familyId = this.getCurrentFamilyId();
    let records: Medication[];
    if (!familyId) {
      records = this.getList<Medication>('medications');
    } else {
      records = this.getList<Medication>('medications').filter(m => m.familyId === familyId || m.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  getMedicationsByMember(memberId: string): Medication[] {
    return this.getMedications().filter(m => m.forMemberId === memberId);
  }

  async deleteMedication(id: string): Promise<void> {
    const records = this.getList<Medication>('medications');
    const record = records.find(r => r.id === id);
    await this.removeItem('medications', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('medications', record, record.version + 1, 'delete');
    }
  }

  // ---- 服药记录 ----
  async saveMedicationLog(log: MedicationLog): Promise<void> {
    await this.saveItem('medication_logs', log);
    this.pushToCloud('medication_logs', log, log.version);
  }

  getMedicationLogs(): MedicationLog[] {
    const familyId = this.getCurrentFamilyId();
    let records: MedicationLog[];
    if (!familyId) {
      records = this.getList<MedicationLog>('medication_logs');
    } else {
      records = this.getList<MedicationLog>('medication_logs').filter(l => l.familyId === familyId || l.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  getTodayLogs(): MedicationLog[] {
    const today = formatDate(new Date());
    // takenAt 存 UTC ISO，须先转本地日期再匹配（凌晨 0-8 点直接 startsWith 会漏掉今日记录）
    return this.getMedicationLogs().filter(l => toLocalDateKey(l.takenAt) === today);
  }

  async deleteMedicationLog(id: string): Promise<void> {
    const records = this.getList<MedicationLog>('medication_logs');
    const record = records.find(r => r.id === id);
    await this.removeItem('medication_logs', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('medication_logs', record, record.version + 1, 'delete');
    }
  }

  /** 删除某药物某时间段的今日服药记录 */
  async deleteTodayMedicationLog(medicationId: string, timeSlot: string): Promise<void> {
    const today = formatDate(new Date());
    const allLogs = this.getList<MedicationLog>('medication_logs');
    const toDelete = allLogs.find(l =>
      l.medicationId === medicationId && l.timeSlot === timeSlot && toLocalDateKey(l.takenAt) === today);
    const remaining = allLogs.filter(l =>
      !(l.medicationId === medicationId && l.timeSlot === timeSlot && toLocalDateKey(l.takenAt) === today)
    );
    await this.saveList('medication_logs', remaining);
    if (toDelete) {
      toDelete.isDeleted = true;
      this.pushToCloud('medication_logs', toDelete, toDelete.version + 1, 'delete');
    }
  }

  // ---- 健康指标 ----
  async saveHealthMetric(metric: HealthMetric): Promise<void> {
    await this.saveItem('health_metrics', metric);
    this.pushToCloud('health_metrics', metric, metric.version);
  }

  async updateHealthMetric(metric: HealthMetric): Promise<void> {
    await this.updateItem('health_metrics', metric);
    this.pushToCloud('health_metrics', metric, metric.version);
  }

  getHealthMetrics(): HealthMetric[] {
    const familyId = this.getCurrentFamilyId();
    let records: HealthMetric[];
    if (!familyId) {
      records = this.getList<HealthMetric>('health_metrics');
    } else {
      records = this.getList<HealthMetric>('health_metrics').filter(m => m.familyId === familyId || m.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  getHealthMetricsByMember(memberId: string): HealthMetric[] {
    return this.getHealthMetrics().filter(m => m.forMemberId === memberId);
  }

  async deleteHealthMetric(id: string): Promise<void> {
    const records = this.getList<HealthMetric>('health_metrics');
    const record = records.find(r => r.id === id);
    await this.removeItem('health_metrics', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('health_metrics', record, record.version + 1, 'delete');
    }
  }

  // ---- 孩子事项 ----
  async saveKidEvent(event: KidEvent): Promise<void> {
    await this.saveItem('kid_events', event);
    this.pushToCloud('kid_events', event, event.version);
  }

  async updateKidEvent(event: KidEvent): Promise<void> {
    await this.updateItem('kid_events', event);
    this.pushToCloud('kid_events', event, event.version);
  }

  getKidEvents(): KidEvent[] {
    const familyId = this.getCurrentFamilyId();
    let records: KidEvent[];
    if (!familyId) {
      records = this.getList<KidEvent>('kid_events');
    } else {
      records = this.getList<KidEvent>('kid_events').filter(e => e.familyId === familyId || e.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  getKidEventsByMember(memberId: string): KidEvent[] {
    return this.getKidEvents().filter(e => e.forMemberId === memberId);
  }

  async deleteKidEvent(id: string): Promise<void> {
    const records = this.getList<KidEvent>('kid_events');
    const record = records.find(r => r.id === id);
    await this.removeItem('kid_events', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('kid_events', record, record.version + 1, 'delete');
    }
  }

  // ---- 成长记录 ----
  async saveGrowthRecord(record: GrowthRecord): Promise<void> {
    await this.saveItem('growth_records', record);
    this.pushToCloud('growth_records', record, record.version);
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
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  async updateGrowthRecord(record: GrowthRecord): Promise<void> {
    await this.updateItem('growth_records', record);
    this.pushToCloud('growth_records', record, record.version);
  }

  async deleteGrowthRecord(id: string): Promise<void> {
    const records = this.getList<GrowthRecord>('growth_records');
    const record = records.find(r => r.id === id);
    await this.removeItem('growth_records', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('growth_records', record, record.version + 1, 'delete');
    }
  }

  // ---- 提醒事项 ----
  async saveReminder(reminder: Reminder): Promise<void> {
    await this.saveItem('reminders', reminder);
    this.pushToCloud('reminders', reminder, reminder.version);
  }

  async updateReminder(reminder: Reminder): Promise<void> {
    await this.updateItem('reminders', reminder);
    this.pushToCloud('reminders', reminder, reminder.version);
  }

  getReminders(): Reminder[] {
    const familyId = this.getCurrentFamilyId();
    let records: Reminder[];
    if (!familyId) {
      records = this.getList<Reminder>('reminders');
    } else {
      records = this.getList<Reminder>('reminders').filter(r => r.familyId === familyId || r.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  async deleteReminder(id: string): Promise<void> {
    const records = this.getList<Reminder>('reminders');
    const record = records.find(r => r.id === id);
    await this.removeItem('reminders', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('reminders', record, record.version + 1, 'delete');
    }
  }

  // ---- 购物清单 ----
  async saveShoppingItem(item: ShoppingItem): Promise<void> {
    await this.saveItem('shopping_items', item);
    this.pushToCloud('shopping_items', item, item.version);
  }

  async updateShoppingItem(item: ShoppingItem): Promise<void> {
    await this.updateItem('shopping_items', item);
    this.pushToCloud('shopping_items', item, item.version);
  }

  getShoppingItems(): ShoppingItem[] {
    const familyId = this.getCurrentFamilyId();
    let records: ShoppingItem[];
    if (!familyId) {
      records = this.getList<ShoppingItem>('shopping_items');
    } else {
      records = this.getList<ShoppingItem>('shopping_items').filter(i => i.familyId === familyId || i.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  async deleteShoppingItem(id: string): Promise<void> {
    const records = this.getList<ShoppingItem>('shopping_items');
    const record = records.find(r => r.id === id);
    await this.removeItem('shopping_items', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('shopping_items', record, record.version + 1, 'delete');
    }
  }

  // ---- 家庭相册 ----
  async savePhoto(photo: Photo): Promise<void> {
    await this.saveItem('photos', photo);
    this.pushToCloud('photos', photo, photo.version);
  }

  getPhotos(): Photo[] {
    const familyId = this.getCurrentFamilyId();
    let records: Photo[];
    if (!familyId) {
      records = this.getList<Photo>('photos');
    } else {
      records = this.getList<Photo>('photos').filter(p => p.familyId === familyId || p.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  async updatePhoto(photo: Photo): Promise<void> {
    await this.updateItem('photos', photo);
    this.pushToCloud('photos', photo, photo.version);
  }

  async deletePhoto(id: string): Promise<void> {
    const records = this.getList<Photo>('photos');
    const record = records.find(r => r.id === id);
    await this.removeItem('photos', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('photos', record, record.version + 1, 'delete');
    }
  }

  // ---- 照片互动（点赞/评论） ----
  async savePhotoComment(comment: PhotoComment): Promise<void> {
    await this.saveItem('photo_comments', comment);
    this.pushToCloud('photo_comments', comment, comment.version);
  }

  getPhotoComments(photoId: string): PhotoComment[] {
    const familyId = this.getCurrentFamilyId();
    let records: PhotoComment[];
    if (!familyId) {
      records = this.getList<PhotoComment>('photo_comments');
    } else {
      records = this.getList<PhotoComment>('photo_comments')
        .filter(c => c.familyId === familyId || c.familyId === '');
    }
    const visible = filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
    return visible.filter(c => c.photoId === photoId);
  }

  async deletePhotoComment(id: string): Promise<void> {
    const records = this.getList<PhotoComment>('photo_comments');
    const record = records.find(r => r.id === id);
    await this.removeItem('photo_comments', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('photo_comments', record, record.version + 1, 'delete');
    }
  }

  // ---- 家庭备忘 ----
  async saveMemo(memo: Memo): Promise<void> {
    await this.saveItem('memos', memo);
    this.pushToCloud('memos', memo, memo.version);
  }

  async updateMemo(memo: Memo): Promise<void> {
    await this.updateItem('memos', memo);
    this.pushToCloud('memos', memo, memo.version);
  }

  getMemos(): Memo[] {
    const familyId = this.getCurrentFamilyId();
    let records: Memo[];
    if (!familyId) {
      records = this.getList<Memo>('memos');
    } else {
      records = this.getList<Memo>('memos').filter(m => m.familyId === familyId || m.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  async deleteMemo(id: string): Promise<void> {
    const records = this.getList<Memo>('memos');
    const record = records.find(r => r.id === id);
    await this.removeItem('memos', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('memos', record, record.version + 1, 'delete');
    }
  }

  // ---- 邀请 ----
  async saveInvitation(inv: FamilyInvitation): Promise<void> {
    await this.saveItem('invitations', inv);
    this.pushToCloud('invitations', inv, 1);
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

  /**
   * 解析模块共享配置为单条记录的可见性字段。
   *
   * 关键转换：SettingsPage 里存的是「成员ID」(FamilyMember.id)，
   * 但记录的 visibleMembers 字段需要存「用户ID」(userId)，
   * 这样 filterByVisibility 才能用 currentUserId 正确匹配。
   *
   * 无配置时回退到 fallback（默认 FAMILY，与历史行为一致）。
   */
  resolveModuleVisibilityForRecord(moduleId: ModuleId, fallback: Visibility = Visibility.FAMILY): ResolvedVisibility {
    const cfg = this.getModuleVisibilityConfig(moduleId);
    if (!cfg) {
      const result: ResolvedVisibility = { visibility: fallback, visibleMembers: [] };
      return result;
    }
    if (cfg.visibility !== Visibility.SELECTED) {
      const result: ResolvedVisibility = { visibility: cfg.visibility, visibleMembers: [] };
      return result;
    }
    const family = this.getCurrentFamily();
    const allMembers = family ? this.getMembersByFamilyId(family.id) : [];
    const userIds: string[] = [];
    for (const memberId of cfg.visibleMemberIds) {
      const m = allMembers.find(mm => mm.id === memberId);
      if (m && m.userId) userIds.push(m.userId);
    }
    const result: ResolvedVisibility = { visibility: Visibility.SELECTED, visibleMembers: userIds };
    return result;
  }

  async removeModuleVisibilityConfig(moduleId: ModuleId): Promise<void> {
    const configs = this.getModuleVisibilityConfigs();
    await this.saveList('module_visibility_configs', configs.filter(c => c.moduleId !== moduleId));
  }

  /**
   * 模块对应的本地存储 key 列表（仅「无 per-record 分享选择器」的模块）。
   *
   * 这些模块的记录始终跟随模块共享配置，所以改配置时需要回填到已存在的记录。
   * Reminder/Memo 有 per-record 选择器，用户已为每条记录单独选过可见性，不强制覆盖。
   * Period 跟随模块配置、Shopping 已合并到 Reminder 不在此处理。
   */
  private static MODULE_LOCAL_KEYS: Record<string, string[]> = {
    'accounting': ['accounting_records'],
    'album': ['photos', 'photo_comments'],
    'kids': ['kid_events', 'growth_records'],
    'health': ['medications', 'medication_logs', 'health_metrics'],
    'location': ['location_places'],
    'reminder': [],
    'memo': [],
    'period': ['period_records', 'intimacy_records'],
    'shopping': []
  };

  /**
   * 将模块共享配置回填到当前用户已存在的所有该模块记录。
   *
   * 背景：模块共享配置只影响「新建记录」时的 visibility 默认值，已存在的记录保留
   * 创建时的 visibility。如果用户从默认 FAMILY 改成 PRIVATE，旧记录仍是 FAMILY，
   * 后加入的成员拉取云端数据后仍能看到这些记录（filterByVisibility 对 FAMILY 一律放行）。
   *
   * 本方法在用户保存模块共享配置时调用，把当前用户创建的所有该模块记录的
   * visibility/visibleMembers 同步到新配置，并 bump version 推送云端，确保其他
   * 设备下次同步时拿到新的 visibility。
   *
   * 仅回填无 per-record 选择器的模块；Reminder/Memo 跳过。
   *
   * @returns 更新的记录数
   */
  async applyModuleVisibilityToExistingRecords(moduleId: ModuleId): Promise<number> {
    const localKeys = LocalDbService.MODULE_LOCAL_KEYS[moduleId as string] ?? [];
    if (localKeys.length === 0) return 0;

    const userId = this.getCurrentUserId();
    if (!userId) return 0;

    const vis = this.resolveModuleVisibilityForRecord(moduleId);
    const now = new Date().toISOString();
    const newVisStr = vis.visibility as string;
    const newVisibleMembersStr = JSON.stringify(vis.visibleMembers);
    let totalUpdated = 0;

    for (let li = 0; li < localKeys.length; li++) {
      const localKey = localKeys[li];
      const records = this.getList<object>(localKey);
      let changed = false;

      for (let ri = 0; ri < records.length; ri++) {
        const r = records[ri] as Record<string, Object>;
        const creatorId = r['creatorId'] as string;
        if (!this.isRecordCreator(creatorId)) continue;

        const oldVis = r['visibility'] as string;
        const oldVisibleMembers = r['visibleMembers'];
        const oldVisibleMembersStr = JSON.stringify(oldVisibleMembers ?? []);
        if (oldVis === newVisStr && oldVisibleMembersStr === newVisibleMembersStr) continue;

        r['visibility'] = newVisStr;
        r['visibleMembers'] = vis.visibleMembers;
        const oldVersion = (r['version'] as number) ?? 1;
        const newVersion = oldVersion + 1;
        r['version'] = newVersion;
        r['updatedAt'] = now;
        changed = true;
        totalUpdated++;

        this.pushToCloud(localKey, records[ri], newVersion);
      }

      if (changed) {
        await this.saveList<object>(localKey, records);
      }
    }

    if (totalUpdated > 0) {
      hilog.info(0x0000, 'LocalDbService',
        'applyModuleVisibilityToExistingRecords: module=%{public}s vis=%{public}s updated=%{public}d',
        moduleId, newVisStr, totalUpdated);
    }
    return totalUpdated;
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

  // ---- 华为账号 unionID（跨应用唯一标识，用于"我的"页展示账号身份）----
  async saveHuaweiUnionId(unionId: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('huawei_union_id', unionId);
    await p.flush();
  }

  getHuaweiUnionId(): string {
    const p = this.ensurePrefs();
    return p.getSync('huawei_union_id', '') as string;
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
      return { remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false, recordSelf: false };
    }
    try {
      return JSON.parse(raw) as PeriodReminderSettings;
    } catch (_) {
      return { remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false, recordSelf: false };
    }
  }

  // ---- 姨妈页查看的归属主体记忆（仅查看家人模式下记住上次看的成员）----
  async savePeriodViewSubject(subjectId: string): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('period_view_subject', subjectId);
    await p.flush();
  }

  getPeriodViewSubject(): string {
    const p = this.ensurePrefs();
    return p.getSync('period_view_subject', '') as string;
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
    this.pushToCloud('accounting_records', record, record.version);
  }

  getAccountingRecords(): AccountingRecord[] {
    const familyId = this.getCurrentFamilyId();
    let records: AccountingRecord[];
    if (!familyId) {
      records = this.getList<AccountingRecord>('accounting_records');
    } else {
      records = this.getList<AccountingRecord>('accounting_records').filter(r => r.familyId === familyId || r.familyId === '');
    }
    const visible = filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
    // 云端 Float/Integer 字段可能以字符串返回（如 amount:"5000"、version:"1"），读取时归一化：
    // 否则 "100"+"200"="100200" 串接污染统计、toFixed 渲染崩溃、version+1 变成字符串拼接
    for (const r of visible) {
      const amt = Number(r.amount);
      r.amount = Number.isFinite(amt) ? amt : 0;
      const ver = Number(r.version);
      r.version = Number.isFinite(ver) ? ver : 1;
    }
    return visible;
  }

  async updateAccountingRecord(record: AccountingRecord): Promise<void> {
    await this.updateItem('accounting_records', record);
    this.pushToCloud('accounting_records', record, record.version);
  }

  async deleteAccountingRecord(id: string): Promise<void> {
    const records = this.getList<AccountingRecord>('accounting_records');
    const record = records.find(r => r.id === id);
    await this.removeItem('accounting_records', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('accounting_records', record, record.version + 1, 'delete');
    }
  }

  // ---- 预算 ----
  async saveBudget(budget: Budget): Promise<void> {
    const budgets = this.getList<Budget>('budgets');
    const idx = budgets.findIndex(b => b.year === budget.year && b.month === budget.month);
    const updated = idx >= 0
      ? [...budgets.slice(0, idx), budget, ...budgets.slice(idx + 1)]
      : [...budgets, budget];
    await this.saveList('budgets', updated);
    this.pushToCloud('budgets', budget, 1);
  }

  getBudget(year: number, month: number): Budget | null {
    const familyId = this.getCurrentFamilyId();
    if (!familyId) return null;
    const budgets = this.getList<Budget>('budgets');
    for (const b of budgets) {
      // 云端 Budget 的 year/month/amount 可能以字符串返回（服务端 SDK 泛型对象不做类型转换），
      // Number 归一化匹配 + 返回值，避免旧数据匹配失败（预算隐身）或渲染 toFixed 崩溃
      if (Number(b.year) === year && Number(b.month) === month && b.familyId === familyId) {
        const amt = Number(b.amount);
        return {
          id: b.id, familyId: b.familyId, year: Number(b.year), month: Number(b.month),
          amount: Number.isFinite(amt) ? amt : 0, createdAt: b.createdAt, updatedAt: b.updatedAt
        };
      }
    }
    return null;
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

  // ---- 云端同步辅助方法 ----

  /**
   * 静默推送数据变更到云端（fire-and-forget）
   *
   * 在每个 save/update/delete 方法末尾自动调用，ViewModel 无需关心。
   * 推送失败不影响本地功能，操作会进入 CloudService 的重试队列。
   *
   * @param localType - 本地存储 key（如 'period_records'）
   * @param data - 要推送的数据对象
   * @param version - 数据版本号
   * @param op - 操作类型：'upsert' 或 'delete'
   */
  private pushToCloud(localType: string, data: object, version: number, op: 'upsert' | 'delete' = 'upsert'): void {
    try {
      const cloud = CloudService.getInstance();
      if (!cloud.isCloudAvailable()) return;
      const cloudType = toCloudType(localType);
      // 不 await —— 调用方不关心推送结果
      cloud.push(cloudType, data, version, op).then(ok => {
        if (ok) {
          hilog.debug(0x0000, 'LocalDbService', 'pushToCloud: %{public}s %{public}s ok', cloudType, op);
        }
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'LocalDbService', 'pushToCloud: %{public}s %{public}s failed: %{public}s',
          cloudType, op, err.message);
      });
    } catch (err) {
      // 推送失败不应影响本地操作
      hilog.warn(0x0000, 'LocalDbService', 'pushToCloud error: %{public}s', (err as Error).message);
    }
  }

  /**
   * 从云端拉取的数据批量写入本地缓存
   *
   * 用于登录后全量恢复数据。直接覆写本地列表，不做合并（由 CloudService.mergeToLocal 负责合并逻辑）。
   *
   * @param cloudData - 云端快照数据，key 为云端类型名（如 'PeriodRecord'），value 为记录数组
   */
  async syncFromCloud(cloudData: Record<string, object[]>): Promise<void> {
    hilog.info(0x0000, 'LocalDbService', 'syncFromCloud: %{public}d types',
      Object.keys(cloudData).length);

    const cloudDataKeys = Object.keys(cloudData);
    for (let ci = 0; ci < cloudDataKeys.length; ci++) {
      const cloudType = cloudDataKeys[ci];
      const records = cloudData[cloudType];
      const localKey = toLocalKey(cloudType);
      if (localKey && localKey !== cloudType && Array.isArray(records)) {
        await this.saveList(localKey, records);
        hilog.info(0x0000, 'LocalDbService', 'syncFromCloud: %{public}s → %{public}d records',
          localKey, records.length);
      }
    }
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
      'shopping_items', 'photos', 'photo_comments', 'memos', 'invitations',
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
      'location_settings', 'location_share_map', 'location_consent', 'dismissed_today_date',
      'huawei_union_id', 'dismissed_today_ids'
    ];
    for (const key of scalarKeys) {
      await p.delete(key);
    }
    await p.flush();
  }

  // ---- 位置共享隐私同意（华为合规：首次开启位置共享前须用户明确同意） ----
  /**
   * 读取本机同意记录；无记录 = 从未同意（首次开启共享前必须弹说明框）
   */
  getLocationConsent(): LocationConsent | null {
    const p = this.ensurePrefs();
    const raw = p.getSync('location_consent', '') as string;
    if (!raw) return null;
    try {
      return JSON.parse(raw) as LocationConsent;
    } catch (_) {
      return null;
    }
  }

  async saveLocationConsent(consent: LocationConsent): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('location_consent', JSON.stringify(consent));
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
    this.pushToCloud('location_places', place, place.version);
  }

  async updateLocationPlace(place: LocationPlace): Promise<void> {
    await this.updateItem('location_places', place);
    this.pushToCloud('location_places', place, place.version);
  }

  getLocationPlaces(): LocationPlace[] {
    const familyId = this.getCurrentFamilyId();
    let records: LocationPlace[];
    if (!familyId) {
      records = this.getList<LocationPlace>('location_places');
    } else {
      records = this.getList<LocationPlace>('location_places').filter(p => p.familyId === familyId || p.familyId === '');
    }
    return filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
  }

  getLocationPlacesByMember(memberId: string): LocationPlace[] {
    return this.getLocationPlaces().filter(p => p.forMemberId === memberId);
  }

  getLocationPlacesByType(placeType: PlaceType): LocationPlace[] {
    return this.getLocationPlaces().filter(p => p.placeType === placeType);
  }

  async deleteLocationPlace(id: string): Promise<void> {
    const records = this.getList<LocationPlace>('location_places');
    const record = records.find(r => r.id === id);
    await this.removeItem('location_places', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('location_places', record, record.version + 1, 'delete');
    }
  }

  // ---- 隐私政策同意状态 ----
  async savePrivacyAgreed(agreed: boolean): Promise<void> {
    const p = this.ensurePrefs();
    await p.put('privacy_agreed', agreed ? 'true' : 'false');
    await p.flush();
  }

  isPrivacyAgreed(): boolean {
    const p = this.ensurePrefs();
    return p.getSync('privacy_agreed', 'false') === 'true';
  }
}
