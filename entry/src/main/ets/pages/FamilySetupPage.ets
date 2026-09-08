/**
 * 卡宝Home - 创建/加入家庭页面
 * 登录已在 LoginPage 完成，此页只负责家庭的创建或加入
 * 视觉风格：编辑式卡片 + 暖色品牌渐变 + 清晰层级
 */
import { APP_NAME, MEMBER_COLORS, MemberRole , PAGE_TRANSITION_DURATION } from '../common/Constants';
import { BG_PAPER, BORDER_SUBTLE, BRAND_CORAL, NEUTRAL_INK_TERTIARY, SEMANTIC_INFO, BG_SUBTLE, ERROR_BG, INFO_BG, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, SEMANTIC_ERROR, SEMANTIC_SUCCESS, SEMANTIC_WARNING, WARNING_BG, MIST_PURPLE } from '../common/DesignTokens';
import { AuthService } from '../service/AuthService';
import { Family } from '../model/Family';
import router from '@ohos.router';
import { curves } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { scanCore, scanBarcode } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { LOGIN_ROUTE_URL, buildExplicitLogoutRouteParams } from '../common/AuthNavigation';

interface RoleOption {
  role: MemberRole;
  label: string;
  emoji: string;
  color: string;
}

@Entry
@Component
struct FamilySetupPage {
  @State setupMode: string = ''; // '' | 'create' | 'join' | 'join_phone' | 'claim' | 'success'
  @State familyName: string = '';
  @State inviteCode: string = '';
  @State memberName: string = '';
  @State selectedRole: MemberRole = MemberRole.DAD;
  @State selectedColor: string = MEMBER_COLORS[0];
  @State joinPhone: string = '';
  @State claimToken: string = '';
  @State errorMessage: string = '';
  @State createdFamily: Family | null = null;
  @State generatedInviteCode: string = '';
  @State successMode: string = 'create';
  @State copySuccess: boolean = false;
  @State showQrCode: boolean = false;
  @State isSubmitting: boolean = false;
  private auth: AuthService = AuthService.getInstance();
  /** Track setTimeout IDs for cleanup on component disposal */
  private timerIds: number[] = [];

  // 品牌色板
  private readonly BRAND_PRIMARY: string = SEMANTIC_WARNING;
  private readonly BRAND_BG_TOP: string = BG_PAPER;
  private readonly BRAND_BG_BOT: string = BG_PAPER;
  private readonly TEXT_PRIMARY: string = NEUTRAL_INK;
  private readonly TEXT_SECONDARY: string = NEUTRAL_INK_TERTIARY;
  private readonly TEXT_HINT: string = NEUTRAL_INK_SECONDARY;
  private readonly SURFACE: string = '#FFFFFF';
  private readonly BORDER_LIGHT: string = BORDER_SUBTLE;

  private roleOptions: RoleOption[] = [
    { role: MemberRole.DAD, label: '爸爸', emoji: '👨', color: SEMANTIC_INFO },
    { role: MemberRole.MOM, label: '妈妈', emoji: '👩', color: BRAND_CORAL },
    { role: MemberRole.GRANDPA, label: '爷爷', emoji: '👴', color: SEMANTIC_ERROR },
    { role: MemberRole.GRANDMA, label: '奶奶', emoji: '👵', color: SEMANTIC_WARNING },
    { role: MemberRole.CHILD, label: '孩子', emoji: '🧒', color: SEMANTIC_SUCCESS },
    { role: MemberRole.OTHER, label: '其他', emoji: '🧑', color: MIST_PURPLE }
  ];

  aboutToAppear(): void {
    this.familyName = '';
    this.inviteCode = '';
    this.memberName = '';
    this.errorMessage = '';
    this.createdFamily = null;
    this.generatedInviteCode = '';

    // 已登录且有家庭 → 直接进入首页（安全守卫）
    if (this.auth.isLoggedIn() && this.auth.hasFamily()) {
      try {
        router.replaceUrl({ url: 'pages/Index' });
      } catch (_) {}
      return;
    }
    // 未登录 → 回到登录页
    if (!this.auth.isLoggedIn()) {
      try {
        router.replaceUrl({ url: 'pages/LoginPage' });
      } catch (_) {}
      return;
    }
    this.setupMode = '';
  }

  aboutDisappear(): void {
    // Clear all pending timers to prevent leaks and state updates after disposal
    for (const id of this.timerIds) {
      clearTimeout(id);
    }
    this.timerIds = [];
  }

  /**
   * 系统返回键/手势拦截：交给 goBack 统一处理，避免在 replaceUrl 后栈空导致直接退出 App
   */
  onBackPress(): boolean {
    this.goBack();
    return true; // 拦截系统默认返回行为
  }

  /**
   * 安全返回：根据当前子页面决定行为
   * - 子模式（create/join 等）→ 返回选择视图
   * - 选择视图 → 退出当前登录态，回到 LoginPage 并带上 explicitLogout 参数，
   *   让 LoginPage 跳过 silentLogin，直接展示华为账号登录界面（否则静默登录成功
   *   会把人又踢回 FamilySetupPage，形成“返回无反应”的死循环）
   */
  private goBack(): void {
    if (this.setupMode === 'join_phone' || this.setupMode === 'claim') {
      this.setupMode = 'join';
      this.errorMessage = '';
      return;
    }
    if (this.setupMode === 'create' || this.setupMode === 'join') {
      this.setupMode = '';
      this.errorMessage = '';
      return;
    }
    // 在选择视图直接退到登录页：登出后带 explicitLogout 跳转，强制展示登录选项
    const goLogin = (): void => {
      try {
        router.replaceUrl({ url: LOGIN_ROUTE_URL, params: buildExplicitLogoutRouteParams() });
      } catch (_) {}
    };
    this.auth.logout().then(goLogin).catch(goLogin);
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Bottom)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Bottom)
    PageTransitionEnter({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(1)
    PageTransitionExit({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(0)
  }

  build() {
    Stack() {
      // 暖色品牌背景渐变
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[this.BRAND_BG_TOP, 0.0], [this.BRAND_BG_BOT, 0.55]]
        })

      Column() {
        if (this.setupMode === 'create') {
          this.CreateFamilyView()
        } else if (this.setupMode === 'join') {
          this.JoinFamilyView()
        } else if (this.setupMode === 'join_phone') {
          this.JoinByPhoneView()
        } else if (this.setupMode === 'claim') {
          this.ClaimMemberView()
        } else if (this.setupMode === 'success') {
          this.SuccessView()
        } else {
          this.SelectionView()
        }
      }
      .width('100%')
      .height('100%')

      this.QrCodeOverlay()
    }
    .width('100%')
    .height('100%')
  }

  /** 通用顶部导航条 */
  @Builder
  TopBar(title: string) {
    Row() {
      // 返回按钮
      Stack() {
        Text('‹')
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.TEXT_PRIMARY)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor('#FFFFFFCC')
      .shadow({ radius: 6, color: '#14000000', offsetX: 0, offsetY: 2 })
      .onClick(() => this.goBack())

      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.TEXT_PRIMARY)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // 占位，保持标题居中
      Column().width(40).height(40)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  /** 错误提示条 */
  @Builder
  ErrorBanner() {
    if (this.errorMessage) {
      Row() {
        Text('⚠️').fontSize(14).margin({ right: 6 })
        Text(this.errorMessage)
          .fontSize(13)
          .fontColor(SEMANTIC_ERROR)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ERROR_BG)
      .borderRadius(8)
    }
  }

  /** 角色选择行 */
  @Builder
  RoleSelector() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.roleOptions, (item: RoleOption) => {
        Row({ space: 4 }) {
          Text(item.emoji).fontSize(15)
          Text(item.label)
            .fontSize(14)
            .fontWeight(this.selectedRole === item.role ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selectedRole === item.role ? Color.White : this.TEXT_PRIMARY)
        }
        .padding({ left: 14, right: 14, top: 9, bottom: 9 })
        .borderRadius(20)
        .backgroundColor(this.selectedRole === item.role ? item.color : BG_SUBTLE)
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          this.selectedRole = item.role;
          this.selectedColor = item.color;
        })
      }, (item: RoleOption) => item.role)
    }
    .width('100%')
  }

  // ============= 选择视图 =============
  @Builder
  SelectionView() {
    Column() {
      this.TopBar('开始使用')

      Scroll() {
        Column() {
          // 品牌头部
          Column({ space: 10 }) {
            // App Logo
            Image($r('app.media.app_icon'))
              .width(96)
              .height(96)
              .borderRadius(48)
              .objectFit(ImageFit.Cover)
              .shadow({ radius: 18, color: '#33B8862E', offsetX: 0, offsetY: 8 })
              .margin({ top: 24 })

            Text(`欢迎使用 ${APP_NAME}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.TEXT_PRIMARY)
              .margin({ top: 12 })

            Text('选择一种方式，开启家人共享之旅')
              .fontSize(13)
              .fontColor(this.TEXT_SECONDARY)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ bottom: 32 })

          // 创建家庭卡片
          Row() {
            Stack() {
              Column()
                .width(54).height(54).borderRadius(16)
                .backgroundColor(WARNING_BG)
              Text('🏡').fontSize(28)
            }
            Column({ space: 4 }) {
              Text('创建家庭')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.TEXT_PRIMARY)
              Text('我是家里第一个使用的人')
                .fontSize(13)
                .fontColor(this.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 14 })
            Text('›')
              .fontSize(24)
              .fontColor(this.TEXT_HINT)
          }
          .width('100%')
          .padding(18)
          .borderRadius(16)
          .backgroundColor(this.SURFACE)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 4 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.setupMode = 'create'; this.errorMessage = ''; })

          // 加入家庭卡片
          Row() {
            Stack() {
              Column()
                .width(54).height(54).borderRadius(16)
                .backgroundColor(INFO_BG)
              Text('🤝').fontSize(28)
            }
            Column({ space: 4 }) {
              Text('加入家庭')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.TEXT_PRIMARY)
              Text('家人已经创建了家庭')
                .fontSize(13)
                .fontColor(this.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 14 })
            Text('›')
              .fontSize(24)
              .fontColor(this.TEXT_HINT)
          }
          .width('100%')
          .padding(18)
          .borderRadius(16)
          .backgroundColor(this.SURFACE)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 4 })
          .alignItems(VerticalAlign.Center)
          .margin({ top: 14 })
          .onClick(() => { this.setupMode = 'join'; this.errorMessage = ''; })

          // 错误提示
          if (this.errorMessage) {
            Column() {
              this.ErrorBanner()
            }
            .margin({ top: 16 })
          }

          // 底部小提示
          Column() {
            Text('您的所有数据将保存在设备本地，安全私密')
              .fontSize(12)
              .fontColor(this.TEXT_HINT)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .margin({ top: 32, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ============= 创建家庭 =============
  @Builder
  CreateFamilyView() {
    Column() {
      this.TopBar('创建家庭')

      Scroll() {
        Column({ space: 20 }) {
          // 头部说明
          Column({ space: 6 }) {
            Text('🏡 新建一个温馨小家')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.TEXT_PRIMARY)
            Text('填写家庭名称和你的称呼，邀请家人加入')
              .fontSize(13)
              .fontColor(this.TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: 8 })

          // 表单卡片
          Column({ space: 18 }) {
            // 家庭名称
            Column() {
              Text('家庭名称').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '如：温馨小家', text: this.familyName })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .maxLength(20)
                  .onChange((v: string) => { this.familyName = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 你的称呼
            Column() {
              Text('你的称呼').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '如：妈妈、爸爸、宝宝', text: this.memberName })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .maxLength(10)
                  .onChange((v: string) => { this.memberName = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 选择角色
            Column() {
              Text('选择身份').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              this.RoleSelector()
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // 颜色选择
            Column() {
              Text('颜色标识').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Row({ space: 12 }) {
                ForEach(MEMBER_COLORS.slice(0, 6), (color: string) => {
                  Stack() {
                    Circle()
                      .width(this.selectedColor === color ? 36 : 32)
                      .height(this.selectedColor === color ? 36 : 32)
                      .fill(color)
                    if (this.selectedColor === color) {
                      Text('✓').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    }
                  }
                  .width(40).height(40)
                  .onClick(() => { this.selectedColor = color; })
                }, (color: string) => color)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor(this.SURFACE)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 4 })

          this.ErrorBanner()

          Button(this.isSubmitting ? '创建中...' : '创建家庭')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.BRAND_PRIMARY)
            .borderRadius(25)
            .shadow({ radius: 12, color: '#33B8862E', offsetX: 0, offsetY: 4 })
            .enabled(!this.isSubmitting)
            .onClick(async () => {
              if (this.isSubmitting) return;
              if (!this.familyName || !this.familyName.trim()) {
                this.errorMessage = '请填写家庭名称';
                return;
              }
              if (!this.memberName || !this.memberName.trim()) {
                this.errorMessage = '请填写你的称呼';
                return;
              }
              this.isSubmitting = true;
              this.errorMessage = '';
              try {
                const family = await this.auth.createFamily(
                  this.familyName.trim(),
                  this.memberName.trim(),
                  this.selectedRole,
                  this.selectedColor
                );
                this.createdFamily = family;
                this.generatedInviteCode = family.inviteCode;
                this.successMode = 'create';
                this.setupMode = 'success';
              } catch (e) {
                this.errorMessage = e instanceof Error ? e.message : '创建失败，请重试';
              } finally {
                this.isSubmitting = false;
              }
            })

          Column().height(20)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ============= 加入家庭 =============
  @Builder
  JoinFamilyView() {
    Column() {
      this.TopBar('加入家庭')

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 6 }) {
            Text('🤝 加入家人的家庭')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.TEXT_PRIMARY)
            Text('请向家人索取 6 位邀请码')
              .fontSize(13)
              .fontColor(this.TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: 8 })

          // 表单卡片
          Column({ space: 18 }) {
            Column() {
              Text('家庭邀请码').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '输入 6 位邀请码', text: this.inviteCode })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .type(InputType.Normal)
                  .inputFilter('^\\d{0,6}$', (_value: string) => {})
                  .maxLength(6)
                  .onChange((v: string) => { this.inviteCode = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Column() {
              Text('你的称呼').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '如：爸爸、奶奶', text: this.memberName })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .maxLength(10)
                  .onChange((v: string) => { this.memberName = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Column() {
              Text('选择身份').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              this.RoleSelector()
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor(this.SURFACE)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 4 })

          this.ErrorBanner()

          Button(this.isSubmitting ? '加入中...' : '加入家庭')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.BRAND_PRIMARY)
            .borderRadius(25)
            .shadow({ radius: 12, color: '#33B8862E', offsetX: 0, offsetY: 4 })
            .enabled(!this.isSubmitting)
            .onClick(async () => {
              if (this.isSubmitting) return;
              if (!this.inviteCode || this.inviteCode.length !== 6) {
                this.errorMessage = '请输入 6 位邀请码';
                return;
              }
              if (!this.memberName || !this.memberName.trim()) {
                this.errorMessage = '请填写你的称呼';
                return;
              }
              this.isSubmitting = true;
              this.errorMessage = '';
              try {
                const family = await this.auth.joinFamilyByCode(
                  this.inviteCode,
                  this.memberName.trim(),
                  this.selectedRole
                );
                if (family) {
                  this.createdFamily = family;
                  this.generatedInviteCode = family.inviteCode;
                  this.successMode = 'join';
                  this.setupMode = 'success';
                } else {
                  this.errorMessage = '邀请码无效或已过期，请确认后重试';
                }
              } catch (e) {
                this.errorMessage = e instanceof Error ? e.message : '加入失败，请重试';
              } finally {
                this.isSubmitting = false;
              }
            })

          // 其他方式
          Column({ space: 12 }) {
            Row() {
              Divider().layoutWeight(1).color(this.BORDER_LIGHT)
              Text(' 其他方式 ').fontSize(12).fontColor(this.TEXT_HINT)
              Divider().layoutWeight(1).color(this.BORDER_LIGHT)
            }
            .width('100%')

            Row({ space: 12 }) {
              Column({ space: 6 }) {
                Text('📱').fontSize(24)
                Text('手机号搜索').fontSize(12).fontColor(this.TEXT_PRIMARY)
              }
              .layoutWeight(1)
              .padding(14)
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
              .onClick(() => { this.setupMode = 'join_phone'; this.errorMessage = ''; })

              Column({ space: 6 }) {
                Text('👤').fontSize(24)
                Text('认领身份').fontSize(12).fontColor(this.TEXT_PRIMARY)
              }
              .layoutWeight(1)
              .padding(14)
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
              .onClick(() => { this.setupMode = 'claim'; this.errorMessage = ''; })

              Column({ space: 6 }) {
                Text('📷').fontSize(24)
                Text('扫码加入').fontSize(12).fontColor(this.TEXT_PRIMARY)
              }
              .layoutWeight(1)
              .padding(14)
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
              .onClick(() => { this.startScan(); })
            }
            .width('100%')
          }
          .width('100%')
          .margin({ top: 8 })

          Column().height(20)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ============= 手机号搜索 =============
  @Builder
  JoinByPhoneView() {
    Column() {
      this.TopBar('手机号搜索')

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 6 }) {
            Text('📱 通过手机号查找家人')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.TEXT_PRIMARY)
            Text('输入家人手机号，系统将向其发送加入申请')
              .fontSize(13)
              .fontColor(this.TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: 8 })

          Column({ space: 18 }) {
            Column() {
              Text('家人手机号').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '输入家人的手机号', text: this.joinPhone })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .type(InputType.PhoneNumber)
                  .maxLength(11)
                  .onChange((v: string) => { this.joinPhone = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Column() {
              Text('你的称呼').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '如：爸爸、奶奶', text: this.memberName })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .maxLength(10)
                  .onChange((v: string) => { this.memberName = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor(this.SURFACE)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 4 })

          this.ErrorBanner()

          Button('搜索并加入')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.BRAND_PRIMARY)
            .borderRadius(25)
            .shadow({ radius: 12, color: '#33B8862E', offsetX: 0, offsetY: 4 })
            .onClick(() => {
              this.errorMessage = 'V2 版本将支持手机号搜索加入';
            })

          Row() {
            Text('💡').fontSize(14).margin({ right: 6 })
            Text('V2 版本将支持通过手机号搜索已注册家人')
              .fontSize(12)
              .fontColor(this.TEXT_SECONDARY)
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(8)
          .backgroundColor(WARNING_BG)

          Column().height(20)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ============= 认领身份 =============
  @Builder
  ClaimMemberView() {
    Column() {
      this.TopBar('认领身份')

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 6 }) {
            Text('👤 认领家人为你创建的身份')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.TEXT_PRIMARY)
            Text('家人已在自己设备上为你添加身份并生成认领码')
              .fontSize(13)
              .fontColor(this.TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .margin({ top: 8 })

          Column({ space: 18 }) {
            Column() {
              Text('认领码').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.TEXT_SECONDARY).width('100%').margin({ bottom: 8 })
              Column() {
                TextInput({ placeholder: '输入 6 位认领码', text: this.claimToken })
                  .placeholderColor(this.TEXT_HINT)
                  .placeholderFont({ size: 14 })
                  .fontSize(15)
                  .fontColor(this.TEXT_PRIMARY)
                  .backgroundColor(Color.Transparent)
                  .height(48)
                  .padding({ left: 14, right: 14 })
                  .type(InputType.Normal)
                  .inputFilter('^\\d{0,6}$', (_value: string) => {})
                  .maxLength(6)
                  .onChange((v: string) => { this.claimToken = v; })
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(this.SURFACE)
              .border({ width: 1, color: this.BORDER_LIGHT })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor(this.SURFACE)
          .shadow({ radius: 10, color: '#0D000000', offsetX: 0, offsetY: 4 })

          this.ErrorBanner()

          Button(this.isSubmitting ? '认领中...' : '认领身份')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(SEMANTIC_SUCCESS)
            .borderRadius(25)
            .shadow({ radius: 12, color: '#333D6B5C', offsetX: 0, offsetY: 4 })
            .enabled(!this.isSubmitting)
            .onClick(async () => {
              if (this.isSubmitting) return;
              if (!this.claimToken || this.claimToken.length !== 6) {
                this.errorMessage = '请输入 6 位认领码';
                return;
              }
              this.isSubmitting = true;
              this.errorMessage = '';
              try {
                const member = await this.auth.claimMemberByToken(this.claimToken);
                if (member) {
                  const family = this.auth.getFamily();
                  this.createdFamily = family;
                  this.generatedInviteCode = family?.inviteCode ?? '';
                  this.successMode = 'claim';
                  this.setupMode = 'success';
                } else {
                  this.errorMessage = '认领码无效或已过期，请确认后重试';
                }
              } catch (e) {
                this.errorMessage = e instanceof Error ? e.message : '认领失败，请重试';
              } finally {
                this.isSubmitting = false;
              }
            })

          Column({ space: 8 }) {
            Row() {
              Text('💡').fontSize(14).margin({ right: 6 })
              Text('没有认领码？让家人在「我的-成员管理」中添加你后，把认领码发给你')
                .fontSize(12)
                .fontColor(this.TEXT_SECONDARY)
                .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .borderRadius(8)
            .backgroundColor(WARNING_BG)

            Row() {
              Text('或者直接用家庭邀请码加入')
                .fontSize(13)
                .fontColor(this.BRAND_PRIMARY)
                .fontWeight(FontWeight.Medium)
              Text(' ›')
                .fontSize(14)
                .fontColor(this.BRAND_PRIMARY)
            }
            .padding(8)
            .onClick(() => { this.setupMode = 'join'; this.errorMessage = ''; })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 4 })

          Column().height(20)
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  // ============= 成功页 =============
  @Builder
  SuccessView() {
    Column() {
      this.TopBar(' ')

      Scroll() {
        Column() {
          // 成功图标 + 光晕
          Stack() {
            Column()
              .width(120).height(120).borderRadius(60)
              .linearGradient({
                angle: 135,
                colors: [[WARNING_BG, 0.0], [WARNING_BG, 1.0]]
              })
              .shadow({ radius: 24, color: '#33B8862E', offsetX: 0, offsetY: 10 })
            Text('🎉').fontSize(60)
          }
          .margin({ top: 24, bottom: 18 })

          Text(
            this.successMode === 'claim' ? '身份已认领！' :
              (this.successMode === 'join' || this.successMode === 'join_phone') ? '已加入家庭！' :
                '家庭创建成功！'
          )
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.TEXT_PRIMARY)

          Text(
            this.successMode === 'create' ? '邀请家人扫码或输入邀请码即可加入' :
              this.successMode === 'claim' ? '你已成功加入家庭，可以开始使用了' :
                '欢迎来到家人共享的小天地'
          )
            .fontSize(13)
            .fontColor(this.TEXT_SECONDARY)
            .margin({ top: 6 })

          // 家庭信息卡片
          if (this.createdFamily) {
            Column({ space: 14 }) {
              Row() {
                Text('🏡')
                  .fontSize(18)
                  .margin({ right: 8 })
                Column({ space: 2 }) {
                  Text('家庭名称')
                    .fontSize(12)
                    .fontColor(this.TEXT_HINT)
                  Text(this.createdFamily.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.TEXT_PRIMARY)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Divider().color(this.BORDER_LIGHT)

              Column({ space: 8 }) {
                Text('家庭邀请码')
                  .fontSize(12)
                  .fontColor(this.TEXT_HINT)
                Text(this.generatedInviteCode)
                  .fontSize(36)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.BRAND_PRIMARY)
                  .letterSpacing(8)
                Text('7 天内有效')
                  .fontSize(11)
                  .fontColor(this.TEXT_HINT)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 4, bottom: 4 })

              Row({ space: 10 }) {
                Button(this.copySuccess ? '已复制 ✓' : '复制邀请码')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.copySuccess ? this.BRAND_PRIMARY : Color.White)
                  .backgroundColor(this.copySuccess ? WARNING_BG : this.BRAND_PRIMARY)
                  .borderRadius(20)
                  .layoutWeight(1)
                  .height(40)
                  .onClick(async () => {
                    try {
                      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.generatedInviteCode);
                      const systemPasteboard = pasteboard.getSystemPasteboard();
                      await systemPasteboard.setData(pasteData);
                      this.copySuccess = true;
                      const id = setTimeout(() => { this.copySuccess = false; }, 2000);
                      this.timerIds.push(id);
                    } catch (_) {}
                  })
                Button('分享二维码')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.BRAND_PRIMARY)
                  .backgroundColor(Color.White)
                  .border({ width: 1, color: this.BRAND_PRIMARY })
                  .borderRadius(20)
                  .layoutWeight(1)
                  .height(40)
                  .onClick(() => { this.showQrCode = true; })
              }
              .width('100%')
            }
            .width('100%')
            .padding(20)
            .borderRadius(16)
            .backgroundColor(this.SURFACE)
            .shadow({ radius: 12, color: '#0D000000', offsetX: 0, offsetY: 6 })
            .margin({ top: 24 })

            Text('将邀请码分享给家人，让他们加入这个家庭')
              .fontSize(12)
              .fontColor(this.TEXT_HINT)
              .margin({ top: 12 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 20, right: 20, bottom: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部固定按钮区域
      Column() {
        Button(`进入 ${APP_NAME}`)
          .width('100%')
          .height(50)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.BRAND_PRIMARY)
          .borderRadius(25)
          .shadow({ radius: 12, color: '#33B8862E', offsetX: 0, offsetY: 4 })
          .onClick(() => {
            try {
              router.replaceUrl({ url: 'pages/Index' });
            } catch (_) {}
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 36 })
    }
    .width('100%')
    .height('100%')
  }

  /** 扫码识别邀请码 */
  private startScan(): void {
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };
      const context = getContext(this) as common.UIAbilityContext;
      scanBarcode.startScanForResult(context, options).then((result: scanBarcode.ScanResult) => {
        const code = result.originalValue.trim();
        if (code && /^\d{6}$/.test(code)) {
          this.inviteCode = code;
          this.setupMode = 'join';
          this.errorMessage = '';
        } else {
          this.errorMessage = '扫描结果不是有效的6位邀请码，请手动输入';
        }
      }).catch(() => {
        // 扫码取消或失败，静默处理
      });
    } catch (_) {
      this.errorMessage = '扫码功能暂不可用，请手动输入邀请码';
    }
  }

  // ============= 二维码弹窗 =============
  @Builder
  QrCodeOverlay() {
    if (this.showQrCode) {
      Column() {
        Column() {
          Text('家庭邀请二维码')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.TEXT_PRIMARY)
            .margin({ bottom: 16 })

          Column() {
            QRCode(this.generatedInviteCode)
              .width(200)
              .height(200)
              .color(NEUTRAL_INK)
              .backgroundColor(Color.White)
          }
          .width(220)
          .height(220)
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor(Color.White)
          .margin({ bottom: 16 })

          Text(this.generatedInviteCode)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.BRAND_PRIMARY)
            .letterSpacing(6)
            .margin({ bottom: 8 })

          Text('家人扫描此二维码即可获取邀请码')
            .fontSize(13)
            .fontColor(this.TEXT_SECONDARY)
            .margin({ bottom: 20 })

          Button('关闭')
            .width('100%')
            .height(44)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor(this.BRAND_PRIMARY)
            .borderRadius(22)
            .onClick(() => { this.showQrCode = false; })
        }
        .width('85%')
        .padding(24)
        .borderRadius(16)
        .backgroundColor(Color.White)
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.showQrCode = false; })
    }
  }
}
