/**
 * 云端同步服务 - 对接华为云 AGC (AppGallery Connect)
 *
 * 架构：本地优先（Local-first）+ 云端同步
 * - 写操作：先写本地 Preferences，再异步推送云端
 * - 读操作：优先读本地缓存，后台拉取云端最新数据合并
 * - 冲突解决：版本号校验 + 最后修改时间优先
 *
 * 使用的 AGC 服务：
 * - Cloud DB (cloudDatabase)：结构化数据同步
 * - Cloud Function (cloudFunction)：服务端逻辑（邀请码验证、冲突合并等）
 * - Cloud Storage (cloudStorage)：照片/文件存储
 *
 * @example
 * ```typescript
 * const cloud = CloudService.getInstance();
 * cloud.setSyncProgressCallback(progress => {
 *   hilog.info(0, TAG, `Sync: ${progress.status} ${progress.phase}`);
 * });
 * await cloud.syncAll(familyId);
 * await cloud.push('period_records', record, record.version);
 * ```
 */
import { cloudFunction, cloudStorage } from '@kit.CloudFoundationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AgcConfig } from './AgcConfig';
import { LocalDbService } from './LocalDbService';
import { SYNC_CONFIG } from '../common/Constants';
import { exponentialBackoff } from '../common/Utils';

const TAG = '[CloudService]';
const DOMAIN = 0x0000;

/** 云端同步最小间隔（5分钟），防止频繁切换应用导致大量请求 */
const MIN_SYNC_INTERVAL_MS = 5 * 60 * 1000;

/** 同步操作记录 */
interface SyncOperation {
  type: string;
  data: object;
  version: number;
  retryCount: number;
  createdAt: number;
}

/** 云函数返回结构 */
interface CloudFunctionResult {
  code: number;
  message: string;
  data?: object;
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
  type: string;
  familyId: string;
  since: number;
}

/** 云函数 push-data 参数 */
interface PushDataParams {
  type: string;
  data: object;
  version: number;
  timestamp: number;
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
   * 需要 AGC 已初始化且 Cloud DB zone 已连接
   * @returns true 表示云端服务可用
   */
  isCloudAvailable(): boolean {
    return AgcConfig.getInstance().isInitialized() &&
      AgcConfig.getInstance().getDbZone() !== null;
  }

  // ===== 核心同步接口 =====

  /**
   * 全量同步：先推本地变更，再拉云端最新数据
   *
   * 通常在应用从后台返回时由 EntryAbility.onForeground 调用。
   * 内置防抖：距上次同步不足 5 分钟时自动跳过。
   *
   * @param familyId - 当前家庭 ID
   * @returns true 表示同步完成（含部分失败），false 表示跳过或全部失败
   */
  async syncAll(familyId: string): Promise<boolean> {
    if (!this.isCloudAvailable() || !familyId) return false;
    if (this.isSyncing) return false;
    // 防抖：距上次同步不足5分钟则跳过
    if (Date.now() - this.lastSyncTime < MIN_SYNC_INTERVAL_MS) {
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
   * @param type - 数据类型名称（如 'period_records', 'medications'）
   * @param data - 要推送的数据对象
   * @param version - 数据版本号，用于冲突解决
   * @returns true 表示推送成功或已入队
   */
  async push(type: string, data: object, version: number): Promise<boolean> {
    if (!this.isCloudAvailable()) {
      // 云端不可用时静默返回，本地功能正常
      return false;
    }

    const operation: SyncOperation = {
      type,
      data,
      version,
      retryCount: 0,
      createdAt: Date.now()
    };
    this.syncQueue.push(operation);
    return await this.processQueue();
  }

  /**
   * 从云端拉取指定类型的数据
   *
   * @param type - 数据类型名称
   * @param familyId - 家庭 ID，用于过滤数据
   * @returns 数据对象数组，失败或无数据时返回空数组
   */
  async pull(type: string, familyId: string): Promise<object[]> {
    if (!this.isCloudAvailable() || !familyId) return [];

    try {
      const params: PullDataParams = {
        type,
        familyId,
        since: this.lastSyncTime
      };
      const result = await this.callCloudFunction('pull-data', params);
      return (result.data as object[]) ?? [];
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Pull failed for %{public}s: %{public}s', type, (err as Error).message);
      return [];
    }
  }

  // ===== Cloud DB 操作 =====

  /**
   * 向 Cloud DB 写入/更新数据（upsert = insert or update）
   *
   * 注意：当前需要 AGC 控制台生成的模型类实例才能执行实际写入。
   * 普通对象会导致运行时类型不匹配错误。
   *
   * @param objectType - 对象类型名称（需与 AGC 控制台定义一致）
   * @param records - 要写入的数据记录数组
   * @returns 成功写入的记录数，当前未实现时返回 0
   */
  async upsertToCloud(objectType: string, records: object[]): Promise<number> {
    const dbZone = AgcConfig.getInstance().getDbZone();
    if (!dbZone) {
      hilog.warn(DOMAIN, TAG, 'Cloud DB zone not available');
      return 0;
    }

    try {
      // TODO(AGC): upsert() 只接受 AGC 控制台生成的 ObjectTypes 模型类的实例
      // 传入普通 JS 对象会导致运行时类型不匹配错误。
      // 完成以下步骤后替换此处逻辑：
      //   1. AGC 控制台 → 云数据库 → 导出对象类型 → 生成客户端代码
      //   2. 将生成的模型类放入 entry/src/main/ets/cloud/model/
      //   3. 导入并使用 new GeneratedModelClass() 构造实例
      // 目前此方法仅记录日志，不执行实际写入
      hilog.warn(DOMAIN, TAG,
        'upsertToCloud: skipped — requires AGC-generated model classes for type %{public}s',
        objectType);
      return 0;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Cloud DB upsert failed: code=%{public}s, msg=%{public}s',
        e.code, e.message);
      return 0;
    }
  }

  /**
   * 从 Cloud DB 查询数据
   *
   * @param objectType - 对象类型名称（需与 AGC 控制台定义一致）
   * @returns 查询结果数组，失败时返回空数组
   */
  async queryFromCloud(objectType: string): Promise<object[]> {
    const dbZone = AgcConfig.getInstance().getDbZone();
    if (!dbZone) return [];

    try {
      // TODO(AGC): 需要用 AGC 生成的模型类构建 CloudDBZoneQuery
      // 当前仅记录日志，待模型类生成后替换此处逻辑
      hilog.warn(DOMAIN, TAG,
        'queryFromCloud: skipped — requires AGC-generated model classes for type %{public}s',
        objectType);
      return [];
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Cloud DB query failed: code=%{public}s, msg=%{public}s',
        e.code, e.message);
      return [];
    }
  }

  /**
   * 从 Cloud DB 删除数据
   *
   * 注意：当前需要 AGC 控制台生成的模型类实例（通过主键定位删除）。
   *
   * @param records - 要删除的数据记录数组
   * @returns 成功删除的记录数，当前未实现时返回 0
   */
  async deleteFromCloud(records: object[]): Promise<number> {
    const dbZone = AgcConfig.getInstance().getDbZone();
    if (!dbZone) return 0;

    // TODO(AGC): delete() 同样需要 AGC 生成的模型类实例（通过主键定位删除）
    // 当前返回0，待模型类生成后实现
    hilog.warn(DOMAIN, TAG, 'deleteFromCloud: skipped — requires AGC-generated model classes');
    return 0;
  }

  // ===== Cloud Function 操作 =====

  /**
   * 调用 AGC 云函数
   *
   * 已定义的云函数：
   * - push-data: 推送数据变更到 Cloud DB
   * - pull-data: 根据 familyId + 时间戳拉取增量数据
   * - validate-invite: 验证邀请码有效性
   * - merge-conflict: 服务端冲突合并（版本号优先 + last-write-wins）
   * - notify-family: 家庭成员变更通知（Cloud DB 触发，客户端被动接收推送）
   *
   * @param name - 云函数名称
   * @param params - 传递给云函数的参数对象
   * @returns 云函数返回的结构化结果 { code, message, data }
   * @throws 云函数调用失败时抛出错误
   */
  async callCloudFunction(name: string, params: object): Promise<CloudFunctionResult> {
    try {
      const result: cloudFunction.FunctionResult = await cloudFunction.call({
        name: name,
        data: params as Record<string, Object>
      });
      const raw = result.result;
      const parsed: CloudFunctionResult = (typeof raw === 'string'
        ? JSON.parse(raw)
        : raw) as CloudFunctionResult;
      hilog.info(DOMAIN, TAG, 'Cloud function %{public}s returned: code=%{public}d',
        name, parsed.code);
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
      await task.start();
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
      await task.start();
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

  // ===== 内部方法 =====

  /**
   * 处理同步队列
   */
  private async processQueue(): Promise<boolean> {
    if (this.syncQueue.length === 0) return true;

    // 快照当前队列，避免迭代期间的新 push 干扰
    const queue = [...this.syncQueue];
    this.syncQueue = [];

    this.emitProgress({
      status: SyncStatus.PUSHING, phase: 'pushing_changes',
      processed: 0, total: queue.length
    });

    let allSuccess = true;
    const failed: SyncOperation[] = [];
    let processed = 0;

    for (const op of queue) {
      processed++;
      this.emitProgress({
        status: SyncStatus.PUSHING, phase: 'pushing_changes',
        processed, total: queue.length
      });

      const success = await this.executeWithRetry(op);
      if (!success) {
        if (op.retryCount < SYNC_CONFIG.MAX_RETRIES) {
          failed.push(op);
        }
        allSuccess = false;
      }
    }

    this.syncQueue = [...failed, ...this.syncQueue];
    return allSuccess;
  }

  /**
   * 带重试的执行推送操作
   */
  private async executeWithRetry(op: SyncOperation): Promise<boolean> {
    for (let attempt = 0; attempt < SYNC_CONFIG.MAX_RETRIES; attempt++) {
      try {
        const params: PushDataParams = {
          type: op.type,
          data: op.data,
          version: op.version,
          timestamp: op.createdAt
        };
        const result = await this.callCloudFunction('push-data', params);
        return result.code === 0;
      } catch (err) {
        hilog.warn(DOMAIN, TAG,
          'Push attempt %{public}d failed for %{public}s: %{public}s',
          attempt + 1, op.type, (err as Error).message);
        if (attempt < SYNC_CONFIG.MAX_RETRIES - 1) {
          const delay = exponentialBackoff(
            attempt,
            SYNC_CONFIG.INITIAL_DELAY_MS,
            SYNC_CONFIG.MAX_DELAY_MS
          );
          await this.sleep(delay);
        }
      }
    }
    op.retryCount += 1;
    return false;
  }

  /**
   * 拉取所有类型数据并合并到本地
   * 分批并行拉取以加速，每批 4 个类型避免压垮云函数层
   */
  private async pullAll(familyId: string): Promise<boolean> {
    if (!familyId) return false;

    this.emitProgress({
      status: SyncStatus.PULLING, phase: 'pulling_updates',
      processed: 0, total: 0
    });

    const dataTypes = [
      'period_records', 'intimacy_records', 'medications', 'medication_logs',
      'health_metrics', 'kid_events', 'growth_records', 'reminders',
      'shopping_items', 'photos', 'memos', 'accounting_records', 'budgets',
      'location_places'
    ];

    const BATCH_SIZE = 4;
    let allSuccess = true;
    let processed = 0;

    for (let i = 0; i < dataTypes.length; i += BATCH_SIZE) {
      const batch = dataTypes.slice(i, Math.min(i + BATCH_SIZE, dataTypes.length));

      // 并行拉取当前批次
      const results = await Promise.allSettled(
        batch.map(type => this.pullAndMerge(type, familyId))
      );

      processed += batch.length;
      this.emitProgress({
        status: SyncStatus.PULLING, phase: 'pulling_updates',
        processed, total: dataTypes.length
      });

      // 检查批次结果
      for (const result of results) {
        if (result.status === 'rejected') {
          allSuccess = false;
        } else if (!result.value) {
          allSuccess = false;
        }
      }
    }

    return allSuccess;
  }

  /**
   * 拉取单个类型数据并合并到本地
   * @returns true 表示成功（含无数据），false 表示失败
   */
  private async pullAndMerge(type: string, familyId: string): Promise<boolean> {
    try {
      const cloudData = await this.pull(type, familyId);
      if (cloudData.length > 0) {
        await this.mergeToLocal(type, cloudData);
      }
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Pull failed for %{public}s: %{public}s',
        type, (err as Error).message);
      return false;
    }
  }

  /**
   * 合并云端数据到本地（冲突解决：版本号 + 最后修改时间）
   */
  private async mergeToLocal(type: string, cloudData: object[]): Promise<void> {
    // 具体的合并逻辑根据数据类型不同而定
    // 通用策略：版本号更高的覆盖本地的，版本号相同的用最后修改时间
    hilog.warn(DOMAIN, TAG,
      'mergeToLocal: NOT YET IMPLEMENTED — %{public}d records of type %{public}s DROPPED',
      cloudData.length, type);
    // TODO: 实现具体合并逻辑，需根据 AGC 控制台生成的模型类来完成
  }

  private emitProgress(progress: SyncProgress): void {
    if (this.syncProgressCallback) {
      this.syncProgressCallback(progress);
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
