/**
 * 位置共享上报器（V2 真实共享）
 *
 * 职责：App 前台期间周期性把「我的最新位置」上报到云端（update-location 云函数），
 * 云端负责覆盖写 LocationShare 行 + 服务端到达检测 + 推送通知给能看到我的家人。
 *
 * 生命周期（EntryAbility 挂接）：
 *   - onForeground -> start()：启动 60s 周期上报
 *   - onBackground -> stop()：鸿蒙后台挂起，停止上报（家人看到「最后在线」）
 *
 * 三种上报形态：
 *   - reportNow()：开启共享/定位成功/范围变为可共享时补报；
 *     仅当「真正在共享」（同意 && 范围非 PRIVATE && 开关开）才执行
 *   - flushStatus()：暂停共享 / 范围改为「仅自己」时把新状态推上云；
 *     范围 PRIVATE 直接 op=delete 删行（无需坐标、云端行彻底消失=仅自己语义），
 *     暂停则 upsert shareEnabled=0（家人看到「已暂停」而非「未共享」）
 *   - deleteRemoteRow()：退出家庭时清理云端行（best-effort）
 *
 * 可靠性：关闭态未同步用持久化标记 cloudSharePending（设置内落盘），
 * flush 失败后由周期心跳重试，App 被杀重启后 tick 仍会补冲刷，
 * 避免「改仅自己/暂停」失败导致旧行（含坐标）跨重启长期残留可见。
 *
 * 合规：所有上报都要求本机已同意位置共享说明（location_consent）。
 */
import geoLocationManager from "@ohos.geoLocationManager";
import hilog from "@ohos.hilog";
import promptAction from "@ohos.promptAction";
import { CloudService } from './CloudService';
import { LocalDbService, LocationShareSettings } from './LocalDbService';
import { ModuleId, Visibility, ResolvedVisibility } from '../common/Constants';
const TAG = '[LocationReporter]';
const DOMAIN = 0x0000;
/** 上报周期：前台每 60 秒一次 */
const REPORT_INTERVAL_MS = 60 * 1000;

/** 设置补丁（保留式更新，未提供的字段保持原值） */
interface LocationPatch {
  shareEnabled?: boolean;
  notifyOnArrival?: boolean;
  lastLat?: number;
  lastLon?: number;
  lastReportAt?: number;
  cloudSharePending?: boolean;
}

/** 一次定位结果（简化 geoLocationManager.Location 的取值） */
interface LocationFix {
  latitude: number;
  longitude: number;
  accuracy: number;
}

export class LocationReporter {
  private static instance: LocationReporter | null = null;
  private db: LocalDbService;
  private cloud: CloudService;
  private timerId: number = -1;
  private running: boolean = false;
  private reporting: boolean = false;

  private constructor() {
    this.db = LocalDbService.getInstance();
    this.cloud = CloudService.getInstance();
    this.timerId = -1;
    this.running = false;
    this.reporting = false;
  }

  static getInstance(): LocationReporter {
    if (!LocationReporter.instance) {
      LocationReporter.instance = new LocationReporter();
    }
    return LocationReporter.instance;
  }

  /** EntryAbility.onForeground 调用；重复 start 幂等 */
  start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.timerId = setInterval(() => {
      this.tick().catch(() => {
      });
    }, REPORT_INTERVAL_MS);
    hilog.info(DOMAIN, TAG, 'started (every %{public}d ms)', REPORT_INTERVAL_MS);
    this.tick().catch(() => {
    });
  }

  /** EntryAbility.onBackground 调用 */
  stop(): void {
    this.running = false;
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    hilog.info(DOMAIN, TAG, 'stopped');
  }

  /** 周期心跳：有关闭态未同步（持久化标记）→ 先冲刷；否则真正共享时上报位置 */
  async tick(): Promise<void> {
    const uid = this.db.getCurrentUserId();
    const familyId = this.db.getCurrentFamilyId();
    if (!this.baseGateOpen(uid, familyId)) {
      return;
    }
    const scope = this.db.resolveModuleVisibilityForRecord(ModuleId.LOCATION);
    const settings = this.db.getLocationShareSettings(uid);
    const off = scope.visibility === Visibility.PRIVATE || !settings.shareEnabled;
    const pending = settings.cloudSharePending === true;
    if (off) {
      // 暂停/仅自己时：仅当有未同步的关闭态才补一次冲刷，平时静默（省电省流量）
      if (pending) {
        await this.flushStatus();
      }
      return;
    }
    if (pending) {
      await this.flushStatus(); // 重新开启后 pending 未清：flush 会走 upsert 建档并清标记
    }
    await this.reportNow();
  }

  /**
   * 立即补报位置（开启共享/定位成功/范围变可共享后调用）
   * 仅当「真正在共享」时执行；暂停/仅自己时不产生无意义心跳流量
   */
  async reportNow(lat?: number, lon?: number, accuracy?: number): Promise<boolean> {
    const uid = this.db.getCurrentUserId();
    const familyId = this.db.getCurrentFamilyId();
    if (!this.baseGateOpen(uid, familyId)) {
      return false;
    }
    const scope = this.db.resolveModuleVisibilityForRecord(ModuleId.LOCATION);
    const settings = this.db.getLocationShareSettings(uid);
    if (scope.visibility === Visibility.PRIVATE || !settings.shareEnabled) {
      return false;
    }
    return await this.performUpsert(uid, familyId, scope, settings, lat, lon, accuracy);
  }

  /**
   * 状态冲刷：暂停共享 / 共享范围改为「仅自己」时把新状态推上云
   * - 范围 PRIVATE → op=delete 删行（云端行彻底消失，「仅自己」最可靠语义，
   *   且不依赖定位；行删除后重新共享会新建一行，到达冷却重置）
   * - 仅暂停（开关关）→ upsert shareEnabled=0，家人看到「已暂停共享」
   * 只要求同意 + 家庭 + 云端可用；失败时 cloudSharePending 保持 true（已落盘），
   * 由后续心跳/重启后 tick 重试，杜绝旧行携坐标跨重启残留
   */
  async flushStatus(): Promise<boolean> {
    const uid = this.db.getCurrentUserId();
    const familyId = this.db.getCurrentFamilyId();
    if (!this.baseGateOpen(uid, familyId)) {
      return false;
    }
    const scope = this.db.resolveModuleVisibilityForRecord(ModuleId.LOCATION);
    const settings = this.db.getLocationShareSettings(uid);
    const off = scope.visibility === Visibility.PRIVATE || !settings.shareEnabled;
    if (!off) {
      // 非关闭态调用（如重新开启后清 pending 的建档冲刷）：等同一次补报，不落 pending
      return await this.performUpsert(uid, familyId, scope, settings);
    }
    await this.persistPatch(uid, { cloudSharePending: true });
    // 成功路径由 performXxx 统一清除 pending（含重新开启后的补报）
    return scope.visibility === Visibility.PRIVATE
      ? await this.performDelete(uid, familyId)
      : await this.performUpsert(uid, familyId, scope, settings);
  }

  /**
   * 页面/设置页在「用户操作产生关闭态」时调用：先落盘 pending 标记再冲刷，
   * 崩溃/杀进程也不丢（重启后 tick 依据标记补冲刷）
   */
  async scheduleFlush(): Promise<boolean> {
    const uid = this.db.getCurrentUserId();
    const familyId = this.db.getCurrentFamilyId();
    if (!this.baseGateOpen(uid, familyId)) {
      return false;
    }
    await this.persistPatch(uid, { cloudSharePending: true });
    return await this.flushStatus();
  }

  /** 退出家庭：best-effort 删除云端本成员行（须在删除 FamilyMember 前调用） */
  async deleteRemoteRow(familyId: string): Promise<void> {
    if (!this.cloud.isCloudAvailable() || familyId.length === 0) {
      return;
    }
    try {
      const params: Record<string, Object> = {};
      params['familyId'] = familyId;
      params['op'] = 'delete';
      await this.cloud.callCloudFunction('update-location', params);
      hilog.info(DOMAIN, TAG, 'deleteRemoteRow done for %{public}s', familyId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'deleteRemoteRow failed (non-blocking): %{public}s', (err as Error).message);
    }
  }

  /** 基础门槛：同意 + 家庭 + 云端（开关/范围由各调用方按语义决定） */
  baseGateOpen(uid: string, familyId: string): boolean {
    if (uid.length === 0 || familyId.length === 0) {
      return false;
    }
    if (!this.cloud.isCloudAvailable()) {
      return false;
    }
    const consent = this.db.getLocationConsent();
    if (consent === null || consent.userId !== uid) {
      return false;
    }
    return true;
  }

  async performDelete(uid: string, familyId: string): Promise<boolean> {
    if (this.reporting) {
      return false;
    }
    this.reporting = true;
    try {
      const params: Record<string, Object> = {};
      params['familyId'] = familyId;
      params['op'] = 'delete';
      const result = await this.cloud.callCloudFunction('update-location', params);
      if (result.code !== 0) {
        hilog.warn(DOMAIN, TAG, 'status delete rejected: code=%{public}d msg=%{public}s', result.code, result.message);
        return false;
      }
      await this.persistPatch(uid, { cloudSharePending: false });
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'status delete failed: %{public}s', (err as Error).message);
      return false;
    } finally {
      this.reporting = false;
    }
  }

  async performUpsert(uid: string, familyId: string, scope: ResolvedVisibility,
    settings: LocationShareSettings, lat?: number, lon?: number, accuracy?: number): Promise<boolean> {
    if (this.reporting) {
      return false; // 防重入（周期 + 即时补报竞态）
    }
    this.reporting = true;
    try {
      let useLat = lat;
      let useLon = lon;
      let useAccuracy = accuracy;
      if (useAccuracy === undefined) {
        useAccuracy = 0;
      }
      if (typeof useLat !== 'number' || typeof useLon !== 'number') {
        // 依次兜底：实时定位 → 上次成功上报的坐标（暂停时也能把状态推上去）
        const loc = await this.fetchCurrentLocation();
        if (loc !== null) {
          useLat = loc.latitude;
          useLon = loc.longitude;
          useAccuracy = loc.accuracy;
        } else if (settings.lastLat !== undefined && settings.lastLon !== undefined) {
          useLat = settings.lastLat;
          useLon = settings.lastLon;
          useAccuracy = 0;
        } else {
          return false;
        }
      }
      const params: Record<string, Object> = {};
      params['familyId'] = familyId;
      params['lat'] = useLat;
      params['lon'] = useLon;
      params['accuracy'] = useAccuracy;
      params['op'] = 'upsert';
      params['visibility'] = scope.visibility;
      params['visibleMembers'] = scope.visibleMembers;
      params['shareEnabled'] = settings.shareEnabled;
      params['arrivalNotifyEnabled'] = settings.notifyOnArrival;
      const result = await this.cloud.callCloudFunction('update-location', params);
      if (result.code !== 0) {
        hilog.warn(DOMAIN, TAG, 'upload rejected: code=%{public}d msg=%{public}s', result.code, result.message);
        return false;
      }
      await this.persistPatch(uid, {
        lastLat: useLat,
        lastLon: useLon,
        lastReportAt: Date.now(),
        cloudSharePending: false
      });
      // 服务端到达检测命中 → 本地轻提示（真实通知由云端推给家人）
      const data = result.data;
      if (data !== undefined && data !== null) {
        const map = data as Record<string, Object>;
        const ph = map['placesHit'];
        if (Array.isArray(ph) && ph.length > 0) {
          const hits = ph as string[];
          promptAction.showToast({ message: `已到达「${hits[0]}」`, duration: 1500 });
        }
      }
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'upload failed: %{public}s', (err as Error).message);
      return false;
    } finally {
      this.reporting = false;
    }
  }

  /** 保留式补丁写设置（不清其他字段），失败仅告警 */
  async persistPatch(uid: string, patch: LocationPatch): Promise<void> {
    try {
      const cur = this.db.getLocationShareSettings(uid);
      const next: LocationShareSettings = {
        shareEnabled: patch.shareEnabled !== undefined ? patch.shareEnabled : cur.shareEnabled,
        visibility: cur.visibility,
        visibleMembers: cur.visibleMembers,
        notifyOnArrival: patch.notifyOnArrival !== undefined ? patch.notifyOnArrival : cur.notifyOnArrival,
        lastNotifiedAt: cur.lastNotifiedAt,
        lastLat: patch.lastLat !== undefined ? patch.lastLat : cur.lastLat,
        lastLon: patch.lastLon !== undefined ? patch.lastLon : cur.lastLon,
        lastReportAt: patch.lastReportAt !== undefined ? patch.lastReportAt : cur.lastReportAt,
        cloudSharePending: patch.cloudSharePending !== undefined ? patch.cloudSharePending : cur.cloudSharePending
      };
      await this.db.saveLocationShareSettings(uid, next);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'persistPatch failed: %{public}s', (e as Error).message);
    }
  }

  async fetchCurrentLocation(): Promise<LocationFix | null> {
    try {
      const loc = await geoLocationManager.getCurrentLocation();
      const acc = loc.accuracy;
      const result: LocationFix = {
        latitude: loc.latitude,
        longitude: loc.longitude,
        accuracy: acc === undefined ? 0 : acc
      };
      return result;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getCurrentLocation failed: %{public}s', (err as Error).message);
      return null;
    }
  }
}
