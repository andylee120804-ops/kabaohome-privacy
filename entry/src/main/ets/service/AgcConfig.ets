/**
 * AGC (AppGallery Connect) 初始化服务
 *
 * 职责：
 * 1. 读取 agconnect-services.json 配置
 * 2. 初始化 AGC Auth SDK（华为账号关联）
 * 3. 初始化 Cloud DB zone
 * 4. 初始化 Cloud Storage bucket
 *
 * 注意：在使用任何 AGC 服务前，必须先调用 init(context)
 *
 * @example
 * ```typescript
 * // 在 EntryAbility.onCreate 中调用
 * const agc = AgcConfig.getInstance();
 * await agc.init(this.context);
 * if (agc.isInitialized()) {
 *   const dbZone = agc.getDbZone();
 *   const isAuthReady = agc.isAuthAvailable();
 * }
 * ```
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cloudDatabase } from '@kit.CloudFoundationKit';
import { buffer } from '@kit.ArkTS';

const TAG = '[AgcConfig]';
const DOMAIN = 0x0000;

/** 云数据存储区名称 - 需与 AGC 控制台创建的 zone 一致 */
const CLOUD_DB_ZONE_NAME = 'kabaoHomeZone';

/** 云存储桶名称 - 取自 agconnect-services.json 中的 default_storage_bucket */
const CLOUD_STORAGE_BUCKET = 'kabao-pl135';

export class AgcConfig {
  private static instance: AgcConfig | null = null;
  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;
  private context: common.Context | null = null;
  private configJson: string = '';
  private dbZone: cloudDatabase.DatabaseZone | null = null;

  // AGC 配置信息
  private appId: string = '';
  private projectId: string = '';
  private packageName: string = '';

  private constructor() {}

  /** 获取 AgcConfig 单例 */
  static getInstance(): AgcConfig {
    if (!AgcConfig.instance) {
      AgcConfig.instance = new AgcConfig();
    }
    return AgcConfig.instance;
  }

  /** AGC 服务是否已初始化完成 */
  isInitialized(): boolean {
    return this.initialized;
  }

  /** 获取 AGC 应用 ID（来自 agconnect-services.json） */
  getAppId(): string {
    return this.appId;
  }

  /** 获取 AGC 项目 ID（来自 agconnect-services.json） */
  getProjectId(): string {
    return this.projectId;
  }

  /** 获取应用包名（来自 agconnect-services.json） */
  getPackageName(): string {
    return this.packageName;
  }

  /**
   * 获取 Cloud DB 数据库区域实例
   * @returns DatabaseZone 实例，未初始化或 Cloud DB 不可用时返回 null
   * @deprecated 项目通过云函数访问 Cloud DB，不直接使用客户端 SDK。保留备用。
   */
  getDbZone(): cloudDatabase.DatabaseZone | null {
    return this.dbZone;
  }

  /** 获取云存储桶名称 */
  getCloudStorageBucket(): string {
    return CLOUD_STORAGE_BUCKET;
  }

  /** 获取已保存的应用上下文，未初始化时返回 null */
  getContext(): common.Context | null {
    return this.context;
  }

  /**
   * 初始化 AGC 服务 - 必须在 EntryAbility.onCreate 中调用
   *
   * 初始化顺序：
   * 1. 读取 rawfile/agconnect-services.json
   * 2. 解析 appId / projectId / packageName
   * 3. 初始化 AGC Auth SDK
   * 4. 初始化 Cloud DB Zone（失败时降级为本地模式）
   *
   * 该方法是幂等的，多次调用安全。并发调用会复用同一个 Promise。
   *
   * @param context - 应用上下文（UIAbility.context）
   * @returns 初始化完成（无论成功失败都不抛出异常，失败时降级为本地模式）
   */
  async init(context: common.Context): Promise<void> {
    if (this.initialized) {
      hilog.info(DOMAIN, TAG, 'Already initialized, skipping');
      return;
    }
    // 复用同一个初始化 Promise，防止并发调用导致重复初始化
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.doInit(context);
    return this.initPromise;
  }

  private async doInit(context: common.Context): Promise<void> {
    this.context = context;

    try {
      // 1. 读取 agconnect-services.json
      const file = context.resourceManager.getRawFileContentSync('agconnect-services.json');
      this.configJson = buffer.from(file.buffer).toString();
      hilog.info(DOMAIN, TAG, 'agconnect-services.json loaded');

      // 2. 解析关键配置
      this.parseConfig();

      // 3. AGC Auth SDK 已由 @kit.CloudFoundationKit 内置，无需单独初始化
      hilog.info(DOMAIN, TAG, 'AGC Auth SDK available via CloudFoundationKit');

      // 4. 初始化 Cloud DB Zone
      //    注意：此步骤要求 AGC 控制台已创建对应 zone 和 object types
      //    如果尚未配置，会 catch 降级，不影响本地功能
      try {
        this.dbZone = cloudDatabase.zone(CLOUD_DB_ZONE_NAME);
        hilog.info(DOMAIN, TAG, 'Cloud DB zone initialized: %{public}s', CLOUD_DB_ZONE_NAME);
      } catch (dbErr) {
        hilog.warn(DOMAIN, TAG, 'Cloud DB zone init failed (need AGC console config): %{public}s',
          (dbErr as Error).message);
        // 降级：本地功能不受影响，仅云端同步不可用
      }

      this.initialized = true;
      hilog.info(DOMAIN, TAG, 'AGC initialization completed');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'AGC init failed: %{public}s', (err as Error).message);
      // 降级处理：不抛出异常，允许应用以纯本地模式运行
    }
  }

  /**
   * 获取 AGC Auth 实例
   * CloudFoundationKit 内置认证服务，无需单独获取实例
   *
   * @returns true 表示已初始化可用
   */
  isAuthAvailable(): boolean {
    return this.initialized;
  }

  /** 解析 agconnect-services.json 中的关键字段 */
  private parseConfig(): void {
    try {
      const config = JSON.parse(this.configJson) as Record<string, Object>;
      const client = (config['client'] as Record<string, Object>) ?? {};
      this.appId = (client['app_id'] as string) ?? '';
      this.projectId = (client['project_id'] as string) ?? '';
      this.packageName = (client['package_name'] as string) ?? '';
      hilog.info(DOMAIN, TAG,
        'Config parsed: appId=%{public}s, projectId=%{public}s, pkg=%{public}s',
        this.appId, this.projectId, this.packageName);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Parse config failed: %{public}s', (err as Error).message);
    }
  }
}
