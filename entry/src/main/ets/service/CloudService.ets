/**
 * 云端同步服务 - 对接华为云 AGC (AppGallery Connect)
 *
 * 架构：云端优先（Cloud-first）+ 本地缓存
 * - 写操作：先写本地缓存，再异步通过云函数推送到 Cloud DB
 * - 读操作：优先读本地缓存，后台从 Cloud DB 拉取最新数据合并
 * - 登录恢复：新设备/重装后登录 → 从 Cloud DB 全量拉取 → 写入本地缓存
 * - 冲突解决：版本号校验 + 最后修改时间优先
 *
 * 使用的 AGC 服务：
 * - Cloud Function (cloudFunction)：所有 Cloud DB 读写通过云函数完成
 * - Cloud Storage (cloudStorage)：照片/文件存储
 *
 * 注意：不直接使用 Cloud DB 客户端 SDK（需 AGC 生成模型类），
 * 而是通过已部署的 push-data / pull-data 云函数间接操作 Cloud DB。
 *
 * @example
 * ```typescript
 * const cloud = CloudService.getInstance();
 * await cloud.syncAll(familyId);
 * await cloud.push('period_records', record, record.version);
 * ```
 */
import { cloudFunction, cloudStorage } from '@kit.CloudFoundationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { AgcConfig } from './AgcConfig';
import { LocalDbService } from './LocalDbService';
import { Photo } from '../model/Photo';
import { SYNC_CONFIG } from '../common/Constants';
import { exponentialBackoff } from '../common/Utils';
import { CLIENT_TO_CLOUD_TYPE, CLOUD_TO_CLIENT, toCloudType, toLocalKey, ALL_CLOUD_TYPES } from '../common/CloudTypes';

const TAG = '[CloudService]';
const DOMAIN = 0x0000;

/** 云端同步最小间隔（5分钟），防止频繁切换应用导致大量请求 */
const MIN_SYNC_INTERVAL_MS = 5 * 60 * 1000;

/** 等待云端文件传输的最长时间；超时按失败处理（照片记录保留本地路径，后续补传自愈） */
const TRANSFER_TIMEOUT_MS = 60 * 1000;

/**
 * Cloud DB Text 字段中存 JSON 数组的字段名（与 agc-clouddb-schema 对齐）。
 * convertFromCloud 对这些字段做归一化：空串/非法 JSON → []，避免页面拿到
 * 字符串/undefined 后调用数组方法崩溃（如 Index 的 m.timeSlots.every()）。
 */
const ARRAY_FIELDS: string[] = [
  'visibleMembers', 'symptoms', 'timeSlots', 'reminderSettings',
  'isSharedWith', 'mutedModules', 'tagIds'
];

/**
 * Cloud DB 数值字段名（Integer/Long/Float/Double/Byte/Short，与 agc-clouddb-object-types.json 对齐）。
 *
 * 服务端 SDK 对 CloudDBZoneGenericObject 反序列化时不做类型转换（Utils.deserializeObjects
 * 只有 typed 模型路径才走 deserializeNumber），AGC 返回的 Float/Integer 字段可能是字符串
 * （如 amount:"5000"、version:"1"）。客户端若原样存储，`"5000".toFixed(0)` 会抛
 * "undefined is not callable" 导致整页 JsCrash（审核致命问题，家庭记账点击闪退根因）。
 * convertFromCloud 在此白名单内统一把字符串转回 number。
 */
const NUMERIC_FIELDS: string[] = [
  'amount', 'cycleDay', 'cycleLength', 'duration', 'headCircumference',
  'height', 'latitude', 'longitude', 'month', 'radius', 'value', 'version',
  'weight', 'width', 'year'
];

// 重新导出类型映射函数，保持向后兼容
export { toCloudType, toLocalKey, CLIENT_TO_CLOUD_TYPE, CLOUD_TO_CLIENT, ALL_CLOUD_TYPES };

// ===== 接口定义 =====

/** 同步操作记录 */
interface SyncOperation {
  type: string;       // 云端对象类型名（如 'PeriodRecord'）
  op: 'upsert' | 'delete';
  data: object;
  version: number;
  retryCount: number;
  createdAt: number;
}

/** 云端推送操作（传给 push-data 云函数） */
export interface CloudOperation {
  type: string;       // 云端对象类型名
  op: 'upsert' | 'delete';
  data: object;
  version: number;
}

/** 云函数返回结构 */
interface CloudFunctionResult {
  code: number;
  message: string;
  data?: object;
}

/** 推送冲突条目 */
export interface ConflictEntry {
  type: string;
  id: string;
  serverVersion: number;
  clientVersion: number;
}

/** 推送结果 */
/** 失败操作的详细原因（诊断用） */
export interface FailedReason {
  type: string;
  id: string;
  reason: string;
}

export interface PushResult {
  succeeded: number;
  failed: number;
  conflicts: ConflictEntry[];
  failedReasons?: FailedReason[];
  /** 云函数返回的非零错误码（如 403=membership 不存在），成功时为 0 */
  code?: number;
  message?: string;
}

/** 拉取结果 */
export interface PullResult {
  serverTime: number;
  snapshots: Record<string, object[]>;  // 云端类型名 → records
}

/** 家人实时位置行（LocationShare，服务端已按可见性过滤，仅含我能看到的成员） */
export interface ClientLocationShareRow {
  id: string;
  familyId: string;
  memberId: string;
  visibility: string;
  visibleMembers: string[];
  shareEnabled: boolean;
  arrivalNotifyEnabled: boolean;
  latitude: number;
  longitude: number;
  accuracy: number;
  updatedAt: string;
  version: number;
}

/** 同步状态 */
export enum SyncStatus {
  IDLE = 'idle',
  PUSHING = 'pushing',
  PULLING = 'pulling',
  SYNCING = 'syncing',
  ERROR = 'error'
}

/** 云函数 pull-data 参数 */
interface PullDataParams {
  familyId: string;
  sinceTimestamp?: number;
  objectTypes?: string[];
}

/** 同步进度回调 */
export interface SyncProgress {
  status: SyncStatus;
  phase: string;
  processed: number;
  total: number;
  error?: string;
}

type SyncProgressCallback = (progress: SyncProgress) => void;

export class CloudService {
  private static instance: CloudService | null = null;
  private syncQueue: SyncOperation[] = [];
  private isSyncing: boolean = false;
  private isProcessingQueue: boolean = false;
  private lastSyncTime: number = 0;
  private syncProgressCallback: SyncProgressCallback | null = null;
  private db: LocalDbService = LocalDbService.getInstance();

  private constructor() {}

  static getInstance(): CloudService {
    if (!CloudService.instance) {
      CloudService.instance = new CloudService();
    }
    return CloudService.instance;
  }

  /**
   * 设置同步进度回调，用于 UI 展示同步状态
   * @param callback - 进度回调函数，传 null 清除回调
   */
  setSyncProgressCallback(callback: SyncProgressCallback | null): void {
    this.syncProgressCallback = callback;
  }

  /** 获取上次成功同步的时间戳（毫秒），0 表示尚未同步过 */
  getLastSyncTime(): number {
    return this.lastSyncTime;
  }

  /**
   * 检查云端服务是否可用
   * 只需 AGC 已初始化即可（通过云函数间接访问 Cloud DB，不需要直接 Cloud DB zone）
   * @returns true 表示云端服务可用
   */
  isCloudAvailable(): boolean {
    return AgcConfig.getInstance().isInitialized();
  }

  /**
   * 清空同步队列（退出家庭时调用）
   *
   * leaveFamily 后本地数据已清空，但 syncQueue 中可能残留旧家庭的待推送操作。
   * 若不清空，重新加入新家庭时 processQueue 会用新 familyId 推送旧数据，
   * 造成跨家庭污染或 FamilyMember 幽灵记录。
   */
  clearSyncQueue(): void {
    const dropped = this.syncQueue.length;
    this.syncQueue = [];
    if (dropped > 0) {
      hilog.info(DOMAIN, TAG, 'clearSyncQueue: dropped %{public}d stale operations', dropped);
    }
  }

  // ===== 核心同步接口 =====

  /**
   * 全量同步：先推本地变更，再拉云端最新数据
   *
   * 通常在应用从后台返回时由 EntryAbility.onForeground 调用。
   * 内置防抖：距上次同步不足 5 分钟时自动跳过（force=true 时跳过，打开应用即及时拉取）。
   *
   * @param familyId - 当前家庭 ID
   * @param force - 是否强制同步（跳过 5 分钟防抖）。打开应用时应传 true，
   *                与 PeriodPage/AlbumPage 的页面级主动拉取（pullPeriodData/pullPhotos）保持一致
   * @returns true 表示同步完成（含部分失败），false 表示跳过或全部失败
   */
  async syncAll(familyId: string, force: boolean = false): Promise<boolean> {
    if (!this.isCloudAvailable() || !familyId) return false;
    if (this.isSyncing) return false;
    // 防抖：距上次同步不足5分钟则跳过（force=true 时跳过）
    if (!force && Date.now() - this.lastSyncTime < MIN_SYNC_INTERVAL_MS) {
      hilog.info(DOMAIN, TAG, 'Sync throttled — last sync was %{public}dms ago',
        Date.now() - this.lastSyncTime);
      return false;
    }

    this.isSyncing = true;
    this.emitProgress({ status: SyncStatus.SYNCING, phase: 'starting', processed: 0, total: 0 });

    try {
      // 先推本地变更
      const pushOk = await this.processQueue();
      // 再拉云端数据
      const pullOk = await this.pullAll(familyId);

      this.lastSyncTime = Date.now();
      this.emitProgress({ status: SyncStatus.IDLE, phase: 'completed', processed: 1, total: 1 });
      return pushOk && pullOk;
    } catch (err) {
      this.emitProgress({
        status: SyncStatus.ERROR, phase: 'sync_failed',
        processed: 0, total: 0, error: (err as Error).message
      });
      return false;
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * 推送单条数据变更到云端
   *
   * 写操作时调用模式：先写本地 Preferences，再异步调用此方法推送。
   * 如果云端不可用，静默返回 false，不影响本地数据。
   * 失败的操作会进入重试队列，最多重试 MAX_RETRIES 次。
   *
   * @param type - 数据类型名称（客户端 key 如 'period_records' 或云端类型名如 'PeriodRecord'）
   * @param data - 要推送的数据对象
   * @param version - 数据版本号，用于冲突解决
   * @param op - 操作类型：upsert（写入/更新）或 delete（删除）
   * @returns true 表示推送成功或已入队
   */
  async push(type: string, data: object, version: number, op: 'upsert' | 'delete' = 'upsert'): Promise<boolean> {
    if (!this.isCloudAvailable()) {
      // 云端不可用时静默返回，本地功能正常
      return false;
    }

    // 自动转换客户端 key 为云端类型名
    const cloudType = CLIENT_TO_CLOUD_TYPE[type] ?? type;
    const operation: SyncOperation = {
      type: cloudType,
      op,
      data,
      version,
      retryCount: 0,
      createdAt: Date.now()
    };
    this.syncQueue.push(operation);
    return await this.processQueue();
  }

  // ===== 云函数 Cloud DB 操作 =====

  /**
   * 通过云函数推送数据变更到 Cloud DB
   *
   * 调用 push-data 云函数，该函数处理：
   * - 用户身份校验
   * - 家庭成员权限验证
   * - 版本号冲突检测
   * - 批量 upsert / delete
   *
   * @param familyId - 家庭 ID
   * @param operations - 操作列表
   * @returns 推送结果
   */
  async pushToCloudDb(familyId: string, operations: CloudOperation[]): Promise<PushResult> {
    const pushData: Record<string, Object> = {};
    pushData['familyId'] = familyId;
    pushData['operations'] = operations as Object;
    const result = await this.callCloudFunction('push-data', pushData);
    if (result.code === 0 && result.data) {
      return result.data as PushResult;
    }
    // 保留错误码和消息，让调用方（processQueue）能区分 403 membership 缺失和其他错误
    return {
      succeeded: 0,
      failed: operations.length,
      conflicts: [],
      code: result.code,
      message: result.message
    };
  }

  /**
   * 通过云函数从 Cloud DB 拉取数据
   *
   * 调用 pull-data 云函数，该函数处理：
   * - 用户身份校验
   * - 家庭成员权限验证
   * - 按 familyId + 时间戳增量拉取
   *
   * @param familyId - 家庭 ID
   * @param objectTypes - 要拉取的云端类型名列表，空/不传则拉全部
   * @returns 拉取结果（含 serverTime 和各类型快照）
   */
  async pullFromCloudDb(familyId: string, objectTypes?: string[]): Promise<PullResult> {
    const params: PullDataParams = {
      familyId
    };
    if (objectTypes && objectTypes.length > 0) {
      params.objectTypes = objectTypes;
    }
    const result = await this.callCloudFunction('pull-data', params);
    if (result.code === 0 && result.data) {
      return result.data as PullResult;
    }
    return { serverTime: Date.now(), snapshots: {} };
  }

  /**
   * 全量拉取并合并到本地（用于新设备登录 / 重装后恢复数据）
   *
   * @param familyId - 家庭 ID
   * @returns true 表示拉取并合并成功
   */
  async fullPullAndMerge(familyId: string): Promise<boolean> {
    if (!this.isCloudAvailable() || !familyId) return false;

    try {
      hilog.info(DOMAIN, TAG, 'fullPullAndMerge: familyId=%{public}s', familyId);
      const result = await this.pullFromCloudDb(familyId);

      let totalMerged = 0;
      const snapshotKeys = Object.keys(result.snapshots);
      for (let si = 0; si < snapshotKeys.length; si++) {
        const cloudType = snapshotKeys[si];
        const records = result.snapshots[cloudType];
        if (Array.isArray(records) && records.length > 0) {
          await this.mergeToLocal(cloudType, records);
          totalMerged += records.length;
        }
      }

      hilog.info(DOMAIN, TAG, 'fullPullAndMerge: merged %{public}d records across %{public}d types',
        totalMerged, Object.keys(result.snapshots).length);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'fullPullAndMerge failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  // ===== Cloud Function 操作 =====

  /**
   * 调用 AGC 云函数
   *
   * 已定义的云函数：
   * - push-data: 推送数据变更到 Cloud DB
   * - pull-data: 根据 familyId + 时间戳拉取增量数据
   * - validate-invite: 验证邀请码有效性
   * - validate-claim: 验证认领码有效性
   * - merge-conflict: 服务端冲突合并（版本号优先 + last-write-wins）
   * - my-families: 按用户 ID 查询所属家庭
   * - notify-family: 家庭成员变更通知（Cloud DB 触发）
   *
   * @param name - 云函数名称
   * @param params - 传递给云函数的参数对象
   * @returns 云函数返回的结构化结果 { code, message, data }
   * @throws 云函数调用失败时抛出错误
   */
  async callCloudFunction(name: string, params: object): Promise<CloudFunctionResult> {
    try {
      // 注入 __uid 兜底：AGC Auth 未就绪时，云函数从 body 读取用户身份
      // 优先用 AGC UID（与 Cloud DB 用户身份一致），其次用本地 userId（openID）
      const localUserId = this.db.getCurrentUserId();
      const agcUserId = this.db.getAgcUserId();
      const uid = agcUserId || localUserId;
      const paramsWithUid: Record<string, Object> = {};
      const paramKeys = Object.keys(params);
      for (let pi = 0; pi < paramKeys.length; pi++) {
        paramsWithUid[paramKeys[pi]] = (params as Record<string, Object>)[paramKeys[pi]];
      }
      if (uid) {
        paramsWithUid['__uid'] = uid;
      }
      hilog.info(DOMAIN, TAG,
        'callCloudFunction: name=%{public}s, uid(local=%{public}s, agc=%{public}s, resolved=%{public}s)',
        name, localUserId ? 'yes' : 'no', agcUserId ? 'yes' : 'no', uid ? 'yes' : 'no');
      // 客户端 @kit.CloudFoundationKit 的 cloudFunction.call 接收 FunctionParams，字段名是 data（非 params）。
      // SDK 类型定义 @hms.core.deviceCloudGateway.cloudFunction.d.ts: FunctionParams 只有 data 字段，没有 params。
      // 客户端 data 被 AGC 放入服务端 event.request；用 params 会被运行时忽略，event.request 为空 -> 401/参数丢失。
      const result: cloudFunction.FunctionResult = await cloudFunction.call({
        name: name,
        data: paramsWithUid
      });
      const raw = result.result;
      const parsed: CloudFunctionResult = (typeof raw === 'string'
        ? JSON.parse(raw)
        : raw) as CloudFunctionResult;
      hilog.info(DOMAIN, TAG, 'Cloud function %{public}s returned: code=%{public}d, message=%{public}s',
        name, parsed.code, parsed.message ?? '');
      return parsed;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG,
        'Cloud function %{public}s failed: code=%{public}s, msg=%{public}s',
        name, e.code, e.message);
      throw new Error(`云函数调用失败: ${name} - ${e.message}`);
    }
  }

  // ===== Cloud Storage 操作 =====

  /**
   * 上传文件到 Cloud Storage
   *
   * 用于照片上传、头像等场景。上传后返回下载 URL。
   *
   * @param localPath - 本地文件路径
   * @param cloudPath - 云端存储路径（如 /photos/{familyId}/{photoId}.jpg）
   * @returns 下载 URL，失败时返回 null
   */
  async uploadFile(localPath: string, cloudPath: string): Promise<string | null> {
    const context = AgcConfig.getInstance().getContext();
    if (!context) {
      hilog.warn(DOMAIN, TAG, 'Cloud Storage context not ready');
      return null;
    }
    try {
      const bucket = cloudStorage.bucket();
      const task = await bucket.uploadFile(context, {
        localPath: localPath,
        cloudPath: cloudPath
      });
      await this.waitTransferTask(task);
      const downloadUrl = await bucket.getDownloadURL(cloudPath);
      hilog.info(DOMAIN, TAG, 'File uploaded: %{public}s -> %{public}s', localPath, cloudPath);
      return downloadUrl;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'File upload failed: code=%{public}s, msg=%{public}s', e.code, e.message);
      return null;
    }
  }

  /**
   * 从 Cloud Storage 下载文件
   *
   * @param cloudPath - 云端存储路径
   * @param localPath - 本地保存路径
   * @returns true 表示下载成功
   */
  async downloadFile(cloudPath: string, localPath: string): Promise<boolean> {
    const context = AgcConfig.getInstance().getContext();
    if (!context) {
      hilog.warn(DOMAIN, TAG, 'Cloud Storage context not ready');
      return false;
    }
    try {
      const bucket = cloudStorage.bucket();
      const task = await bucket.downloadFile(context, {
        cloudPath: cloudPath,
        localPath: localPath
      });
      await this.waitTransferTask(task);
      hilog.info(DOMAIN, TAG, 'File downloaded: %{public}s -> %{public}s', cloudPath, localPath);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'File download failed: code=%{public}s, msg=%{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 删除 Cloud Storage 中的文件
   *
   * @param cloudPath - 云端存储路径
   * @returns true 表示删除成功
   */
  async deleteFile(cloudPath: string): Promise<boolean> {
    try {
      const bucket = cloudStorage.bucket();
      await bucket.deleteFile(cloudPath);
      hilog.info(DOMAIN, TAG, 'File deleted: %{public}s', cloudPath);
      return true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'File delete failed: code=%{public}s, msg=%{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 等待传输任务真正完成
   *
   * request.agent.Task.start() 的 Promise 只表示任务"已启动"，不代表传输完成；
   * 传输结果通过 completed/failed 事件通知。直接 await start() 会在上传进行中
   * 就去取下载 URL / 读本地文件，产生竞态。
   */
  private waitTransferTask(task: request.agent.Task): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { reject(new Error('transfer task timeout')); }, TRANSFER_TIMEOUT_MS);
      task.on('completed', () => { clearTimeout(timer); resolve(); });
      task.on('failed', () => {
        clearTimeout(timer);
        // failed 事件的 Progress 不带错误码，TaskInfo.reason 是唯一能拿到真实原因的途径
        request.agent.show(task.tid).then((info: request.agent.TaskInfo) => {
          reject(new Error(`transfer task failed: faults=${info.faults}, reason=${info.reason}`));
        }).catch(() => {
          reject(new Error('transfer task failed: no detail'));
        });
      });
      task.start().catch((err: BusinessError) => { clearTimeout(timer); reject(err); });
    });
  }

  /**
   * 生成照片的云端存储路径
   * 约定：family/{familyId}/photos/{photoId}.jpg（与 cloud/storage-rules.txt 规划一致）
   * 删除云端文件时按同一约定推导路径，无需在记录里额外存 cloudPath
   */
  static photoCloudPath(familyId: string, photoId: string): string {
    return `family/${familyId ? familyId : 'nofamily'}/photos/${photoId}.jpg`;
  }

  /**
   * 上传本地照片到 Cloud Storage
   *
   * @param localPath - 本地沙箱文件路径（http 开头视为已上传，直接返回 null）
   * @param familyId - 家庭 ID，用于云端路径隔离
   * @param photoId - 照片记录 ID，作为云端文件名
   * @returns 云端下载 URL，失败或无需上传时返回 null
   */
  async uploadPhoto(localPath: string, familyId: string, photoId: string): Promise<string | null> {
    if (!localPath || localPath.startsWith('http')) {
      hilog.warn(DOMAIN, TAG, 'uploadPhoto skipped: url=%{public}s', localPath ? 'already http' : 'empty');
      return null;
    }
    let srcPath = localPath;
    if (localPath.startsWith('file://')) {
      // 媒体库 URI（旧版本保存的记录）：先复制到沙箱再上传，让历史记录也能自愈补传；
      // 若是其他设备同步来的 URI，本机媒体库无此文件，openSync 会抛错走 skip 分支
      const copied = this.copyUriToSandbox(localPath);
      if (!copied) {
        hilog.warn(DOMAIN, TAG, 'uploadPhoto skipped: copy media uri to sandbox failed: %{public}s', localPath);
        return null;
      }
      srcPath = copied;
    } else {
      // 接收端设备上没有发送方的沙箱文件，access 校验避免无效上传
      try {
        if (!fileIo.accessSync(localPath)) {
          hilog.warn(DOMAIN, TAG, 'uploadPhoto skipped: local file not found: %{public}s', localPath);
          return null;
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'uploadPhoto skipped: access check failed: %{public}s, %{public}s',
          localPath, (err as Error).message);
        return null;
      }
    }
    return this.uploadFile(srcPath, CloudService.photoCloudPath(familyId, photoId));
  }

  /**
   * 把媒体库 URI（file://media/...）复制到应用沙箱，返回沙箱路径
   * copyFileSync 不接受媒体库 URI，必须先 openSync 拿 fd
   */
  private copyUriToSandbox(uri: string): string | null {
    try {
      const context = AgcConfig.getInstance().getContext();
      const sandboxDir = context ? context.filesDir : '';
      if (!sandboxDir) {
        return null;
      }
      const destPath = `${sandboxDir}/photo_${Date.now()}_${Math.floor(Math.random() * 1000)}.jpg`;
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.copyFileSync(srcFile.fd, destPath);
      } finally {
        fileIo.closeSync(srcFile);
      }
      return destPath;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'copyUriToSandbox failed: %{public}s, %{public}s', uri, (err as Error).message);
      return null;
    }
  }

  /**
   * 补传未上云的照片：扫描本地相册，url 仍是本地路径且文件存在的，上传到 Cloud Storage，
   * 成功后把 url 改为云端下载 URL 并重新推送（version+1）。
   *
   * 覆盖两种场景：
   * 1. 离线时保存的照片，恢复网络后补传
   * 2. 历史记录自愈：旧版本只同步了本地路径，接收端无法显示；发送端补传后 url 变为
   *    https 下载地址并重新推送，接收端下拉同步即可显示
   *
   * @returns 本次成功补传的数量
   */
  /**
   * 主动拉取云端照片并合并到本地，绕过 syncAll 的 5 分钟节流。
   *
   * 背景：syncAll 只在 app 前后台切换时触发且有节流，用户打开相册页时若云端
   * 已有其他成员新传的照片，本地缓存里没有，导致"别人传的照片我看不到"。
   * 相册页 aboutToAppear 应主动调用本方法拉取 Photo 类型，无需等待全局同步。
   *
   * @param familyId - 家庭 ID
   * @returns 本次合并进本地的照片数
   */
  async pullPhotos(familyId: string): Promise<number> {
    if (!this.isCloudAvailable() || !familyId) return 0;
    try {
      const result = await this.pullFromCloudDb(familyId, ['Photo', 'PhotoComment']);
      let merged = 0;
      const photoRecords = result.snapshots['Photo'];
      if (Array.isArray(photoRecords) && photoRecords.length > 0) {
        await this.mergeToLocal('Photo', photoRecords);
        this.reconcileLocalDirty('Photo', photoRecords);
        merged += photoRecords.length;
      }
      const commentRecords = result.snapshots['PhotoComment'];
      if (Array.isArray(commentRecords) && commentRecords.length > 0) {
        await this.mergeToLocal('PhotoComment', commentRecords);
        this.reconcileLocalDirty('PhotoComment', commentRecords);
        merged += commentRecords.length;
      }
      return merged;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pullPhotos failed: %{public}s', (err as Error).message);
      return 0;
    }
  }

  /**
   * 主动拉取云端经期数据（经期记录 + 啪啪记录）并合并到本地，绕过 syncAll 的 5 分钟节流。
   *
   * 背景：syncAll 只在 app 前后台切换时触发且有节流，用户打开姨妈周期页时若云端
   * 已有其他成员新记录的经期（如创建者刚点了「来了」），本地缓存里没有，
   * 导致「创建者显示经期第4天、我显示第13天」的分歧。周期页 aboutToAppear 应主动
   * 调用本方法，无需等待全局同步。
   *
   * 附带效果：reconcileLocalDirty 会把「本地有而云端没有 / 本地版本更高」的本人记录
   * 补推上去，自愈本机 push 静默失败（fire-and-forget 队列丢失）导致的本地/云端分叉。
   *
   * @param familyId - 家庭 ID
   * @returns 本次合并进本地的记录数
   */
  async pullPeriodData(familyId: string): Promise<number> {
    if (!this.isCloudAvailable() || !familyId) return 0;
    try {
      const result = await this.pullFromCloudDb(familyId, ['PeriodRecord', 'IntimacyRecord']);
      const snapshots = result.snapshots;
      let merged = 0;

      const periodRecords = snapshots['PeriodRecord'];
      if (Array.isArray(periodRecords) && periodRecords.length > 0) {
        await this.mergeToLocal('PeriodRecord', periodRecords);
        this.reconcileLocalDirty('PeriodRecord', periodRecords);
        merged += periodRecords.length;
      }

      const intimacyRecords = snapshots['IntimacyRecord'];
      if (Array.isArray(intimacyRecords) && intimacyRecords.length > 0) {
        await this.mergeToLocal('IntimacyRecord', intimacyRecords);
        this.reconcileLocalDirty('IntimacyRecord', intimacyRecords);
        merged += intimacyRecords.length;
      }

      return merged;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pullPeriodData failed: %{public}s', (err as Error).message);
      return 0;
    }
  }

  /**
   * 主动拉取家人实时位置（LocationShare），绕过 syncAll 节流与本地缓存。
   *
   * 与照片/经期页不同：LocationShare 是 1 分钟心跳数据，不进本地业务缓存
   * （避免 mergeToLocal/reconcileLocalDirty 卷入版本对账回推），只返回给调用方
   * （LocationPage）展示。服务端已按可见性过滤：拿到的行就是「我能看到的人」。
   *
   * @param familyId - 家庭 ID
   * @returns 归一化后的 LocationShare 行数组（空数组 = 云端不可用/无行）
   */
  async pullLocationShares(familyId: string): Promise<ClientLocationShareRow[]> {
    if (!this.isCloudAvailable() || !familyId) return [];
    try {
      const result = await this.pullFromCloudDb(familyId, ['LocationShare']);
      const records = result.snapshots['LocationShare'];
      if (!Array.isArray(records)) return [];
      const rows: ClientLocationShareRow[] = [];
      for (let i = 0; i < records.length; i++) {
        const r = records[i] as Record<string, Object>;
        const row: ClientLocationShareRow = {
          id: r['id'] as string,
          familyId: r['familyId'] as string,
          memberId: r['memberId'] as string,
          visibility: (r['visibility'] as string) ?? 'FAMILY',
          visibleMembers: this.parseStringArrayField(r['visibleMembers']),
          shareEnabled: r['shareEnabled'] === 1 || r['shareEnabled'] === true,
          arrivalNotifyEnabled: r['arrivalNotifyEnabled'] === 1 || r['arrivalNotifyEnabled'] === true,
          latitude: r['latitude'] as number,
          longitude: r['longitude'] as number,
          accuracy: (r['accuracy'] as number) ?? 0,
          updatedAt: (r['updatedAt'] as string) ?? '',
          version: (r['version'] as number) ?? 1
        };
        rows.push(row);
      }
      return rows;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pullLocationShares failed: %{public}s', (err as Error).message);
      return [];
    }
  }

  private parseStringArrayField(v: Object | undefined): string[] {
    if (Array.isArray(v)) return v as string[];
    if (typeof v === 'string' && v.length > 0) {
      try {
        const parsed = JSON.parse(v) as Object;
        return Array.isArray(parsed) ? parsed as string[] : [];
      } catch (e) {
        return [];
      }
    }
    return [];
  }

  async syncPendingPhotoUploads(): Promise<number> {
    const db = LocalDbService.getInstance();
    const photos = db.getPhotos();
    let uploaded = 0;
    for (const photo of photos) {
      if (!photo.url || photo.url.startsWith('http')) {
        continue;
      }
      const downloadUrl = await this.uploadPhoto(photo.url, photo.familyId, photo.id);
      if (!downloadUrl) {
        continue;
      }
      const updated: Photo = {
        id: photo.id,
        familyId: photo.familyId,
        creatorId: photo.creatorId,
        visibility: photo.visibility,
        visibleMembers: photo.visibleMembers,
        version: photo.version + 1,
        createdAt: photo.createdAt,
        updatedAt: new Date().toISOString(),
        isDeleted: photo.isDeleted,
        url: downloadUrl,
        thumbnailUrl: photo.thumbnailUrl,
        description: photo.description,
        eventTag: photo.eventTag,
        takenAt: photo.takenAt,
        isOnWall: photo.isOnWall === true,
        width: photo.width || 0,
        height: photo.height || 0
      };
      try {
        await db.updatePhoto(updated);
        uploaded++;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Pending photo update failed: %{public}s, %{public}s',
          photo.id, (err as Error).message);
      }
    }
    if (uploaded > 0) {
      hilog.info(DOMAIN, TAG, 'syncPendingPhotoUploads: %{public}d photos uploaded', uploaded);
    }
    return uploaded;
  }

  // ===== 内部方法 =====

  /**
   * 处理同步队列 — 攒批调用 push-data 云函数
   */
  private async processQueue(): Promise<boolean> {
    if (this.syncQueue.length === 0) return true;

    // 防止并发执行：saveFamily 和 saveMember 的 fire-and-forget pushToCloud
    // 可能同时触发 processQueue，导致两个并发推送互相干扰（如 403 恢复时读到不一致状态）。
    // 正在处理时，新操作留在队列中，由当前处理轮次结束后通过递归调用处理。
    if (this.isProcessingQueue) {
      return false;
    }
    this.isProcessingQueue = true;

    try {
      // 快照当前队列，避免迭代期间的新 push 干扰
      const queue = [...this.syncQueue];
      this.syncQueue = [];

      const familyId = this.db.getCurrentFamilyId();
      if (!familyId) {
        // 没有 familyId（尚未加入家庭），操作重新入队
        this.syncQueue = [...queue, ...this.syncQueue];
        return false;
      }

      this.emitProgress({
        status: SyncStatus.PUSHING, phase: 'pushing_changes',
        processed: 0, total: queue.length
      });

      try {
        const operations: CloudOperation[] = [];
        for (let oi = 0; oi < queue.length; oi++) {
          const q = queue[oi];
          const cop: CloudOperation = {
            type: q.type,
            op: q.op,
            data: q.data,
            version: q.version
          };
          operations.push(cop);
        }

        const result = await this.pushToCloudDb(familyId, operations);

        if (result.code === 403 && operations.length > 0) {
          hilog.warn(DOMAIN, TAG,
            'processQueue: 403 (membership missing), re-establishing from local data, then retrying');
          const recovered = await this.reEstablishMembership(familyId);
          if (recovered) {
            const retryResult = await this.pushToCloudDb(familyId, operations);
            hilog.info(DOMAIN, TAG,
              'processQueue: retry after membership recovery -> succeeded=%{public}d failed=%{public}d',
              retryResult.succeeded, retryResult.failed);
            this.emitProgress({
              status: SyncStatus.PUSHING, phase: 'pushing_changes',
              processed: queue.length, total: queue.length
            });
            return retryResult.failed === 0;
          }
          hilog.warn(DOMAIN, TAG, 'processQueue: membership recovery failed, operations dropped');
          return false;
        }

        hilog.info(DOMAIN, TAG,
          'processQueue: %{public}d ops -> succeeded=%{public}d failed=%{public}d conflicts=%{public}d',
          operations.length, result.succeeded, result.failed, result.conflicts.length);
        if (result.failed > 0 && result.failedReasons && result.failedReasons.length > 0) {
          hilog.warn(DOMAIN, TAG, 'processQueue failedReasons: %{public}s',
            JSON.stringify(result.failedReasons));
        }

        if (result.conflicts.length > 0) {
          hilog.warn(DOMAIN, TAG, 'Conflicts detected: %{public}s',
            JSON.stringify(result.conflicts));
        }

        this.emitProgress({
          status: SyncStatus.PUSHING, phase: 'pushing_changes',
          processed: queue.length, total: queue.length
        });

        return result.failed === 0;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'processQueue failed, re-enqueue %{public}d ops: %{public}s',
          queue.length, (err as Error).message);

        const retryable = queue.map(op => {
          op.retryCount++;
          return op;
        }).filter(op => op.retryCount <= SYNC_CONFIG.MAX_RETRIES);

        this.syncQueue = [...retryable, ...this.syncQueue];
        return false;
      }
    } finally {
      this.isProcessingQueue = false;
      if (this.syncQueue.length > 0 && this.db.getCurrentFamilyId()) {
        const retryAttempt = this.syncQueue[0].retryCount ?? 0;
        const delay = exponentialBackoff(retryAttempt, SYNC_CONFIG.INITIAL_DELAY_MS, SYNC_CONFIG.MAX_DELAY_MS);
        setTimeout(() => { this.processQueue().catch(() => {}); }, delay);
      }
    }
  }

  /**
   * 从本地数据恢复 Cloud DB membership
   *
   * 场景：createFamily 时离线 / 初始 fire-and-forget 推送静默失败，
   * 导致 Cloud DB 没有 FamilyMember 记录，所有后续 push-data 返回 403。
   *
   * 处理：查本地 Family + FamilyMember，用 isEstablishingRelation 放行路径重新推送。
   *
   * @param familyId - 当前家庭 ID
   * @returns true 表示 membership 恢复成功
   */
  private async reEstablishMembership(familyId: string): Promise<boolean> {
    try {
      const uid = this.db.getAgcUserId() || this.db.getCurrentUserId();
      if (!uid || !familyId) {
        hilog.warn(DOMAIN, TAG, 'reEstablishMembership: missing uid or familyId');
        return false;
      }

      const family = this.db.getFamilies().find(f => f.id === familyId);
      if (!family) {
        hilog.warn(DOMAIN, TAG, 'reEstablishMembership: local family not found for %{public}s', familyId);
        return false;
      }

      // 找到当前用户在这个家庭的成员记录
      const members = this.db.getMembersByFamilyId(familyId);
      const member = members.find(m => m.userId === uid);
      if (!member) {
        hilog.warn(DOMAIN, TAG, 'reEstablishMembership: local FamilyMember not found, uid=%{public}s, familyId=%{public}s, members=%{public}d',
          uid, familyId, members.length);
        return false;
      }

      // 推送 Family 的条件：creatorId 非空（有合法创建者）。
      // 不用 creatorId === uid 判断 -- AGC Auth 就绪后 getAgcUserId() 可能在 createFamily
      // 之后才可用，与 getCurrentUserId() 设的 creatorId 不一致，导致 Family 永远不被推送。
      const ops: CloudOperation[] = [];
      if (family.creatorId) {
        ops.push({ type: 'Family', op: 'upsert', data: family as object, version: 1 });
      }
      ops.push({ type: 'FamilyMember', op: 'upsert', data: member as object, version: 1 });

      const result = await this.pushToCloudDb(familyId, ops);
      hilog.info(DOMAIN, TAG,
        'reEstablishMembership: pushed Family+FamilyMember, succeeded=%{public}d failed=%{public}d code=%{public}d',
        result.succeeded, result.failed, result.code ?? 0);
      return result.failed === 0;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'reEstablishMembership failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  /**
   * 拉取所有类型数据并合并到本地
   * 分批并行拉取以加速，每批 4 个类型避免压垮云函数层
   */
  private async pullAll(familyId: string): Promise<boolean> {
    if (!familyId) return false;

    this.emitProgress({
      status: SyncStatus.PULLING, phase: 'pulling_updates',
      processed: 0, total: ALL_CLOUD_TYPES.length
    });

    try {
      // 使用 pull-data 云函数一次性拉取所有类型
      const result = await this.pullFromCloudDb(familyId);

      let processed = 0;
      const pullKeys = Object.keys(result.snapshots);
      for (let pi = 0; pi < pullKeys.length; pi++) {
        const cloudType = pullKeys[pi];
        const records = result.snapshots[cloudType];
        processed++;
        if (Array.isArray(records) && records.length > 0) {
          await this.mergeToLocal(cloudType, records);
          hilog.info(DOMAIN, TAG, 'pullAll: %{public}s → %{public}d records merged',
            cloudType, records.length);
        }

        // 对账：合并后把「本地有而云端没有 / 本地版本更高」的记录补推，
        // 自愈 fire-and-forget 推送失败导致的本地/云端永久分叉
        this.reconcileLocalDirty(cloudType, Array.isArray(records) ? records : []);

        this.emitProgress({
          status: SyncStatus.PULLING, phase: 'pulling_updates',
          processed, total: ALL_CLOUD_TYPES.length
        });
      }

      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pullAll failed: %{public}s', (err as Error).message);
      return false;
    }
  }

  /**
   * 合并云端数据到本地缓存（冲突解决：版本号 + 最后修改时间）
   *
   * 合并策略：
   * - 云端记录不存在于本地 → 直接添加
   * - 云端 version > 本地 version → 用云端的
   * - 云端 version = 本地 version → 比较 updatedAt，新的覆盖旧的
   * - 云端 isDeleted = 1 → 从本地删除
   * - 本地 version > 云端 version → 保留本地（本地变更尚未推送）
   */
  private async mergeToLocal(cloudType: string, cloudRecords: object[]): Promise<void> {
    const localKey = CLOUD_TO_CLIENT[cloudType];
    if (!localKey || cloudRecords.length === 0) {
      hilog.warn(DOMAIN, TAG, 'mergeToLocal: unknown cloud type %{public}s or empty records', cloudType);
      return;
    }

    const localRecords = this.db.getList<object>(localKey);
    let added = 0;
    let updated = 0;
    let deleted = 0;

    for (const cloud of cloudRecords) {
      // Cloud DB schema 不支持 Boolean/Array：Integer 存 0/1，Text 存 JSON 字符串。
      // 转换回客户端类型，否则 filterByVisibility 的 .includes() / UI 布尔判断会失效。
      const cloudObj = this.convertFromCloud(cloud);
      const cloudId = cloudObj['id'] as string;
      const cloudVersion = (cloudObj['version'] as number) ?? 1;
      // convertFromCloud 已将 isDeleted 从 Integer(0/1) 转为 boolean
      const cloudDeleted = cloudObj['isDeleted'] as boolean;
      const cloudUpdatedAt = cloudObj['updatedAt'] as string;

      let localIdx = -1;
      for (let li = 0; li < localRecords.length; li++) {
        const rec = localRecords[li] as Record<string, Object>;
        if (rec['id'] as string === cloudId) {
          localIdx = li;
          break;
        }
      }

      if (cloudDeleted === true) {
        // 云端已软删除 → 本地也删除
        if (localIdx >= 0) {
          localRecords.splice(localIdx, 1);
          deleted++;
        }
      } else if (localIdx >= 0) {
        // 本地有同 id 记录 → 比较版本号
        const local = localRecords[localIdx] as Record<string, Object>;
        const localVersion = (local['version'] as number) ?? 1;
        const localUpdatedAt = local['updatedAt'] as string;

        if (cloudVersion > localVersion) {
          // 云端版本更高，用云端的
          localRecords[localIdx] = cloudObj;
          updated++;
        } else if (cloudVersion === localVersion && cloudUpdatedAt) {
          // 版本相同：云端有 updatedAt 时比较。
          // 本地 updatedAt 为空（如 join 时 validate-invite 返回的占位 Family，仅含部分字段）
          // 视为不完整记录，直接用云端完整记录补全本地。
          if (!localUpdatedAt || cloudUpdatedAt > localUpdatedAt) {
            localRecords[localIdx] = cloudObj;
            updated++;
          }
        }
        // 本地版本更高 → 保留本地（本地变更尚未推送）
      } else {
        // 本地没有，直接添加
        localRecords.push(cloudObj);
        added++;
      }
    }

    await this.db.saveList<object>(localKey, localRecords);

    hilog.info(DOMAIN, TAG,
      'mergeToLocal: %{public}s → added=%{public}d updated=%{public}d deleted=%{public}d',
      cloudType, added, updated, deleted);
  }

  /**
   * 本地/云端对账：把「本地有而云端没有」或「本地版本比云端新」的记录补推。
   *
   * 背景：push 是 fire-and-forget + 内存队列，推送失败或 App 被杀后不会自动补推，
   * 本地与云端会永久分叉。例如周期记录改了 startDate 未推上去，两台手机各自按
   * 不同的记录计算排卵期/怀孕几率，出现「一台显示安全期、一台显示高」的分歧。
   * mergeToLocal 对「本地版本更高」的记录保留本地（注释：本地变更尚未推送），
   * 但此前从无任何机制把它们回推——这里在每次 pullAll 后补上。
   *
   * 安全规则（防误推）：
   * - 本地版本 > 云端版本 → 回推 upsert（本地确有未推送的编辑）
   * - 本地独有且创建者是当前用户 → 回推 upsert（本机新建未推送）
   * - 本地独有但创建者是他人 → 不回推（大概率是云端已删除的陈旧副本，防止复活）
   * - 本地 isDeleted → 跳过（已删除记录不回推）
   *
   * 已知权衡：本人记录在另一台设备删除并成功同步后，本机未拉取到删除的陈旧副本
   * 会被当成本地独有回推（幂等 upsert，可再次删除），窗口极小，相比永久分叉可接受。
   */
  private reconcileLocalDirty(cloudType: string, cloudRecords: object[]): void {
    const localKey = CLOUD_TO_CLIENT[cloudType];
    if (!localKey) return;
    // 家庭/成员表有专属的 membership 恢复流程（reEstablishMembership），不在此对账
    if (cloudType === 'Family' || cloudType === 'FamilyMember') return;

    const localRecords = this.db.getList<object>(localKey);
    if (localRecords.length === 0) return;

    const cloudById: Record<string, Object> = {};
    for (let ci = 0; ci < cloudRecords.length; ci++) {
      const c = cloudRecords[ci] as Record<string, Object>;
      const cid = c['id'] as string;
      if (cid) cloudById[cid] = c;
    }

    let repushed = 0;
    for (let li = 0; li < localRecords.length; li++) {
      const rec = localRecords[li] as Record<string, Object>;
      const id = rec['id'] as string;
      if (!id) continue;
      const localVersion = (rec['version'] as number) ?? 1;
      const isDeleted = rec['isDeleted'] === true || (rec['isDeleted'] as number) === 1;
      if (isDeleted) continue;

      const cloud = cloudById[id];
      const cloudVersion = cloud ? (((cloud as Record<string, Object>)['version'] as number) ?? 1) : 0;
      const creatorId = rec['creatorId'] as string;
      const isMine = !!creatorId && this.db.isRecordCreator(creatorId);

      // 只回推「本人创建」的记录（云端无此行 = 新建未推送；本地版本更高 = 有未推送编辑）。
      // 他人记录一律不回推：对账快照可能不含该行（增量/分页拉取、陈旧副本、云端已删），
      // 以当前用户身份回推他人的记录，会在云端触发「xx 添加了地点/写了新备忘」之类
      // 假通知（通知按上传者取名），还可能复活已被作者删除的记录。
      if (!isMine) continue;
      if (!cloud || localVersion > cloudVersion) {
        this.push(cloudType, localRecords[li], localVersion, 'upsert');
        repushed++;
      }
    }

    if (repushed > 0) {
      hilog.info(DOMAIN, TAG,
        'reconcileLocalDirty: %{public}s → %{public}d dirty records re-pushed', cloudType, repushed);
    }
  }

  /**
   * Cloud DB 记录 -> 客户端类型转换
   *
   * Cloud DB schema 不支持 Boolean/Array：
   * - Boolean 字段存为 Integer (0/1) -> 转回 boolean
   * - Array 字段存为 Text (JSON 字符串) -> 转回 Array
   *
   * 规则：
   * - 字段名以 'is' 开头且值为 0/1 -> boolean（isSharedWith 除外，它是 Text 数组字段）
   * - 字符串值以 '[' 或 '{' 开头 -> 尝试 JSON.parse
   * - 已知数组字段（Cloud DB Text 存 JSON）为空串/非法 JSON 时归一化为数组，
   *   避免任何页面拿到字符串/undefined 后调用 .every()/.includes()/.map() 崩溃
   */
  private convertFromCloud(cloudRecord: object): Record<string, Object> {
    const obj = cloudRecord as Record<string, Object>;
    const result: Record<string, Object> = {};
    const keys = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const val = obj[key];
      if (val === undefined || val === null) {
        result[key] = val;
        continue;
      }

      // Integer (0/1) -> boolean，字段名以 is 开头（isSharedWith 除外，它是 Text 数组）。
      // 云端可能以数字 0/1 或字符串 "0"/"1" 返回，两种都要转，否则 mergeToLocal 的
      // isDeleted === true 判断失效（云端删除的记录本地永远删不掉）。
      if (key.startsWith('is') && key !== 'isSharedWith' &&
          ((typeof val === 'number' && (val === 0 || val === 1)) ||
           (typeof val === 'string' && (val === '0' || val === '1')))) {
        result[key] = Number(val) === 1;
        continue;
      }

      // 数值字段字符串 -> number（见 NUMERIC_FIELDS 注释：SDK 泛型对象不做类型转换，
      // Float 如 amount 返回字符串，客户端直接渲染 toFixed 会崩溃）
      if (typeof val === 'string' && NUMERIC_FIELDS.indexOf(key) >= 0) {
        const num = Number(val);
        result[key] = Number.isFinite(num) ? num : 0;
        continue;
      }

      // Text (JSON string) -> Array，只对已知数组字段做 JSON.parse（白名单）。
      // 不能对所有 "["/"{" 开头的字符串都解析：用户内容（如提醒标题 "{}"、"[]"）
      // 被转成对象/数组后，页面调用 title.replace() 等字符串方法会 TypeError 崩溃，
      // 且写入本地存储后每次启动都崩（无法进入 = 审核致命问题）。
      if (typeof val === 'string' && val.length > 0 && ARRAY_FIELDS.indexOf(key) >= 0) {
        try {
          result[key] = JSON.parse(val);
          continue;
        } catch (e) {
          // 不是合法 JSON，保留原始字符串（下方归一化会兜底成 []）
        }
      }

      result[key] = val;
    }

    // 数组字段归一化：空串 / 非数组字符串（如异常数据）→ []
    // 云端缺失的字段不新增（避免给类型外加字段），由各页面读取端兜底。
    for (let i = 0; i < ARRAY_FIELDS.length; i++) {
      const field = ARRAY_FIELDS[i];
      if (result[field] === undefined || result[field] === null) {
        continue;
      }
      if (!Array.isArray(result[field])) {
        result[field] = [];
      }
    }

    return result;
  }

  private emitProgress(progress: SyncProgress): void {
    if (this.syncProgressCallback) {
      this.syncProgressCallback(progress);
    }
  }
}
