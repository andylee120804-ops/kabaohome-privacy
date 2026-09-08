/**
 * 卡宝Home - 登录页面
 * 先登录再创建/加入家庭，形成清晰的 Login -> Family -> App 流程
 *
 * 视觉风格：方向 C · 极简编辑 - 纸白底 + 墨黑正文 + 卡宝红 CTA
 * flat 编辑风：无卡片阴影、细分隔线、锐利直角、衬线标题
 */
import { PAGE_TRANSITION_DURATION } from '../common/Constants';
import { INDEX_ROUTE_URL, FAMILY_SETUP_ROUTE_URL, shouldSkipSilentLogin } from '../common/AuthNavigation';
import { AuthService } from '../service/AuthService';
import router from '@ohos.router';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalDbService } from '../service/LocalDbService';
import { loginComponentManager, LoginWithHuaweiIDButton } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  BG_PAPER,
  BG_CARD,
  NEUTRAL_INK,
  NEUTRAL_INK_SECONDARY,
  NEUTRAL_INK_TERTIARY,
  BRAND_RED,
  BRAND_RED_LG,
  DIVIDER,
  SEMANTIC_ERROR,
  FONT_FAMILY_SERIF,
  FONT_BODY_LARGE,
  FONT_BODY,
  FONT_CAPTION,
  FONT_CAPTION_SM,
  SPACE_LG,
  SPACE_MD,
} from '../common/DesignTokens';

const TAG = '[LoginPage]';
const DOMAIN = 0x0000;

@Entry
@Component
struct LoginPage {
  // 登录选项始终在渲染树中可见，不依赖动画回调。
  // 原因：LoginWithHuaweiIDButton 是系统级组件，会绕过父层 opacity 独立渲染，
  // 若用 opacity 门控登录层可见性，state 卡住时只剩华为按钮独显。
  // 改为：登录层恒可见，loading 作为带不透明背景的覆盖层盖在其上。
  @State isLoading: boolean = false;
  @State loadingOpacity: number = 0;
  @State isHuaweiLoggingIn: boolean = false;
  @State loginMessage: string = '';

  @State showLoginOptions: boolean = true;
  @State showOfflineOption: boolean = true;

  /** 隐私政策勾选状态（集成在登录页底部，不再自动弹窗） */
  @State isPrivacyChecked: boolean = false;
  /** 是否展开隐私政策全文（点击《隐私政策》链接时打开） */
  @State showPolicyViewer: boolean = false;

  private db: LocalDbService = LocalDbService.getInstance();
  private auth: AuthService = AuthService.getInstance();
  /**
   * 华为账号登录按钮控制器
   *
   * 为什么用 LoginWithHuaweiIDButton 而不是 AuthenticationController.executeRequest：
   * LoginWithHuaweiIDRequest.forceLogin=true 时必须在「ArkUI 页面上下文」中执行，
   * 而 AuthenticationController 用 UIAbility 上下文会抛异常、用页面上下文又会
   * 触发 "environment is undefined"（见 arkts-pitfalls.md #11）。官方按钮组件内部
   * 自行处理上下文与协议弹窗，是华为推荐的登录方式。
   */
  private huaweiLoginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  /** 防止重复调用 checkLoginStatus */
  private isCheckingLogin: boolean = false;
  /** Track setTimeout IDs for cleanup on component disposal */
  private timerIds: number[] = [];

  aboutToAppear(): void {
    // 注意：此处不直接读 db（isPrivacyAgreed），因为 EntryAbility 现在 loadContent 同步执行、
    // db.init 并行异步，aboutToAppear 时 db 可能尚未初始化，ensurePrefs() 会抛异常中断初始化。
    // 隐私同意状态改在 checkLoginStatus 内 waitForDbInit 之后再读取。
    this.setupHuaweiLoginController();
    this.checkLoginStatus();
  }

  aboutDisappear(): void {
    // Clear all pending timers to prevent leaks and state updates after disposal
    for (const id of this.timerIds) {
      clearTimeout(id);
    }
    this.timerIds = [];
  }

  /**
   * 注册华为账号登录按钮回调
   * 必须在 aboutToAppear 中完成（保证 this 绑定正确），且仅注册一次。
   *
   * AgreementStatus 说明：
   * - ACCEPTED：告知华为账号 Kit 用户已在应用内同意隐私政策，Kit 不会再弹自有协议窗
   * - NOT_ACCEPTED：Kit 会在点击登录时弹出自有协议窗，用户拒绝会回调
   *   "the user did not accept the agreement" 错误。
   * 本应用改为登录页内勾选，故根据 isPrivacyChecked 同步设置，避免 Kit 二次弹窗。
   */
  private setupHuaweiLoginController(): void {
    this.huaweiLoginController
      .setAgreementStatus(this.resolveAgreementStatus())
      .onClickLoginWithHuaweiIDButton((err: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
        if (err) {
          // 1001502012 = 用户取消授权，静默不提示
          if (err.code !== 1001502012) {
            this.loginMessage = `华为账号登录失败：${err.message}`;
          }
          return;
        }
        const openID = credential?.openID ?? '';
        if (!openID) {
          this.loginMessage = '华为账号登录失败：未获取到 OpenID';
          return;
        }
        // 从 credential 中提取 idToken（用于 AGC Auth 登录）
        const credAsObj: object = credential as object;
        const idToken = (credAsObj as Record<string, Object>)?.['idToken'] as string ?? '';
        this.isHuaweiLoggingIn = true;
        this.loginMessage = '';
        this.auth.completeHuaweiLogin(openID, credential?.unionID, idToken).then(() => {
          const hasFam = this.auth.hasFamily();
          hilog.info(DOMAIN, TAG,
            'Huawei login complete: openID=%{public}s, hasFamily=%{public}s, isLoggedIn=%{public}s',
            openID, hasFam ? 'true' : 'false', this.auth.isLoggedIn() ? 'true' : 'false');
          if (hasFam) {
            router.replaceUrl({ url: INDEX_ROUTE_URL });
          } else {
            router.replaceUrl({ url: FAMILY_SETUP_ROUTE_URL });
          }
        }).catch((e: Error) => {
          this.loginMessage = `华为账号登录失败：${e.message}。可使用离线模式先体验`;
        }).finally(() => {
          this.isHuaweiLoggingIn = false;
        });
      });
  }

  private startLoading(): void {
    this.isLoading = true;
    this.loadingOpacity = 1;
  }

  private finishLoading(): void {
    // 用动画淡出 loading
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.loadingOpacity = 0;
    });
    const id = setTimeout(() => {
      this.isLoading = false;
    }, 200);
    this.timerIds.push(id);
  }

  /**
   * 检查登录和家庭状态，自动跳转
   *
   * 两条路径：
   * - 退出登录返回（explicitLogout=true）：不检查登录态、不播 loading，
   *   直接展示登录选项（登录层默认可见，无需任何 state 翻转）。
   * - 首次启动：显示 loading 检查本地登录态，已登录则跳首页/创建家庭页，
   *   未登录则淡出 loading 直接露登录选项（不自动 silentLogin，避免华为账号静默成功
   *   把首次安装用户直接跳到 FamilySetupPage，看不到登录界面）。
   *
   * db 初始化：EntryAbility 现在同步 loadContent、db.init 并行异步，所以 aboutToAppear
   * 时 db 可能尚未初始化。此处先 waitForDbInit 再读取隐私状态/登录态，避免
   * ensurePrefs() 抛异常导致初始化中断（华为按钮回调注册不上、动画不播放）。
   */
  private async checkLoginStatus(): Promise<void> {
    if (this.isCheckingLogin) return;
    this.isCheckingLogin = true;

    const params = router.getParams() as Record<string, Object> | undefined;
    // 双保险：路由参数（explicitLogout）或 AuthService 标志任一命中即跳过 silentLogin。
    // 标志防止 router.clear() 等原因导致参数丢失时，silentLogin 把用户又踢回首页。
    const skipSilentLogin = shouldSkipSilentLogin(params) || this.auth.isExplicitlyLoggedOut();

    // 退出登录返回：登录层默认可见，无需任何动画/定时器即可展示
    if (skipSilentLogin) {
      this.isLoading = false;
      // 仍需等待 db 初始化以读取隐私同意状态（同步给华为按钮 AgreementStatus）
      await this.waitForDbInit();
      this.applyPrivacyState();
      return;
    }

    // 首次启动：显示 loading 检查登录态
    this.startLoading();

    // 等 db 初始化完成（EntryAbility 异步并行 init，通常毫秒级）
    await this.waitForDbInit();
    this.applyPrivacyState();

    // 1. 如果已登录且有家庭，直接进入首页
    if (this.auth.isLoggedIn() && this.auth.hasFamily()) {
      try {
        router.replaceUrl({ url: INDEX_ROUTE_URL });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Router to Index failed: %{public}s', (err as Error).message);
      }
      this.finishLoading();
      return;
    }

    // 2. 如果已登录但无家庭，跳转到创建/加入家庭页面
    if (this.auth.isLoggedIn()) {
      try {
        router.replaceUrl({ url: FAMILY_SETUP_ROUTE_URL });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Router to FamilySetup failed: %{public}s', (err as Error).message);
      }
      this.finishLoading();
      return;
    }

    // 3. 未登录：淡出 loading，直接展示登录选项
    //
    // 不自动 silentLogin：华为账号已登录的设备上 forceLogin=false 会静默成功，
    // 首次安装（hasFamily=false）会被直接跳到 FamilySetupPage，用户根本看不到登录界面。
    // 用户期望安装后先看到登录界面（华为登录按钮 + 离线选项），主动选择登录方式。
    // 老用户（本地有 userId）由步骤 1/2 自动跳转，不受影响；silentLogin 仅在用户主动点击
    // 华为登录按钮时通过 LoginWithHuaweiIDButton 触发（forceLogin=true，需用户交互）。
    this.finishLoading();
  }

  /**
   * 等待 LocalDbService 初始化完成
   *
   * EntryAbility.onWindowStageCreate 现在同步 loadContent('pages/LoginPage')，
   * db.init 并行异步执行。aboutToAppear 时 db 可能尚未就绪，直接读 isPrivacyAgreed /
   * getCurrentUserId 会触发 ensurePrefs() 抛异常。此方法轮询等待，超时 5s 后放行
   * （超时后 applyPrivacyState 仍用 try-catch 兜底）。
   */
  private async waitForDbInit(): Promise<void> {
    if (this.db.isInitialized()) return;
    hilog.info(DOMAIN, TAG, 'Waiting for LocalDbService init...');
    const POLL_INTERVAL_MS = 50;
    const MAX_ATTEMPTS = 100; // 5s 超时
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      await new Promise<void>(resolve => setTimeout(resolve, POLL_INTERVAL_MS));
      if (this.db.isInitialized()) {
        hilog.info(DOMAIN, TAG, 'LocalDbService ready after %{public}d polls', i + 1);
        return;
      }
    }
    hilog.warn(DOMAIN, TAG, 'waitForDbInit timeout (5s), proceed with fallback');
  }

  /**
   * 读取本地隐私同意状态并同步给华为账号 Kit
   * 在 waitForDbInit 之后调用，确保 db 已就绪；仍用 try-catch 兜底超时场景。
   */
  private applyPrivacyState(): void {
    try {
      this.isPrivacyChecked = this.db.isPrivacyAgreed();
      this.huaweiLoginController.setAgreementStatus(this.resolveAgreementStatus());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyPrivacyState failed: %{public}s', (err as Error).message);
    }
  }

  /**
   * 计算当前应同步给华为账号 Kit 的 AgreementStatus
   */
  private resolveAgreementStatus(): loginComponentManager.AgreementStatus {
    return this.isPrivacyChecked
      ? loginComponentManager.AgreementStatus.ACCEPTED
      : loginComponentManager.AgreementStatus.NOT_ACCEPTED;
  }

  /**
   * 勾选/取消勾选隐私政策
   * 勾选后持久化并同步华为按钮 AgreementStatus=ACCEPTED，避免 Kit 二次弹窗；
   * 取消勾选则回退为 NOT_ACCEPTED。
   */
  private async onPrivacyToggle(checked: boolean): Promise<void> {
    this.isPrivacyChecked = checked;
    this.huaweiLoginController.setAgreementStatus(this.resolveAgreementStatus());
    if (checked) {
      try {
        await this.db.savePrivacyAgreed(true);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'savePrivacyAgreed failed: %{public}s', (e as Error).message);
      }
    }
  }

  /**
   * 未勾选时拦截登录入口的提示
   */
  private notifyPrivacyRequired(): void {
    this.loginMessage = '请先阅读并同意《隐私政策》';
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(1)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(0)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(1)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(0)
    PageTransitionEnter({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(1)
    PageTransitionExit({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(0)
  }

  build() {
    Stack() {
      // 登录选项层（底层，恒可见）
      this.LoginLayer()

      // Loading 层：覆盖在主内容之上（仅首次启动检查本地登录态时显示）
      // 编辑风：纯纸白底，无渐变
      if (this.isLoading) {
        Column() {
          this.LoadingView()
        }
        .width('100%')
        .height('100%')
        .opacity(this.loadingOpacity)
        .backgroundColor(BG_PAPER)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 隐私政策查看弹窗（点击《隐私政策》链接时展开，非自动弹出）
      if (this.showPolicyViewer) {
        this.PolicyViewerDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAPER)
  }

  /**
   * 系统加载中状态（静默登录检测阶段）
   */
  @Builder
  LoadingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(BRAND_RED)
      Text('正在检查登录状态...')
        .fontSize(FONT_CAPTION)
        .fontColor(NEUTRAL_INK_SECONDARY)
    }
  }

  /**
   * 登录选项 - 编辑极简风：顶部品牌区 + 底部操作区
   * 上部：方形 Logo + 衬线标题 + 斜体副标题（居中留白，呼吸感）
   * 下部：华为登录 / 分割线 / 离线 / 隐私协议（贴近底部，操作便捷）
   */
  @Builder
  LoginLayer() {
    Column() {
      // ===== 顶部品牌焦点区（占据剩余空间，内容垂直居中）=====
      Column({ space: 10 }) {
        // Logo: 方形红色块 + 白色衬线"卡"字
        Stack() {
          Text('卡')
            .fontSize(44)
            .fontColor(Color.White)
            .fontFamily(FONT_FAMILY_SERIF)
        }
        .width(80)
        .height(80)
        .backgroundColor(BRAND_RED_LG)
        .alignContent(Alignment.Center)

        // 标题: "卡宝Home" - "卡宝"墨黑, "Home"卡宝红斜体
        Text() {
          Span('卡宝')
            .fontColor(NEUTRAL_INK)
          Span('Home')
            .fontColor(BRAND_RED)
            .fontStyle(FontStyle.Italic)
        }
        .fontSize(36)
        .fontFamily(FONT_FAMILY_SERIF)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 6 })

        // 副标题: 斜体衬线, 三级灰
        Text('守护每个家人的健康与幸福')
          .fontSize(FONT_BODY_LARGE)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontStyle(FontStyle.Italic)
          .fontColor(NEUTRAL_INK_TERTIARY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)

      // ===== 底部操作区（编辑风：无卡片包裹，直接在纸白底上）=====
      Column({ space: 16 }) {
        // 华为账号登录
        // HuaweiLoginCard 内部已处理隐私政策拦截（未勾选时渲染占位按钮，点击提示），
        // 不再需要外层透明拦截层 -- 透明层 height('100%') 在 Stack 中会造成循环依赖，
        // 叠加系统组件异步渲染，破坏整个底部操作区布局。
        this.HuaweiLoginCard()

        // 分割线 + 离线选项
        if (this.showOfflineOption) {
          Row() {
            Divider().layoutWeight(1).color(DIVIDER)
            Text('或')
              .fontSize(FONT_CAPTION)
              .fontFamily(FONT_FAMILY_SERIF)
              .fontStyle(FontStyle.Italic)
              .fontColor(NEUTRAL_INK_TERTIARY)
              .padding({ left: 12, right: 12 })
            Divider().layoutWeight(1).color(DIVIDER)
          }
          .width('76%')

          this.OfflineCard()
        }

        // 隐私政策勾选
        this.AgreementCheckbox()

        // 错误消息
        if (this.loginMessage) {
          Text(this.loginMessage)
            .fontSize(FONT_CAPTION)
            .fontColor(SEMANTIC_ERROR)
            .padding({ left: SPACE_MD, right: SPACE_MD })
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding({ left: SPACE_LG, right: SPACE_LG, bottom: SPACE_LG })
      .alignItems(HorizontalAlign.Center)
    }
    .zIndex(0)
    .width('100%')
    .height('100%')
  }

  /**
   * 华为账号登录卡片 - 使用官方 LoginWithHuaweiIDButton 组件
   *
   * 该系统按钮内部处理华为账号授权 UI、协议弹窗与上下文，点击后通过
   * huaweiLoginController 上注册的回调返回 HuaweiIDCredential（含 openID）。
   * 自定义按钮无法触发 forceLogin=true 的授权流程，因此必须使用此组件。
   *
   * 布局稳定性：
   * LoginWithHuaweiIDButton 是系统级组件，异步渲染且首次布局时尺寸为 0。
   * 外层 Stack 用固定 height(52) 保证布局不依赖系统组件渲染时机。
   *
   * 隐私政策拦截：
   * 未勾选时在按钮上覆盖一个固定尺寸（78% × 52，与按钮完全一致）的透明拦截层，
   * 点击提示"请先同意隐私政策"。用固定尺寸而非 height('100%')，避免 Stack 循环依赖。
   * 始终渲染华为按钮（非条件渲染），保证 controller 回调正确注册，勾选后即可正常点击。
   */
  @Builder
  HuaweiLoginCard() {
    Column({ space: 6 }) {
      // 固定高度容器（52），系统按钮异步渲染不影响整体布局
      Stack() {
        LoginWithHuaweiIDButton({
          params: {
            style: loginComponentManager.Style.BUTTON_RED,
            borderRadius: 0
          },
          controller: this.huaweiLoginController
        })
          .width('78%')
          .height(52)

        // 未勾选隐私政策时覆盖拦截层（固定尺寸，与按钮一致，不用 height('100%')）
        if (!this.isPrivacyChecked) {
          Column()
            .width('78%')
            .height(52)
            .onClick(() => {
              this.notifyPrivacyRequired();
            })
        }
      }
      .width('100%')
      .height(52)
      .alignContent(Alignment.Center)

      if (this.isHuaweiLoggingIn) {
        Row({ space: 6 }) {
          LoadingProgress().width(14).height(14).color(BRAND_RED)
          Text('正在登录...')
            .fontSize(FONT_CAPTION)
            .fontColor(NEUTRAL_INK_SECONDARY)
        }
      } else {
        Text('同步家庭数据到云端，多设备共享')
          .fontSize(FONT_CAPTION_SM)
          .fontColor(NEUTRAL_INK_TERTIARY)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 离线使用按钮 - 编辑风描边款：透明底 + 墨黑描边 + 墨黑文字 + 直角
   */
  @Builder
  OfflineCard() {
    Column({ space: 6 }) {
      Button('离线使用')
        .fontSize(FONT_BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(NEUTRAL_INK)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: NEUTRAL_INK })
        .borderRadius(0)
        .width('78%')
        .height(52)

      Text('无需登录，数据保存在本地设备')
        .fontSize(FONT_CAPTION_SM)
        .fontColor(NEUTRAL_INK_TERTIARY)
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(async () => {
      if (!this.isPrivacyChecked) {
        this.notifyPrivacyRequired();
        return;
      }
      try {
        await this.auth.offlineLogin();
        // 与华为账号登录回调一致：已有家庭回首页，否则去创建/加入家庭
        router.replaceUrl({ url: this.auth.hasFamily() ? INDEX_ROUTE_URL : FAMILY_SETUP_ROUTE_URL });
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Offline login failed: %{public}s', (err as Error).message);
        this.loginMessage = '启动失败，请重试';
      }
    })
  }

  /**
   * 隐私政策勾选行 - 登录页底部，替代自动弹窗
   * 编辑风：11sp 三级灰文字 + 卡宝红下划线链接
   */
  @Builder
  AgreementCheckbox() {
    Row({ space: 6 }) {
      Checkbox()
        .select(this.isPrivacyChecked)
        .selectedColor(BRAND_RED)
        .width(18)
        .height(18)
        .onChange((value: boolean) => {
          this.onPrivacyToggle(value);
        })

      Text('我已阅读并同意')
        .fontSize(FONT_CAPTION_SM)
        .fontColor(NEUTRAL_INK_TERTIARY)

      Text('《隐私政策》')
        .fontSize(FONT_CAPTION_SM)
        .fontColor(BRAND_RED)
        .decoration({ type: TextDecorationType.Underline, color: BRAND_RED })
        .onClick(() => {
          this.showPolicyViewer = true;
        })
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .margin({ top: 4 })
  }

  /**
   * 隐私政策全文查看弹窗 - 编辑风：白底无阴影、直角、衬线标题
   */
  @Builder
  PolicyViewerDialog() {
    Stack() {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.showPolicyViewer = false;
        })

      // 弹窗卡片
      Column({ space: 12 }) {
        // 标题
        Text($r('app.string.privacy_policy_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(FONT_FAMILY_SERIF)
          .fontColor(NEUTRAL_INK)
          .width('100%')
          .textAlign(TextAlign.Center)

        // 分割线
        Divider().color(DIVIDER).margin({ top: 4, bottom: 4 })

        // 隐私政策内容（可滚动）
        Scroll() {
          Text($r('app.string.privacy_policy_content'))
            .fontSize(FONT_BODY)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .lineHeight(22)
            .width('100%')
        }
        .height(320)
        .width('100%')
        .padding({ left: 4, right: 4 })

        // 分割线
        Divider().color(DIVIDER)

        // 关闭按钮（编辑风：墨黑底白字直角）
        Button('关闭')
          .fontSize(FONT_BODY_LARGE)
          .fontColor(Color.White)
          .backgroundColor(NEUTRAL_INK)
          .borderRadius(0)
          .height(40)
          .width('100%')
          .onClick(() => {
            this.showPolicyViewer = false;
          })
      }
      .width('85%')
      .padding(20)
      .borderRadius(0)
      .backgroundColor(BG_CARD)
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
  }

}
