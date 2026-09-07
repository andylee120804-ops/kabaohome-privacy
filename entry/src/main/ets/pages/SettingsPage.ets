/**
 * 卡宝Home - 我的页面
 * 顶部家庭卡 + 分组菜单 + 色系/表情偏好
 */
import { curves } from '@kit.ArkUI';
import { BRAND_CORAL, BG_SUBTLE, BORDER_SUBTLE, INFO_BG, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, SEMANTIC_ERROR, SEMANTIC_INFO, SEMANTIC_SUCCESS, SEMANTIC_WARNING, WARNING_BG, MIST_PURPLE } from '../common/DesignTokens';
import { ModuleId, FontSizeMode, MemberRole, Visibility, ThemeColor, THEME_PALETTES, ThemePalette, EmojiStyle, EMOJI_SETS, EmojiSet , PAGE_TRANSITION_DURATION, ModuleVisibility } from '../common/Constants';
import { LOGIN_ROUTE_URL, buildExplicitLogoutRouteParams } from '../common/AuthNavigation';
import { ALL_MODULES, ModuleDef } from '../viewmodel/ModuleManager';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { FamilyMember } from '../model/FamilyMember';
import { LocalDbService } from '../service/LocalDbService';
import { AuthService } from '../service/AuthService';
import { PushService } from '../service/PushService';
import { LocationReporter } from '../service/LocationReporter';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import router from '@ohos.router';

interface MemberRoleOption {
  role: MemberRole;
  label: string;
  color: string;
}

@Entry
@Component
struct SettingsPage {
  @State currentSection: number = 0;
  @State enabledModules: ModuleId[] = [];
  /** 模块共享配置缓存：保存后同步更新以即时刷新列表中的分享标签 */
  @State moduleVisibilityConfigs: ModuleVisibility[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State familyName: string = '';
  @State inviteCode: string = '';
  @State isAddingMember: boolean = false;
  @State isSavingMember: boolean = false;
  @State newMemberName: string = '';
  @State newMemberRole: MemberRole = MemberRole.DAD;
  @State newMemberIsCustodial: boolean = false;
  @State showClaimInfo: boolean = false;
  @State lastCreatedClaimToken: string = '';
  @State lastCreatedMemberName: string = '';
  /** 查看认领码对话框：指定成员 */
  @State claimInfoMemberId: string = '';
  @State claimInfoToken: string = '';
  @State claimInfoName: string = '';
  @State isLargeFont: boolean = false;
  @State fontSize: number = 14;
  @State titleFontSize: number = 18;
  @State sharingModuleId: ModuleId = ModuleId.PERIOD;
  @State recordSelf: boolean = false; // 「我的姨妈」模块：是否记录自己（仅查看家人时置关）
  @State tempVisibility: Visibility = Visibility.PRIVATE;
  @State tempMemberIds: string[] = [];
  @State activeDialog: string = 'none';
  @State currentTheme: ThemeColor = ThemeColor.WARM_CORAL;
  @State currentEmojiStyle: EmojiStyle = EmojiStyle.KABAO;
  /** 当前账号摘要（华为/离线 + 脱敏 ID），用于家庭卡展示 */
  @State accountLabel: string = '';
  @State accountMaskedId: string = '';
  /** 当前账号完整 ID（用于复制核对） */
  @State accountFullId: string = '';
  /** 当前用户是否为家庭创建者（仅创建者可删除成员） */
  @State isFamilyCreator: boolean = false;
  /** 编辑成员资料对话框：目标成员 + 表单值 */
  @State editMemberId: string = '';
  @State editMemberName: string = '';
  @State editMemberRole: MemberRole = MemberRole.DAD;
  @State notifyEnabled: boolean = true;

  private familyVm: FamilyViewModel = new FamilyViewModel();
  private db: LocalDbService = LocalDbService.getInstance();

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    const family = this.familyVm.getCurrentFamily();
    if (family) {
      this.familyName = family.name;
      this.inviteCode = family.inviteCode;
    }
    this.familyMembers = this.familyVm.getFamilyMembers();
    const allModules = ALL_MODULES;
    this.enabledModules = this.db.getEnabledModules().filter(id => {
      const def = allModules.find(m => m.id === id);
      return def !== undefined && def.isAvailable;
    });
    this.moduleVisibilityConfigs = this.db.getModuleVisibilityConfigs();
    this.currentTheme = this.db.getThemeColor();
    this.currentEmojiStyle = this.db.getEmojiStyle();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    this.applyFontMode();
    this.isFamilyCreator = AuthService.getInstance().isCreator();
    this.refreshAccountSummary();
    this.notifyEnabled = PushService.getInstance().isNotifyEnabled();
  }

  /** 刷新当前账号摘要（华为账号 / 离线账号 + 脱敏 ID） */
  private refreshAccountSummary(): void {
    const auth = AuthService.getInstance();
    const summary = auth.getAccountSummary();
    this.accountLabel = summary.label;
    this.accountMaskedId = summary.maskedId;
    this.accountFullId = auth.getAccountFullId();
  }

  /** 复制账号完整 ID 到剪贴板 */
  private async copyAccountId(): Promise<void> {
    if (!this.accountFullId) return;
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.accountFullId);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '账号 ID 已复制' });
    } catch (err) {
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private applyFontMode(): void {
    if (this.isLargeFont) {
      this.fontSize = 18;
      this.titleFontSize = 22;
    } else {
      this.fontSize = 14;
      this.titleFontSize = 18;
    }
  }

  private getPalette(): ThemePalette {
    return THEME_PALETTES.find(p => p.id === this.currentTheme) ?? THEME_PALETTES[0];
  }

  private getEmoji(): EmojiSet {
    return EMOJI_SETS.find(e => e.id === this.currentEmojiStyle) ?? EMOJI_SETS[2];
  }

  private async goToLoginAfterAuthReset(): Promise<void> {
    // 先清空路由栈（保留当前页 SettingsPage），再 replaceUrl 到 LoginPage。
    // 若先 replaceUrl 再 clear，clear 可能重置 LoginPage 的路由参数，导致
    // shouldSkipSilentLogin 失败 -> 走 silentLogin -> 华为账号静默成功跳回 Index。
    router.clear();
    await router.replaceUrl({
      url: LOGIN_ROUTE_URL,
      params: buildExplicitLogoutRouteParams(),
      recoverable: false
    });
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionEnter({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).opacity(1)
    PageTransitionExit({ type: RouteType.None, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).opacity(0)
  }

  build() {
    Stack() {
      if (this.currentSection === 0) {
        Column() {
          this.FamilyCard()
          Scroll() {
            Column({ space: 12 }) {
              this.FamilySection()
              this.PersonalSection()
              this.NotifySection()
              this.DangerSection()
              // 隐私政策入口：从「个性」分组移出，改为页面底部轻量链接（法规入口保持可达，层级弱化）
              Text('《隐私政策》')
                .fontSize(this.fontSize - 2)
                .fontColor(NEUTRAL_INK_SECONDARY)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 4, bottom: 8 })
                .onClick(() => { this.activeDialog = 'privacy'; })
            }
            .padding({ left: 16, right: 16, top: 4, bottom: 24 })
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .edgeEffect(EdgeEffect.Spring)
          .layoutWeight(1)
          .align(Alignment.TopStart)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(BG_SUBTLE)
      } else if (this.currentSection === 1) {
        this.ModuleManager()
      } else {
        this.MemberManager()
      }

      if (this.activeDialog !== 'none') {
        this.DialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Top)
  }

  // ==================== 顶部家庭卡 ====================
  @Builder
  FamilyCard() {
    Column() {
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor('#2E000000')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.currentSection > 0) {
            this.currentSection = 0;
          } else {
            router.back();
          }
        })
        Blank()
        Text('⚙️').fontSize(20).fontColor(Color.White).opacity(0)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Row() {
        Column() {
          Text(this.familyName).fontSize(this.titleFontSize + 4).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Row() {
            Text(`邀请码: ${this.inviteCode}`).fontSize(this.fontSize - 2).fontColor('#FFFFFF')
            Text('🔄').fontSize(this.fontSize - 2).fontColor('#FFFFFF').margin({ left: 6 })
              .onClick(async () => {
                this.inviteCode = await this.familyVm.refreshInviteCode();
              })
          }.margin({ top: 4 })
          if (this.accountMaskedId) {
            Row() {
              Text(this.accountLabel).fontSize(11).fontColor('#FFFFFF')
              Text(` · ${this.accountMaskedId}`).fontSize(11).fontColor('#FFFFFF')
              Text('📋').fontSize(11).fontColor('#FFFFFF').margin({ left: 6 })
                .onClick(() => { this.copyAccountId(); })
            }.margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 4 })

      // 成员头像圆点
      if (this.familyMembers.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.familyMembers, (member: FamilyMember) => {
              Row() {
                Text(member.avatar).fontSize(this.fontSize - 2)
                Text(member.name).fontSize(this.fontSize - 2).fontColor(Color.White).margin({ left: 3 })
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(16)
              .backgroundColor('#2E000000')
              // 键含 updatedAt：改名后即时刷新成员条（见成员列表 ForEach 注释）
            }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .borderRadius({ bottomLeft: 20, bottomRight: 20 })
    .linearGradient({
      direction: GradientDirection.RightBottom,
      colors: [[this.getPalette().gradientStart, 0], [this.getPalette().gradientEnd, 1]]
    })
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 家庭分组 ====================
  @Builder
  FamilySection() {
    Column() {
      Text('家庭').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 8, left: 4 })

      Column() {
        // 注意：图标不能用 @Builder 按值传参（基础类型参数首次渲染后被冻结，
        // 切换表情风格不会刷新），必须在无参 @Builder 内直接读 this.getEmoji()
        Row() {
          Text(this.getEmoji().modules).fontSize(20).margin({ right: 12 })
          Text('功能模块管理').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Text(`${this.enabledModules.length}/3`).fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 6 })
          Text('▶').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => { this.currentSection = 1; })

        Divider().color(BG_SUBTLE).margin({ left: 12, right: 12 })

        Row() {
          Text(this.getEmoji().members).fontSize(20).margin({ right: 12 })
          Text('家庭成员管理').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Text(`${this.familyMembers.length}人`).fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 6 })
          Text('▶').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => { this.currentSection = 2; })

        Divider().color(BG_SUBTLE).margin({ left: 12, right: 12 })

        Row() {
          Text(this.getEmoji().invite).fontSize(20).margin({ right: 12 })
          Text('邀请家人加入').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Text('▶').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => { this.activeDialog = 'invite'; })
      }
      .borderRadius(10)
      .backgroundColor(Color.White)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 个性分组 ====================
  @Builder
  PersonalSection() {
    Column() {
      Text('个性').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 8, left: 4 })

      Column() {
        Row() {
          Text(this.getEmoji().theme).fontSize(20).margin({ right: 12 })
          Text('家庭色系').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Circle().width(14).height(14).fill(this.getPalette().primary).margin({ right: 6 })
            .border({ width: 2, color: this.getPalette().border })
          Text(this.getPalette().name).fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 4 })
          Text('▶').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .borderRadius({ topLeft: 10, topRight: 10 })
        .onClick(() => { this.activeDialog = 'themeColor'; })

        Divider().color(BG_SUBTLE).margin({ left: 16, right: 16 })

        Row() {
          Text(this.getEmoji().emojiStyle).fontSize(20).margin({ right: 12 })
          Text('表情风格').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Text(this.getEmoji().name).fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 4 })
          Text('▶').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => { this.activeDialog = 'emojiStyle'; })

        Divider().color(BG_SUBTLE).margin({ left: 16, right: 16 })

        Row() {
          Text(this.getEmoji().font).fontSize(20).margin({ right: 12 })
          Text('字体模式').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Text(this.isLargeFont ? '大字体' : '标准').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 4 })
          Text('▶').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .borderRadius({ bottomLeft: 10, bottomRight: 10 })
        .onClick(() => { this.activeDialog = 'fontSize'; })
      }
      .borderRadius(10)
      .backgroundColor(Color.White)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 通知设置 ====================
  @Builder
  NotifySection() {
    Column() {
      Text('通知').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 8, left: 4 })

      Column() {
        Row() {
          Text('🔔').fontSize(20).margin({ right: 12 })
          Text('家庭动态通知').fontSize(this.fontSize + 2).fontColor(NEUTRAL_INK).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.notifyEnabled })
            .selectedColor(BRAND_CORAL)
            .onChange((isOn: boolean) => {
              this.notifyEnabled = isOn;
              PushService.getInstance().setNotifyEnabled(isOn);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .borderRadius(10)
      }
      .borderRadius(10)
      .backgroundColor(Color.White)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 危险操作 ====================
  @Builder
  DangerSection() {
    Column({ space: 10 }) {
      // 退出家庭
      Row() {
        Text(this.getEmoji().exit).fontSize(20).margin({ right: 12 })
        Text('退出家庭').fontSize(this.fontSize + 2).fontColor(SEMANTIC_ERROR).layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .borderRadius(10)
      .backgroundColor(Color.White)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        AlertDialog.show({
          title: '退出家庭',
          message: '将清除本地家庭数据并返回登录页，确定退出吗？',
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: {
            value: '退出', fontColor: SEMANTIC_ERROR,
            action: async () => {
              await this.familyVm.leaveFamily();
              await AuthService.getInstance().logout();
              await this.goToLoginAfterAuthReset();
            }
          }
        });
      })

      // 退出登录（清登录态 + 回到华为账号登录页）
      Row() {
        Text('🔄').fontSize(20).margin({ right: 12 })
        Text('退出登录').fontSize(this.fontSize + 2).fontColor(SEMANTIC_ERROR).layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .borderRadius(10)
      .backgroundColor(Color.White)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        AlertDialog.show({
          title: '退出登录',
          message: '将清除登录状态并返回登录页，可重新选择华为账号登录或离线模式。',
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: {
            value: '退出登录', fontColor: SEMANTIC_ERROR,
            action: async () => {
              await AuthService.getInstance().logout();
              await this.goToLoginAfterAuthReset();
            }
          }
        });
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 模块管理页 ====================
  @Builder
  ModuleManager() {
    Column() {
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.getPalette().primary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.getPalette().border)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.currentSection = 0; })
        Text(`${this.getEmoji().modules} 功能模块管理`).fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).layoutWeight(1).textAlign(TextAlign.Center)
        Text('  ')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          // 已选模块：长按拖动排序（使用 List + onMove 实现真正的拖拽排序）
          if (this.enabledModules.length > 0) {
            Text('已选模块（长按拖动排序）')
              .fontSize(this.fontSize - 1).fontColor(NEUTRAL_INK_SECONDARY).padding({ left: 4 })

            List({ space: 8 }) {
              ForEach(this.enabledModules, (moduleId: ModuleId) => {
                ListItem() {
                  Row() {
                    Text('≡').fontSize(20).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 8 })
                    Text(ALL_MODULES.find(m => m.id === moduleId)?.icon ?? '📋').fontSize(18).margin({ right: 8 })
                    Column() {
                      Text(ALL_MODULES.find(m => m.id === moduleId)?.name ?? '')
                        .fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
                      Text(`分享: ${this.getModuleVisibilityLabel(moduleId)}`)
                        .fontSize(10).fontColor(this.getPalette().primary).margin({ top: 1 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: this.enabledModules.includes(moduleId) })
                      .onChange((isOn: boolean) => { this.toggleModule(moduleId, isOn); })
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 10, bottom: 10 })
                  .borderRadius(8)
                  .backgroundColor(Color.White)
                  .border({ width: 1, color: BORDER_SUBTLE })
                  .onClick(() => {
                    this.openSharingConfig(moduleId);
                  })
                }
              }, (moduleId: ModuleId) => moduleId)
              // List + ForEach 的 onMove 回调：拖拽排序时自动触发，更新数据源
              .onMove((from: number, to: number) => {
                const arr = [...this.enabledModules];
                const item = arr.splice(from, 1)[0];
                arr.splice(to, 0, item);
                this.enabledModules = arr;
                this.db.saveEnabledModules(this.enabledModules);
              })
            }
            .width('100%')
          }

          Row().width('100%').height(0.5).backgroundColor(BORDER_SUBTLE).margin({ top: 4, bottom: 4 })

          // 更多模块：可开启
          Text('更多模块')
            .fontSize(this.fontSize - 1).fontColor(NEUTRAL_INK_SECONDARY).padding({ left: 4 })

          ForEach(ALL_MODULES.filter(m => m.isAvailable && !this.enabledModules.includes(m.id)), (mod: ModuleDef) => {
            Row() {
              Text(mod.icon).fontSize(18).margin({ right: 8 })
              Column() {
                Text(mod.name).fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
                Text(mod.description).fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 1 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.enabledModules.includes(mod.id) })
                .onChange((isOn: boolean) => { this.toggleModule(mod.id, isOn); })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 10 })
            .borderRadius(8)
            .backgroundColor(Color.White)
            .border({ width: 1, color: BORDER_SUBTLE })
          }, (mod: ModuleDef) => mod.id)

          Text(`已选择 ${this.enabledModules.length}/3 个模块`)
            .fontSize(this.fontSize - 1)
            .fontColor(this.enabledModules.length >= 3 ? SEMANTIC_ERROR : NEUTRAL_INK_SECONDARY)
            .margin({ top: 8 })
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BG_SUBTLE)
  }

  // ==================== 成员管理页 ====================
  @Builder
  MemberManager() {
    Column() {
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.getPalette().primary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.getPalette().border)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.currentSection = 0; })
        Text(`${this.getEmoji().members} 家庭成员管理`).fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).layoutWeight(1).textAlign(TextAlign.Center)
        Text('  ')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 10 }) {
          Text('管理家庭成员，添加后可在各模块中设置数据共享范围')
            .fontSize(this.fontSize - 1).fontColor(NEUTRAL_INK_SECONDARY).padding({ left: 4, bottom: 4 })

          ForEach(this.familyMembers, (member: FamilyMember) => {
            Row() {
              Text(member.avatar).fontSize(18).margin({ right: 8 })
              Column() {
                Text(member.name).fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
                Text(this.getRoleLabel(member.role))
                  .fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 1 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Circle().width(16).height(16).fill(member.color).margin({ right: 6 })
              // 编辑入口：本人或家庭创建者可修改名字/角色
              // 触控目标按 ≥40vp 设计：字号 13 + 水平/垂直 padding，避免 10 号字过难点按
              if (this.familyVm.canEditMember(member)) {
                Text('编辑')
                  .fontSize(13).fontColor(this.getPalette().primary)
                  .backgroundColor(this.getPalette().lightBg)
                  .borderRadius(15)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 6 })
                  .onClick(() => {
                    this.editMemberId = member.id;
                    this.editMemberName = member.name;
                    this.editMemberRole = member.role;
                    this.activeDialog = 'editMember';
                  })
              }
              if (member.status === 'UNCLAIMED') {
                Text('待认领')
                  .fontSize(11).fontColor(SEMANTIC_INFO).backgroundColor(INFO_BG)
                  .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 }).margin({ right: 4 })
                Text('查看认领码')
                  .fontSize(13).fontColor(this.getPalette().primary)
                  .backgroundColor(this.getPalette().lightBg)
                  .borderRadius(15)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 4 })
                  .onClick(() => {
                    this.claimInfoMemberId = member.id;
                    this.claimInfoName = member.name;
                    this.claimInfoToken = this.familyVm.getMemberClaimToken(member.id);
                    this.activeDialog = 'claimInfo';
                  })
              }
              if (member.isCustodial) {
                Text('代管').fontSize(10).fontColor(SEMANTIC_WARNING).backgroundColor(WARNING_BG)
                  .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 }).margin({ right: 4 })
              }
              if (this.isFamilyCreator && member.userId !== AuthService.getInstance().getCurrentUserId()) {
                Text('✕').fontSize(this.fontSize - 2).fontColor(SEMANTIC_ERROR).margin({ left: 4 })
                  .onClick(() => {
                    AlertDialog.show({
                      title: '确认删除',
                      message: `确定要删除成员"${member.name}"吗？删除后相关共享设置也会失效。`,
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: {
                        value: '删除', fontColor: SEMANTIC_ERROR,
                        action: async () => {
                          try {
                            await this.familyVm.removeMember(member.id);
                            this.familyMembers = this.familyVm.getFamilyMembers();
                          } catch (err) {
                            promptAction.showToast({ message: err.message ?? '删除失败' });
                          }
                        }
                      }
                    });
                  })
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(Color.White)
            // 键必须含 updatedAt：编辑成员后 id 不变，仅以 id 为键会导致
            // ForEach 复用旧组件、列表不刷新（与 @Builder 按值冻结同类坑）
          }, (member: FamilyMember) => member.id + '_' + member.updatedAt)

          if (this.familyMembers.length === 0) {
            Column() {
              Text('👥').fontSize(40)
              Text('还没有家庭成员').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 8 })
              Text('添加家庭成员后，可以在各模块设置数据共享范围').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
            }
            .width('100%').padding(30).alignItems(HorizontalAlign.Center)
            .borderRadius(10).backgroundColor(BG_SUBTLE)
          }

          Button('+ 添加家庭成员')
            .fontSize(this.fontSize).fontColor(Color.White).backgroundColor(this.getPalette().primary)
            .borderRadius(20).width('100%').margin({ top: 8 })
            .onClick(() => { this.activeDialog = 'addMember'; })
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BG_SUBTLE)
  }

  // ==================== 对话框覆盖层 ====================
  @Builder
  DialogOverlay() {
    Column() {
      Column() {
        if (this.activeDialog === 'invite') {
          this.InviteDialogContent()
        } else if (this.activeDialog === 'addMember') {
          this.AddMemberDialogContent()
        } else if (this.activeDialog === 'editMember') {
          this.EditMemberDialogContent()
        } else if (this.activeDialog === 'claimInfo') {
          this.ClaimInfoDialogContent()
        } else if (this.activeDialog === 'sharing') {
          this.SharingDialogContent()
        } else if (this.activeDialog === 'themeColor') {
          this.ThemeColorDialogContent()
        } else if (this.activeDialog === 'emojiStyle') {
          this.EmojiStyleDialogContent()
        } else if (this.activeDialog === 'fontSize') {
          this.FontSizeDialogContent()
        } else if (this.activeDialog === 'privacy') {
          this.PrivacyPolicyDialogContent()
        }
      }
      .width('90%')
      .padding(24)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.activeDialog = 'none'; })
  }

  // ==================== 色系选择对话框 ====================
  @Builder
  ThemeColorDialogContent() {
    Text(`${this.getEmoji().theme} 选择家庭色系`).fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 16 })
    Text('色系会应用在顶部家庭卡、按钮、标签等位置').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

    Column({ space: 10 }) {
      ForEach(THEME_PALETTES, (palette: ThemePalette) => {
        Row() {
          Column() {
            Row({ space: 6 }) {
              Circle().width(28).height(28).fill(palette.primary)
              Circle().width(28).height(28).fill(palette.gradientEnd)
              Circle().width(28).height(28).fill(palette.lightBg).border({ width: 1, color: BORDER_SUBTLE })
              Circle().width(28).height(28).fill(palette.border)
            }
            Text(palette.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK).margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.currentTheme === palette.id) {
            Text('✓').fontColor(this.getPalette().primary).fontSize(20).fontWeight(FontWeight.Bold)
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(this.currentTheme === palette.id ? palette.lightBg : BG_SUBTLE)
        .border({ width: 1, color: this.currentTheme === palette.id ? palette.primary : BORDER_SUBTLE })
        .onClick(async () => {
          this.currentTheme = palette.id;
          await this.db.saveThemeColor(palette.id);
        })
      }, (palette: ThemePalette) => palette.id)
    }

    Button('确定')
      .width('100%').height(44).fontSize(15).margin({ top: 16 })
      .fontColor(Color.White).backgroundColor(this.getPalette().primary).borderRadius(22)
      .onClick(() => { this.activeDialog = 'none'; })
  }

  // ==================== 表情风格选择对话框 ====================
  @Builder
  EmojiStyleDialogContent() {
    Text(`${this.getEmoji().emojiStyle} 选择表情风格`).fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 16 })
    Text('选择菜单图标的表情风格').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

    Column({ space: 10 }) {
      ForEach(EMOJI_SETS, (emojiSet: EmojiSet) => {
        Row() {
          Column() {
            Text(emojiSet.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
            Row({ space: 12 }) {
              Text(emojiSet.modules).fontSize(22)
              Text(emojiSet.members).fontSize(22)
              Text(emojiSet.invite).fontSize(22)
              Text(emojiSet.theme).fontSize(22)
              Text(emojiSet.exit).fontSize(22)
            }.margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.currentEmojiStyle === emojiSet.id) {
            Text('✓').fontColor(this.getPalette().primary).fontSize(20).fontWeight(FontWeight.Bold)
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(this.currentEmojiStyle === emojiSet.id ? this.getPalette().lightBg : BG_SUBTLE)
        .border({ width: 1, color: this.currentEmojiStyle === emojiSet.id ? this.getPalette().primary : BORDER_SUBTLE })
        .onClick(async () => {
          this.currentEmojiStyle = emojiSet.id;
          await this.db.saveEmojiStyle(emojiSet.id);
        })
      }, (emojiSet: EmojiSet) => emojiSet.id)
    }

    Button('确定')
      .width('100%').height(44).fontSize(15).margin({ top: 16 })
      .fontColor(Color.White).backgroundColor(this.getPalette().primary).borderRadius(22)
      .onClick(() => { this.activeDialog = 'none'; })
  }

  // ==================== 字体模式选择对话框 ====================
  @Builder
  FontSizeDialogContent() {
    Text(`${this.getEmoji().font} 选择字体模式`).fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 16 })
    Text('大字体模式会增大页面文字，方便阅读').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

    Column({ space: 10 }) {
      Row() {
        Column() {
          Text('标准').fontSize(this.fontSize + 2).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          Text('默认字体大小').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (!this.isLargeFont) {
          Text('✓').fontColor(this.getPalette().primary).fontSize(20).fontWeight(FontWeight.Bold)
        }
      }
      .width('100%')
      .padding(14)
      .borderRadius(10)
      .backgroundColor(!this.isLargeFont ? this.getPalette().lightBg : BG_SUBTLE)
      .border({ width: 1, color: !this.isLargeFont ? this.getPalette().primary : BORDER_SUBTLE })
      .onClick(async () => {
        if (this.isLargeFont) {
          await this.setFontMode(FontSizeMode.NORMAL);
        }
      })

      Row() {
        Column() {
          Text('大字体').fontSize(this.fontSize + 4).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          Text('文字更大，阅读更轻松').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.isLargeFont) {
          Text('✓').fontColor(this.getPalette().primary).fontSize(20).fontWeight(FontWeight.Bold)
        }
      }
      .width('100%')
      .padding(14)
      .borderRadius(10)
      .backgroundColor(this.isLargeFont ? this.getPalette().lightBg : BG_SUBTLE)
      .border({ width: 1, color: this.isLargeFont ? this.getPalette().primary : BORDER_SUBTLE })
      .onClick(async () => {
        if (!this.isLargeFont) {
          await this.setFontMode(FontSizeMode.LARGE);
        }
      })
    }

    Button('确定')
      .width('100%').height(44).fontSize(15).margin({ top: 16 })
      .fontColor(Color.White).backgroundColor(this.getPalette().primary).borderRadius(22)
      .onClick(() => { this.activeDialog = 'none'; })
  }
  @Builder
  InviteDialogContent() {
    Text('邀请家人加入').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 20 })
    Column() {
      Text('邀请码').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY)
      Text(this.inviteCode).fontSize(32).fontWeight(FontWeight.Bold).fontColor(this.getPalette().primary)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(20).borderRadius(12)
    .backgroundColor(this.getPalette().lightBg)
    .justifyContent(FlexAlign.Center).margin({ bottom: 16 })

    Row({ space: 8 }) {
      Text('🔄 刷新邀请码').fontSize(13).fontColor(this.getPalette().primary)
        .onClick(async () => { this.inviteCode = await this.familyVm.refreshInviteCode(); })
    }
    .margin({ bottom: 16 })

    // 二维码 - 使用原生QRCode组件生成可扫描二维码
    Column() {
      QRCode(this.inviteCode)
        .width(136)
        .height(136)
        .color(NEUTRAL_INK)
        .backgroundColor(Color.White)
    }
    .width(160).height(160)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(Color.White)
    .margin({ bottom: 16 })

    Text('将邀请码或二维码分享给家人').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })
    Button('关闭')
      .width('100%').height(48).fontSize(this.fontSize + 2)
      .fontColor(Color.White).backgroundColor(this.getPalette().primary).borderRadius(24)
      .onClick(() => { this.activeDialog = 'none'; })
  }

  // ==================== 添加成员对话框 ====================
  @Builder
  AddMemberDialogContent() {
    if (this.showClaimInfo) {
      // 添加成功后显示认领信息
      Text('✅ 成员已添加').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
      Text(`${this.lastCreatedMemberName} 已添加到家庭`)
        .fontSize(15).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 20 })

      Column() {
        Text('认领码（分享给该家人）').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
        Text(this.lastCreatedClaimToken)
          .fontSize(36).fontWeight(FontWeight.Bold).fontColor(SEMANTIC_INFO).margin({ top: 8, bottom: 8 })
        Text('该家人登录后，输入此码即可认领身份')
          .fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
      }
      .width('100%')
      .padding(16).borderRadius(12)
      .backgroundColor(INFO_BG)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 16 })

      Text('💡 该家人也可以直接用家庭邀请码加入，系统会自动匹配并认领')
        .fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

      Button('知道了')
        .width('100%').height(44).fontSize(15)
        .fontColor(Color.White).backgroundColor(this.getPalette().primary).borderRadius(22)
        .onClick(() => {
          this.showClaimInfo = false;
          this.activeDialog = 'none';
        })
    } else {
      Text('添加家庭成员').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 16 })
      TextInput({ placeholder: '姓名（如：爸爸、宝贝）' })
        .width('100%').fontSize(this.fontSize + 2).height(48).padding(10).borderRadius(10).margin({ bottom: 12 })
        .onChange((v: string) => { this.newMemberName = v; })

      Text('选择角色').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.getRoleOptions(), (item: MemberRoleOption) => {
          Text(item.label)
            .fontSize(15)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor(this.newMemberRole === item.role ? item.color : BG_SUBTLE)
            .fontColor(this.newMemberRole === item.role ? Color.White : NEUTRAL_INK)
            .margin(4)
            .onClick(() => { this.newMemberRole = item.role; })
        }, (item: MemberRoleOption) => item.role)
      }
      .margin({ bottom: 12 })

      Row() {
        Text('代管成员（没有自己的手机）').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.newMemberIsCustodial })
          .onChange((isOn: boolean) => { this.newMemberIsCustodial = isOn; })
      }
      .width('100%').padding({ top: 4, bottom: 4 })

      if (this.newMemberIsCustodial) {
        Text('代管成员由你代为操作，适用于没有手机的孩子或老人').fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
      } else {
        Text('非代管成员添加后需本人认领，系统会生成认领码')
          .fontSize(11).fontColor(SEMANTIC_INFO).margin({ top: 4 })
      }

      Row({ space: 12 }) {
        Button('取消')
          .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BORDER_SUBTLE)
          .borderRadius(20).layoutWeight(1)
          .onClick(() => {
            this.activeDialog = 'none';
            this.newMemberName = '';
            this.newMemberRole = MemberRole.DAD;
            this.newMemberIsCustodial = false;
          })
        Button(this.isAddingMember ? '添加中...' : '添加')
          .fontSize(14).fontColor(Color.White).backgroundColor(this.getPalette().primary)
          .borderRadius(20).layoutWeight(1)
          .enabled(!this.isAddingMember)
          .onClick(async () => {
            if (this.isAddingMember) return; // 防重复提交
            this.isAddingMember = true;
            try {
              if (!this.newMemberName) return;
              const member = await this.familyVm.addFamilyMember(this.newMemberName, this.newMemberRole, this.newMemberIsCustodial);
              this.activeDialog = 'none';
              this.familyMembers = this.familyVm.getFamilyMembers();

              // 非代管成员：显示认领信息
              if (!this.newMemberIsCustodial && member.claimToken) {
                this.lastCreatedClaimToken = member.claimToken;
                this.lastCreatedMemberName = this.newMemberName;
                this.showClaimInfo = true;
                this.activeDialog = 'addMember'; // 保持对话框打开以显示认领信息
              } else {
                this.showClaimInfo = false;
              }

              this.newMemberName = '';
              this.newMemberRole = MemberRole.DAD;
              this.newMemberIsCustodial = false;
            } finally {
              this.isAddingMember = false;
            }
          })
      }
      .margin({ top: 16 })
    }
  }

  // ==================== 编辑成员资料对话框 ====================
  @Builder
  EditMemberDialogContent() {
    Text('修改成员信息').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
    Text('修改名字和角色，仅本人或家庭创建者可操作')
      .fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

    TextInput({ placeholder: '姓名', text: this.editMemberName })
      .width('100%').fontSize(this.fontSize + 2).height(48).padding(10).borderRadius(10).margin({ bottom: 12 })
      .onChange((v: string) => { this.editMemberName = v; })

    Text('选择角色').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 8 })
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.getRoleOptions(), (item: MemberRoleOption) => {
        Text(item.label)
          .fontSize(15)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(this.editMemberRole === item.role ? item.color : BG_SUBTLE)
          .fontColor(this.editMemberRole === item.role ? Color.White : NEUTRAL_INK)
          .margin(4)
          .onClick(() => { this.editMemberRole = item.role; })
      }, (item: MemberRoleOption) => item.role)
    }
    .margin({ bottom: 12 })

    Row({ space: 12 }) {
      Button('取消')
        .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BORDER_SUBTLE)
        .borderRadius(20).layoutWeight(1)
        .onClick(() => { this.activeDialog = 'none'; })
      Button(this.isSavingMember ? '保存中...' : '保存')
        .fontSize(14).fontColor(Color.White).backgroundColor(this.getPalette().primary)
        .borderRadius(20).layoutWeight(1)
        .enabled(!this.isSavingMember)
        .onClick(async () => {
          if (this.isSavingMember) return; // 防重复提交
          this.isSavingMember = true;
          try {
            if (!this.editMemberName.trim()) {
              promptAction.showToast({ message: '名字不能为空' });
              return;
            }
            await this.familyVm.updateMemberProfile(this.editMemberId, this.editMemberName, this.editMemberRole);
            this.familyMembers = this.familyVm.getFamilyMembers();
            this.activeDialog = 'none';
            promptAction.showToast({ message: '已保存' });
          } catch (err) {
            promptAction.showToast({ message: (err as Error).message ?? '保存失败' });
          } finally {
            this.isSavingMember = false;
          }
        })
    }
    .margin({ top: 16 })
  }

  // ==================== 认领码查看对话框 ====================
  @Builder
  ClaimInfoDialogContent() {
    Text('查看认领码').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
    Text(`将认领码分享给「${this.claimInfoName}」，对方登录后输入即可认领身份`)
      .fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 20 })

    Column() {
      Text('认领码').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
      Text(this.claimInfoToken)
        .fontSize(36).fontWeight(FontWeight.Bold).fontColor(SEMANTIC_INFO)
        .margin({ top: 8, bottom: 8 })
      Text('该家人登录后，输入此码即可认领身份')
        .fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
    }
    .width('100%')
    .padding(16).borderRadius(12)
    .backgroundColor(INFO_BG)
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: 16 })

    Text('💡 该家人也可以直接用家庭邀请码加入，系统会自动匹配并认领')
      .fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

    Row({ space: 12 }) {
      Button('复制认领码')
        .fontSize(14).fontColor(Color.White).backgroundColor(this.getPalette().primary)
        .borderRadius(20).layoutWeight(1)
        .onClick(async () => {
          try {
            const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.claimInfoToken);
            const systemPasteboard = pasteboard.getSystemPasteboard();
            await systemPasteboard.setData(pasteData);
            promptAction.showToast({ message: '认领码已复制' });
          } catch (_) {
            promptAction.showToast({ message: '复制失败' });
          }
        })
      Button('刷新认领码')
        .fontSize(14).fontColor(this.getPalette().primary).backgroundColor(Color.White)
        .border({ width: 1, color: this.getPalette().primary })
        .borderRadius(20).layoutWeight(1)
        .onClick(async () => {
          const newToken = await this.familyVm.refreshClaimToken(this.claimInfoMemberId);
          if (newToken) {
            this.claimInfoToken = newToken;
            promptAction.showToast({ message: '认领码已刷新' });
          }
        })
    }
    .margin({ bottom: 12 })

    Button('关闭')
      .width('100%').height(44).fontSize(15)
      .fontColor(Color.White).backgroundColor(this.getPalette().primary).borderRadius(22)
      .onClick(() => { this.activeDialog = 'none'; })
  }

  // ==================== 分享设置对话框 ====================
  @Builder
  SharingDialogContent() {
    Text('数据共享设置').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
    Text(`为「${this.getModuleName(this.sharingModuleId)}」选择数据可见范围`)
      .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).margin({ bottom: 16 })

    Column({ space: 8 }) {
      this.ShareOption('🔒 仅自己', '只有你自己能看到该模块的数据', Visibility.PRIVATE)
      this.ShareOption('👨‍👩 指定成员', '仅你选择的家庭成员可以看到', Visibility.SELECTED)
      this.ShareOption('👨‍👩‍👧‍👦 家庭可见', '所有家庭成员都可以看到', Visibility.FAMILY)
    }
    .width('100%')

    if (this.tempVisibility === Visibility.SELECTED) {
      Text('选择可见成员').fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
        .width('100%').margin({ top: 12, bottom: 4 })
      Text('💡 你作为创建者始终可见，无需选择自己').fontSize(11).fontColor(NEUTRAL_INK_SECONDARY)
        .width('100%').margin({ bottom: 8 })
      if (this.familyMembers.length === 0) {
        Text('暂无家庭成员，请先在成员管理中添加').fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY)
          .width('100%').margin({ top: 4 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.familyMembers.filter(m => m.userId !== AuthService.getInstance().getCurrentUserId()), (member: FamilyMember) => {
            Text(`${member.avatar} ${member.name}`)
              .fontSize(this.fontSize - 2)
              .fontColor(this.tempMemberIds.includes(member.id) ? Color.White : NEUTRAL_INK_SECONDARY)
              .backgroundColor(this.tempMemberIds.includes(member.id) ? member.color : BORDER_SUBTLE)
              .borderRadius(14)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                if (this.tempMemberIds.includes(member.id)) {
                  this.tempMemberIds = this.tempMemberIds.filter(id => id !== member.id);
                } else {
                  this.tempMemberIds = [...this.tempMemberIds, member.id];
                }
              })
          }, (member: FamilyMember) => member.id + '_' + member.updatedAt)
        }
        .width('100%')
      }
    }

    Text(this.getSharingHint()).fontSize(this.fontSize - 2).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 12 })

    if (this.sharingModuleId === ModuleId.PERIOD) {
      Divider().color(BORDER_SUBTLE).margin({ top: 14, bottom: 12 })
      Row() {
        Column() {
          Text('我的角色').fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          Text('关闭时：没有自己的记录就自动进入「仅查看家人」模式')
            .fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.recordSelf })
          .onChange((isOn: boolean) => {
            this.setRecordSelf(isOn);
          })
          .selectedColor(this.getPalette().primary)
      }
      .width('100%')
    }

    Row({ space: 12 }) {
      Button('取消')
        .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BORDER_SUBTLE)
        .borderRadius(20).layoutWeight(1)
        .onClick(() => { this.activeDialog = 'none'; })
      Button('确定')
        .fontSize(14).fontColor(Color.White).backgroundColor(this.getPalette().primary)
        .borderRadius(20).layoutWeight(1)
        .onClick(() => { this.saveSharingConfig(); })
    }
    .width('100%').margin({ top: 16 })
  }

  @Builder
  ShareOption(iconLabel: string, desc: string, visibility: Visibility) {
    Row() {
      Column() {
        Text(iconLabel).fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
        Text(desc).fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.tempVisibility === visibility) {
        Text('✓').fontColor(this.getPalette().primary).fontSize(18).fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.tempVisibility === visibility ? this.getPalette().lightBg : BG_SUBTLE)
    .border({ width: 1, color: this.tempVisibility === visibility ? this.getPalette().primary : BORDER_SUBTLE })
    .onClick(() => {
      this.tempVisibility = visibility;
      if (visibility !== Visibility.SELECTED) {
        this.tempMemberIds = [];
      }
    })
  }

  // ==================== 隐私政策弹窗内容 ====================
  @Builder
  PrivacyPolicyDialogContent() {
    Column({ space: 12 }) {
      // 标题
      Text($r('app.string.privacy_policy_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(NEUTRAL_INK)
        .width('100%')
        .textAlign(TextAlign.Center)

      // 分割线
      Divider().color(BORDER_SUBTLE).margin({ top: 4, bottom: 4 })

      // 隐私政策内容（可滚动）
      Scroll() {
        Text($r('app.string.privacy_policy_content'))
          .fontSize(14)
          .fontColor(NEUTRAL_INK_SECONDARY)
          .lineHeight(22)
          .width('100%')
      }
      .height(320)
      .width('100%')
      .padding({ left: 4, right: 4 })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // 分割线
      Divider().color(BORDER_SUBTLE)

      // 关闭按钮
      Button('关闭')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor(this.getPalette().primary)
        .borderRadius(20)
        .height(40)
        .width('100%')
        .onClick(() => {
          this.activeDialog = 'none';
        })
    }
    .width('100%')
  }

  // ==================== 私有方法 ====================
  /** 角色选项（添加/编辑成员对话框共用） */
  private getRoleOptions(): MemberRoleOption[] {
    return [
      { role: MemberRole.DAD, label: '👨 爸爸', color: SEMANTIC_INFO },
      { role: MemberRole.MOM, label: '👩 妈妈', color: BRAND_CORAL },
      { role: MemberRole.GRANDPA, label: '👴 爷爷', color: SEMANTIC_ERROR },
      { role: MemberRole.GRANDMA, label: '👵 奶奶', color: SEMANTIC_WARNING },
      { role: MemberRole.CHILD, label: '👧 孩子', color: SEMANTIC_SUCCESS },
      { role: MemberRole.OTHER, label: '🧑 其他', color: MIST_PURPLE }
    ];
  }

  /** 角色纯文本标签（成员列表展示用） */
  private getRoleLabel(role: MemberRole): string {
    switch (role) {
      case MemberRole.DAD: return '爸爸';
      case MemberRole.MOM: return '妈妈';
      case MemberRole.GRANDPA: return '爷爷';
      case MemberRole.GRANDMA: return '奶奶';
      case MemberRole.CHILD: return '孩子';
      default: return '其他';
    }
  }

  private async toggleModule(moduleId: ModuleId, isOn: boolean): Promise<void> {
    if (isOn) {
      if (this.enabledModules.length >= 3) {
        AlertDialog.show({
          title: '无法添加更多模块',
          message: '最多只能选择3个功能模块，请先关闭已有模块再开启新模块。',
          primaryButton: { value: '知道了', action: () => {} }
        });
        // 强制触发 @State 重渲染，让 Toggle 视觉状态回到关闭
        this.enabledModules = [...this.enabledModules];
        return;
      }
      if (!this.enabledModules.includes(moduleId)) {
        this.enabledModules = [...this.enabledModules, moduleId];
      }
      await this.db.saveEnabledModules(this.enabledModules);
      this.openSharingConfig(moduleId);
    } else {
      this.enabledModules = this.enabledModules.filter(id => id !== moduleId);
      await this.db.saveEnabledModules(this.enabledModules);
    }
  }

  private getModuleName(moduleId: ModuleId): string {
    const def = ALL_MODULES.find(m => m.id === moduleId);
    return def ? def.name : moduleId;
  }

  private getModuleVisibilityLabel(moduleId: ModuleId): string {
    const config = this.moduleVisibilityConfigs.find(c => c.moduleId === moduleId);
    if (!config) return '仅自己';
    switch (config.visibility) {
      case Visibility.PRIVATE: return '仅自己';
      case Visibility.SELECTED: return `指定${config.visibleMemberIds.length}位成员`;
      case Visibility.FAMILY: return '家庭可见';
      default: return '仅自己';
    }
  }

  private openSharingConfig(moduleId: ModuleId): void {
    this.sharingModuleId = moduleId;
    this.recordSelf = this.db.getPeriodReminderSettings().recordSelf ?? false;
    const existing = this.moduleVisibilityConfigs.find(c => c.moduleId === moduleId);
    if (existing) {
      this.tempVisibility = existing.visibility;
      this.tempMemberIds = [...existing.visibleMemberIds];
    } else {
      this.tempVisibility = Visibility.PRIVATE;
      this.tempMemberIds = [];
    }
    this.activeDialog = 'sharing';
  }

  private async saveSharingConfig(): Promise<void> {
    let visibility = this.tempVisibility;
    let memberIds = [...this.tempMemberIds];
    if (visibility === Visibility.SELECTED && memberIds.length === 0) {
      visibility = Visibility.PRIVATE;
      memberIds = [];
    }
    const newConfig: ModuleVisibility = {
      moduleId: this.sharingModuleId,
      visibility: visibility,
      visibleMemberIds: memberIds
    };
    await this.db.saveModuleVisibilityConfig(newConfig);
    // 回填到当前用户已存在的该模块记录：旧记录保留创建时的 visibility，
    // 不回填会导致后加入成员拉云端时仍能看到改 PRIVATE 前的旧 FAMILY 记录。
    // 用 try-catch 包裹，回填失败不影响配置保存本身。
    let updatedCount = 0;
    try {
      updatedCount = await this.db.applyModuleVisibilityToExistingRecords(this.sharingModuleId);
    } catch (err) {
      console.error('[SettingsPage] applyModuleVisibilityToExistingRecords failed: ' + (err as Error).message);
    }
    // 同步更新 @State 缓存，触发模块列表重新渲染以即时刷新"分享: xxx"标签
    const idx = this.moduleVisibilityConfigs.findIndex(c => c.moduleId === newConfig.moduleId);
    if (idx >= 0) {
      this.moduleVisibilityConfigs = [
        ...this.moduleVisibilityConfigs.slice(0, idx),
        newConfig,
        ...this.moduleVisibilityConfigs.slice(idx + 1)
      ];
    } else {
      this.moduleVisibilityConfigs = [...this.moduleVisibilityConfigs, newConfig];
    }
    this.activeDialog = 'none';
    if (updatedCount > 0) {
      promptAction.showToast({
        message: `已更新 ${updatedCount} 条历史记录的共享范围`,
        duration: 2500
      });
    }
    // 位置模块：共享范围变更立即同步云端行 visibility
    // （改为「仅自己」→ scheduleFlush 删云端行：PRIVATE 心跳不上报，只能靠冲刷，
    //   落盘 pending 保证跨重启/失败也能把旧行清掉）
    if (this.sharingModuleId === ModuleId.LOCATION) {
      if (visibility === Visibility.PRIVATE) {
        LocationReporter.getInstance().scheduleFlush().catch(() => {});
      } else {
        LocationReporter.getInstance().reportNow().catch(() => {});
      }
    }
  }

  /** 「我的姨妈」我的角色开关：立即生效（不经弹窗确定按钮） */
  private async setRecordSelf(isOn: boolean): Promise<void> {
    const s = this.db.getPeriodReminderSettings();
    await this.db.savePeriodReminderSettings({
      remind3DaysBefore: s.remind3DaysBefore,
      remind1DayBefore: s.remind1DayBefore,
      remindOvulation: s.remindOvulation,
      remindFertile: s.remindFertile,
      recordSelf: isOn
    });
    this.recordSelf = isOn;
  }

  private getSharingHint(): string {
    switch (this.tempVisibility) {
      case Visibility.PRIVATE:
        return '🔒 仅自己可见，其他家庭成员看不到该模块的数据';
      case Visibility.SELECTED:
        return this.tempMemberIds.length === 0
          ? '⚠️ 请至少选择一位成员，或切换为「仅自己」'
          : `👨‍👩 已选择 ${this.tempMemberIds.length} 位成员可见（你作为创建者始终可见）`;
      case Visibility.FAMILY:
        return '👨‍👩‍👧‍👦 所有家庭成员都可以看到该模块的数据';
      default: return '';
    }
  }

  private async toggleFontSize(): Promise<void> {
    const newMode = this.isLargeFont ? FontSizeMode.NORMAL : FontSizeMode.LARGE;
    await this.setFontMode(newMode);
  }

  private async setFontMode(mode: FontSizeMode): Promise<void> {
    const member = this.familyVm.getCurrentMember();
    if (member) {
      const updated: FamilyMember = {
        id: member.id, familyId: member.familyId, userId: member.userId,
        name: member.name, avatar: member.avatar, color: member.color,
        role: member.role, birthDate: member.birthDate, phone: member.phone,
        isCustodial: member.isCustodial, fontSizeMode: mode,
        claimToken: member.claimToken, status: member.status,
        createdAt: member.createdAt, updatedAt: new Date().toISOString()
      };
      await this.db.updateMember(updated);
      // 刷新 AuthService 内存缓存，确保其他页面读取到最新的 fontSizeMode
      AuthService.getInstance().reloadCurrentMember();
      this.isLargeFont = mode === FontSizeMode.LARGE;
      this.applyFontMode();
    }
  }

}
