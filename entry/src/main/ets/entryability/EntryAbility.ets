/**
 * 卡宝Home - 应用入口
 *
 * 初始化顺序：
 * 1. AGC 服务初始化（Auth/CloudDB/CloudStorage）
 * 2. 本地数据库初始化
 * 3. 华为账号 Provider 注入
 * 4. 系统提醒刷新
 * 5. 页面路由
 */
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalDbService } from '../service/LocalDbService';
import { AuthService } from '../service/AuthService';
import { HuaweiAccountProvider } from '../service/HuaweiAccountProvider';
import { ReminderService } from '../service/ReminderService';
import { AgcConfig } from '../service/AgcConfig';
import { CloudService } from '../service/CloudService';

const TAG = '[EntryAbility]';
const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');

    // 1. 先初始化 AGC 服务（Cloud DB/Auth/CloudStorage）
    const agc = AgcConfig.getInstance();
    agc.init(this.context).then(() => {
      hilog.info(DOMAIN, TAG, 'AGC initialized');
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'AGC init failed (app runs in local mode): %{public}s', err.message);
    });

    // 2. 注入华为账号登录实现
    const auth = AuthService.getInstance();
    auth.setContext(this.context);
    auth.setHuaweiLoginProvider(
      HuaweiAccountProvider.silentLogin,
      HuaweiAccountProvider.explicitLogin
    );

    // 3. 注入 AGC 配置（用于 Auth 关联）
    auth.setAgcConfig(agc);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate');

    // 初始化本地数据库，再加载页面
    const db = LocalDbService.getInstance();
    db.init(this.context).then(() => {
      hilog.info(DOMAIN, TAG, 'LocalDbService initialized');
      this.requestNotificationEnable();
      this.refreshSystemReminders();
      this.initAuthAndRoute(windowStage);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'LocalDbService init failed: %{public}s', err.message);
      // 即使初始化失败也尝试加载页面
      this.initAuthAndRoute(windowStage);
    });
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
    // 每次从后台返回时：刷新系统提醒 + 触发云端同步
    this.refreshSystemReminders();
    this.triggerCloudSync();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  /**
   * 请求通知授权（用户同意后才能发送系统提醒）
   */
  private requestNotificationEnable(): void {
    notificationManager.requestEnableNotification(this.context).then(() => {
      hilog.info(DOMAIN, TAG, 'Notification enabled');
    }).catch((err: BusinessError) => {
      if (err.code === 1600004) {
        hilog.warn(DOMAIN, TAG, 'User denied notification authorization');
      } else {
        hilog.warn(DOMAIN, TAG, 'Notification request failed: %{public}s', err.message);
      }
    });
  }

  /**
   * 刷新所有系统提醒（用药提醒、家庭提醒、周期提醒等）
   */
  private refreshSystemReminders(): void {
    try {
      const db = LocalDbService.getInstance();
      if (!db.isInitialized()) return;
      ReminderService.getInstance().refreshAllReminders();
      hilog.info(DOMAIN, TAG, 'System reminders refreshed');
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to refresh reminders: %{public}s',
        (err as Error).message);
    }
  }

  /**
   * 从后台返回时触发云端同步
   * 先将本地变更推送到云端，再从云端拉取最新数据
   */
  private triggerCloudSync(): void {
    try {
      const agc = AgcConfig.getInstance();
      if (!agc.isInitialized()) return;
      const db = LocalDbService.getInstance();
      if (!db.isInitialized()) return;
      // CloudService 会在后台处理 push/pull，不阻塞 UI
      CloudService.getInstance().syncAll(db.getCurrentFamilyId());
    } catch (err) {
      // 同步失败不影响本地功能
      hilog.warn(DOMAIN, TAG, 'Cloud sync skipped: %{public}s', (err as Error).message);
    }
  }

  /**
   * 加载登录页面，LoginPage 内部会根据状态自动跳转
   */
  private initAuthAndRoute(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Routing to LoginPage');
    windowStage.loadContent('pages/LoginPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load LoginPage: %{public}s', JSON.stringify(err));
        // 回退：尝试直接加载 FamilySetupPage
        windowStage.loadContent('pages/FamilySetupPage', (err2) => {
          if (err2.code) {
            hilog.error(DOMAIN, TAG, 'Failed to load FamilySetupPage: %{public}s', JSON.stringify(err2));
          }
        });
      }
    });
  }
}
