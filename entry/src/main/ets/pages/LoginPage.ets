/**
 * 卡宝Home - 登录页面
 * 先登录再创建/加入家庭，形成清晰的 Login → Family → App 流程
 */
import { APP_NAME } from '../common/Constants';
import { AuthService } from '../service/AuthService';
import { LocalDbService } from '../service/LocalDbService';
import router from '@ohos.router';

@Entry
@Component
struct LoginPage {
  @State isLoading: boolean = true;
  @State isHuaweiLoggingIn: boolean = false;
  @State loginMessage: string = '';
  @State showOfflineOption: boolean = false;

  private auth: AuthService = AuthService.getInstance();
  private db: LocalDbService = LocalDbService.getInstance();

  aboutToAppear(): void {
    this.checkLoginStatus();
  }

  /**
   * 检查登录和家庭状态，自动跳转
   */
  private async checkLoginStatus(): Promise<void> {
    this.isLoading = true;
    // 离线选项始终可用，不依赖静默登录结果
    this.showOfflineOption = true;

    // 1. 如果已登录且有家庭，直接进入首页
    if (this.auth.isLoggedIn() && this.auth.hasFamily()) {
      try {
        router.replaceUrl({ url: 'pages/Index' });
      } catch (_) {}
      this.isLoading = false;
      return;
    }

    // 2. 如果已登录但无家庭，跳转到创建/加入家庭页面
    if (this.auth.isLoggedIn()) {
      try {
        router.replaceUrl({ url: 'pages/FamilySetupPage' });
      } catch (_) {}
      this.isLoading = false;
      return;
    }

    // 3. 未登录：尝试静默登录
    try {
      const userId = await this.auth.silentLogin();
      if (userId) {
        // 静默登录成功，根据家庭状态跳转
        if (this.auth.hasFamily()) {
          router.replaceUrl({ url: 'pages/Index' });
        } else {
          router.replaceUrl({ url: 'pages/FamilySetupPage' });
        }
        this.isLoading = false;
        return;
      }
    } catch (_) {
      // 静默登录失败，展示登录选项
    }

    // 4. 静默登录也失败，展示登录界面
    this.isLoading = false;
  }

  build() {
    Column() {
      if (this.isLoading) {
        this.LoadingView()
      } else {
        this.LoginView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  LoadingView() {
    Column({ space: 20 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color('#FF6F00')
      Text('正在检查登录状态...')
        .fontSize(14)
        .fontColor('#999999')
    }
  }

  @Builder
  LoginView() {
    Column({ space: 24 }) {
      // App Logo & 名称
      Column({ space: 8 }) {
        Image($rawfile('app_logo.png'))
          .width(80)
          .height(80)
          .borderRadius(16)
          .objectFit(ImageFit.Cover)
        Text(APP_NAME)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        Text('守护每个家人的健康与幸福')
          .fontSize(13)
          .fontColor('#999999')
      }
      .margin({ bottom: 30 })

      // 华为账号登录
      Column() {
        Row({ space: 10 }) {
          Text('🔑 华为账号登录')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF6F00')
            .layoutWeight(1)
          if (this.isHuaweiLoggingIn) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color('#FF6F00')
          }
        }
        Text('同步家庭数据到云端，多设备共享')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .width('80%')
      .padding(18)
      .borderRadius(12)
      .backgroundColor('#FFF3E0')
      .border({ width: 1, color: '#FFCC80' })
      .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 2 })
      .alignItems(HorizontalAlign.Start)
      .onClick(async () => {
        if (this.isHuaweiLoggingIn) return;
        this.isHuaweiLoggingIn = true;
        this.loginMessage = '';
        try {
          await this.auth.huaweiLogin();
          // 登录成功，跳转到家庭设置或首页
          if (this.auth.hasFamily()) {
            router.replaceUrl({ url: 'pages/Index' });
          } else {
            router.replaceUrl({ url: 'pages/FamilySetupPage' });
          }
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          this.loginMessage = `华为账号登录失败：${msg}。可使用离线模式先体验`;
        } finally {
          this.isHuaweiLoggingIn = false;
        }
      })

      // 分割线
      if (this.showOfflineOption) {
        Row() {
          Divider().layoutWeight(1).color('#E0E0E0')
          Text(' 或 ').fontSize(12).fontColor('#CCCCCC')
          Divider().layoutWeight(1).color('#E0E0E0')
        }
        .width('80%')

        // 离线使用
        Column() {
          Text('📱 离线使用')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
          Text('无需登录，数据保存在本地设备')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .width('80%')
        .padding(18)
        .borderRadius(12)
        .backgroundColor(Color.White)
        .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 2 })
        .alignItems(HorizontalAlign.Start)
        .onClick(async () => {
          try {
            await this.auth.offlineLogin();
            router.replaceUrl({ url: 'pages/FamilySetupPage' });
          } catch (_) {
            this.loginMessage = '启动失败，请重试';
          }
        })
      }

      if (this.loginMessage) {
        Text(this.loginMessage)
          .fontSize(12)
          .fontColor('#C62828')
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
  }
}
