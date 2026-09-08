/**
 * 推送服务 - Push Kit 令牌注册 + 通知权限 + 通知偏好
 *
 * 流程：
 * 1. 请求通知权限（requestEnableNotification）
 * 2. 获取 Push Kit 令牌（pushService.getToken）
 * 3. 上传令牌到云端（register-push-token 云函数，含默认通知偏好）
 * 4. 通知偏好设置同步（set-notify-setting 云函数）
 *
 * 前置条件：AGC 控制台已开通推送服务（Push Kit）
 */
import pushService from "@hms.core.push.pushService";
import notificationManager from "@ohos.notificationManager";
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from "@ohos.hilog";
import { CloudService } from './CloudService';
import { LocalDbService } from './LocalDbService';
const DOMAIN = 0x0000;
const TAG = 'PushService';
/** 通知偏好存储 key */
const PREF_NOTIFY_ENABLED = 'notify_enabled';
const PREF_NOTIFY_MUTED_MODULES = 'notify_muted_modules';
const PREF_DEVICE_ID = 'push_device_id';
export class PushService {
  private static instance: PushService | null = null;
  private db: LocalDbService;
  private initialized: boolean = false;

  private constructor() {
    this.db = LocalDbService.getInstance();
    this.initialized = false;
  }

  static getInstance(): PushService {
    if (!PushService.instance) {
      PushService.instance = new PushService();
    }
    return PushService.instance;
  }

  /**
   * 初始化推送服务（在登录后、进入首页前调用）
   * 不阻塞主流程：失败仅降级，不影响应用使用
   */
  async init(): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    try {
      // 1) 请求通知权限（用户拒绝也不阻塞）
      const permGranted = await this.ensureNotificationPermission();
      hilog.info(DOMAIN, TAG, 'notification permission: %{public}s', permGranted ? 'granted' : 'denied');
      // 2) 获取 Push Kit 令牌
      const token = await this.getPushToken();
      if (token.length === 0) {
        hilog.warn(DOMAIN, TAG, 'Push Kit token not available (push service may not be enabled in AGC console)');
        return;
      }
      // 3) 上传令牌
      const deviceId = await this.getDeviceId();
      const enabledStr = this.db.getPrefs().getSync(PREF_NOTIFY_ENABLED, '1') as string;
      const familyId = this.db.getCurrentFamilyId();
      await this.uploadToken(token, deviceId, enabledStr !== '0', familyId);
      hilog.info(DOMAIN, TAG, 'Push service initialized: deviceId=%{public}s', deviceId);
    } catch (err) {
      // 推送失败不应影响应用正常使用
      hilog.warn(DOMAIN, TAG, 'Push service init failed: %{public}s', (err as Error).message);
    }
  }

  /** 请求通知权限 */
  async ensureNotificationPermission(): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification();
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'requestEnableNotification failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  /** 获取 Push Kit 令牌 */
  async getPushToken(): Promise<string> {
    try {
      const token = await pushService.getToken();
      hilog.info(DOMAIN, TAG, 'Push token obtained');
      return token;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getToken failed: code=%{public}d, msg=%{public}s',
        (err as BusinessError).code, (err as BusinessError).message);
      return '';
    }
  }

  /** 获取或生成设备标识（同设备换 token 去重用） */
  async getDeviceId(): Promise<string> {
    const p = this.db.getPrefs();
    let deviceId = p.getSync(PREF_DEVICE_ID, '') as string;
    if (deviceId.length === 0) {
      deviceId = `dev_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      await p.put(PREF_DEVICE_ID, deviceId);
      await p.flush();
    }
    return deviceId;
  }

  /** 上传令牌到云端 */
  async uploadToken(token: string, deviceId: string, notifyEnabled: boolean, familyId: string): Promise<void> {
    try {
      const cloud = CloudService.getInstance();
      const params: Record<string, Object> = {};
      params['token'] = token;
      params['deviceId'] = deviceId;
      params['notifyEnabled'] = notifyEnabled ? 1 : 0;
      if (familyId.length > 0) {
        params['familyId'] = familyId;
      }
      await cloud.callCloudFunction('register-push-token', params);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'uploadToken failed: %{public}s', (err as Error).message);
    }
  }

  /** 设置通知偏好（调用云函数同步） */
  async setNotifyEnabled(enabled: boolean, mutedModules: string[] = []): Promise<void> {
    const familyId = this.db.getCurrentFamilyId();
    if (familyId.length === 0) {
      hilog.warn(DOMAIN, TAG, 'setNotifyEnabled: no current family');
      return;
    }
    // 本地缓存
    const p = this.db.getPrefs();
    await p.put(PREF_NOTIFY_ENABLED, enabled ? '1' : '0');
    await p.put(PREF_NOTIFY_MUTED_MODULES, JSON.stringify(mutedModules));
    await p.flush();
    // 云端同步
    try {
      const cloud = CloudService.getInstance();
      const params: Record<string, Object> = {};
      params['familyId'] = familyId;
      params['enabled'] = enabled ? 1 : 0;
      params['mutedModules'] = mutedModules;
      await cloud.callCloudFunction('set-notify-setting', params);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setNotifyEnabled cloud sync failed: %{public}s', (err as Error).message);
    }
  }

  /** 获取本地通知偏好 */
  isNotifyEnabled(): boolean {
    const p = this.db.getPrefs();
    const val = p.getSync(PREF_NOTIFY_ENABLED, '1') as string;
    return val !== '0';
  }

  getMutedModules(): string[] {
    try {
      const p = this.db.getPrefs();
      const raw = p.getSync(PREF_NOTIFY_MUTED_MODULES, '[]') as string;
      const arr = JSON.parse(raw) as Object;
      if (Array.isArray(arr)) {
        return arr as string[];
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
