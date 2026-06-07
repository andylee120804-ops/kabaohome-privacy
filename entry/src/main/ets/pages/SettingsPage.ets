/**
 * 卡宝Home - 我的页面
 * 顶部家庭卡 + 分组菜单 + 色系/表情偏好
 */
import { ModuleId, FontSizeMode, MemberRole, Visibility, ThemeColor, THEME_PALETTES, ThemePalette, EmojiStyle, EMOJI_SETS, EmojiSet } from '../common/Constants';
import { ALL_MODULES, ModuleDef } from '../viewmodel/ModuleManager';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { FamilyMember } from '../model/FamilyMember';
import { LocalDbService } from '../service/LocalDbService';
import { AuthService } from '../service/AuthService';
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
  @State familyMembers: FamilyMember[] = [];
  @State familyName: string = '';
  @State inviteCode: string = '';
  @State newMemberName: string = '';
  @State newMemberRole: MemberRole = MemberRole.DAD;
  @State newMemberIsCustodial: boolean = false;
  @State showClaimInfo: boolean = false;
  @State lastCreatedClaimToken: string = '';
  @State lastCreatedMemberName: string = '';
  @State isLargeFont: boolean = false;
  @State fontSize: number = 14;
  @State titleFontSize: number = 18;
  @State sharingModuleId: ModuleId = ModuleId.PERIOD;
  @State tempVisibility: Visibility = Visibility.PRIVATE;
  @State tempMemberIds: string[] = [];
  @State activeDialog: string = 'none';
  @State currentTheme: ThemeColor = ThemeColor.WARM_CORAL;
  @State currentEmojiStyle: EmojiStyle = EmojiStyle.KABAO;

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
    this.currentTheme = this.db.getThemeColor();
    this.currentEmojiStyle = this.db.getEmojiStyle();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    this.applyFontMode();
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

  build() {
    Stack() {
      if (this.currentSection === 0) {
        Column() {
          this.FamilyCard()
          Scroll() {
            Column({ space: 12 }) {
              this.FamilySection()
              this.PersonalSection()
              this.DangerSection()
            }
            .padding({ left: 16, right: 16, top: 4, bottom: 24 })
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .align(Alignment.TopStart)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#F5F5F5')
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
        .backgroundColor('#2FFFFFFF')
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
          Text(this.familyName).fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Row() {
            Text(`邀请码: ${this.inviteCode}`).fontSize(12).fontColor('#CCFFFFFF')
            Text('🔄').fontSize(12).fontColor('#CCFFFFFF').margin({ left: 6 })
              .onClick(async () => {
                this.inviteCode = await this.familyVm.refreshInviteCode();
              })
          }.margin({ top: 4 })
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
                Text(member.avatar).fontSize(12)
                Text(member.name).fontSize(12).fontColor(Color.White).margin({ left: 3 })
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(16)
              .backgroundColor('#2FFFFFFF')
            }, (member: FamilyMember) => member.id)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
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
      Text('家庭').fontSize(12).fontColor('#999999').margin({ bottom: 8, left: 4 })

      Column() {
        this.MenuRow(this.getEmoji().modules, '功能模块管理', `${this.enabledModules.length}/3`, 'modules')
        Divider().color('#F5F5F5').margin({ left: 12, right: 12 })
        this.MenuRow(this.getEmoji().members, '家庭成员管理', `${this.familyMembers.length}人`, 'members')
        Divider().color('#F5F5F5').margin({ left: 12, right: 12 })
        this.MenuRow(this.getEmoji().invite, '邀请家人加入', '', 'invite')
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
      Text('个性').fontSize(12).fontColor('#999999').margin({ bottom: 8, left: 4 })

      Column() {
        Row() {
          Text(this.getEmoji().theme).fontSize(20).margin({ right: 12 })
          Text('家庭色系').fontSize(16).fontColor('#333333').layoutWeight(1)
          Circle().width(14).height(14).fill(this.getPalette().primary).margin({ right: 6 })
            .border({ width: 2, color: this.getPalette().border })
          Text(this.getPalette().name).fontSize(12).fontColor('#999999').margin({ right: 4 })
          Text('▶').fontSize(12).fontColor('#CCCCCC')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .borderRadius({ topLeft: 10, topRight: 10 })
        .onClick(() => { this.activeDialog = 'themeColor'; })

        Divider().color('#F5F5F5').margin({ left: 16, right: 16 })

        Row() {
          Text(this.getEmoji().emojiStyle).fontSize(20).margin({ right: 12 })
          Text('表情风格').fontSize(16).fontColor('#333333').layoutWeight(1)
          Text(this.getEmoji().name).fontSize(12).fontColor('#999999').margin({ right: 4 })
          Text('▶').fontSize(12).fontColor('#CCCCCC')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onClick(() => { this.activeDialog = 'emojiStyle'; })

        Divider().color('#F5F5F5').margin({ left: 16, right: 16 })

        Row() {
          Text(this.getEmoji().font).fontSize(20).margin({ right: 12 })
          Text('字体模式').fontSize(16).fontColor('#333333').layoutWeight(1)
          Text(this.isLargeFont ? '大字体' : '标准').fontSize(12).fontColor('#999999').margin({ right: 4 })
          Text('▶').fontSize(12).fontColor('#CCCCCC')
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

  // ==================== 危险操作 ====================
  @Builder
  DangerSection() {
    Column({ space: 10 }) {
      // 退出家庭
      Row() {
        Text(this.getEmoji().exit).fontSize(20).margin({ right: 12 })
        Text('退出家庭').fontSize(16).fontColor('#C62828').layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .borderRadius(10)
      .backgroundColor(Color.White)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        AlertDialog.show({
          title: '退出家庭',
          message: '将清除本地数据并返回设置页，确定退出吗？',
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: {
            value: '退出', fontColor: '#C62828',
            action: async () => {
              await this.familyVm.leaveFamily();
              // 清空路由栈后跳转到登录页，避免返回键回到旧页面
              router.clear();
              router.replaceUrl({ url: 'pages/FamilySetupPage' });
            }
          }
        });
      })

      // 退出登录（清登录态 + 回到华为账号登录页）
      Row() {
        Text('🔄').fontSize(20).margin({ right: 12 })
        Text('退出登录').fontSize(16).fontColor('#C62828').layoutWeight(1)
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
            value: '退出登录', fontColor: '#C62828',
            action: async () => {
              await AuthService.getInstance().logout();
              router.clear();
              router.replaceUrl({ url: 'pages/LoginPage' });
            }
          }
        });
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ==================== 菜单行 ====================
  @Builder
  MenuRow(icon: string, title: string, badge: string, action: string) {
    Row() {
      Text(icon).fontSize(20).margin({ right: 12 })
      Text(title).fontSize(16).fontColor('#333333').layoutWeight(1)
      if (badge) {
        Text(badge).fontSize(12).fontColor('#999999').margin({ right: 6 })
      }
      Text('▶').fontSize(12).fontColor('#CCCCCC')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .onClick(() => {
      if (action === 'modules') {
        this.currentSection = 1;
      } else if (action === 'members') {
        this.currentSection = 2;
      } else if (action === 'invite') {
        this.activeDialog = 'invite';
      }
    })
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
        Text(`${this.getEmoji().modules} 功能模块管理`).fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Text('  ')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          // 已选模块：长按拖动排序（使用 List + onMove 实现真正的拖拽排序）
          if (this.enabledModules.length > 0) {
            Text('已选模块（长按拖动排序）')
              .fontSize(this.fontSize - 1).fontColor('#666666').padding({ left: 4 })

            List({ space: 8 }) {
              ForEach(this.enabledModules, (moduleId: ModuleId) => {
                ListItem() {
                  Row() {
                    Text('≡').fontSize(20).fontColor('#BBBBBB').margin({ right: 8 })
                    Text(ALL_MODULES.find(m => m.id === moduleId)?.icon ?? '📋').fontSize(18).margin({ right: 8 })
                    Column() {
                      Text(ALL_MODULES.find(m => m.id === moduleId)?.name ?? '')
                        .fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor('#333333')
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
                  .border({ width: 1, color: '#F0F0F0' })
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

          Row().width('100%').height(0.5).backgroundColor('#E0E0E0').margin({ top: 4, bottom: 4 })

          // 更多模块：可开启
          Text('更多模块')
            .fontSize(this.fontSize - 1).fontColor('#666666').padding({ left: 4 })

          ForEach(ALL_MODULES.filter(m => m.isAvailable && !this.enabledModules.includes(m.id)), (mod: ModuleDef) => {
            Row() {
              Text(mod.icon).fontSize(18).margin({ right: 8 })
              Column() {
                Text(mod.name).fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor('#333333')
                Text(mod.description).fontSize(this.fontSize - 2).fontColor('#999999').margin({ top: 1 })
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
            .border({ width: 1, color: '#F0F0F0' })
          }, (mod: ModuleDef) => mod.id)

          Text(`已选择 ${this.enabledModules.length}/3 个模块`)
            .fontSize(this.fontSize - 1)
            .fontColor(this.enabledModules.length >= 3 ? '#C62828' : '#666666')
            .margin({ top: 8 })
        }
        .padding(16)
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F5F5F5')
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
        Text(`${this.getEmoji().members} 家庭成员管理`).fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Text('  ')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 10 }) {
          Text('管理家庭成员，添加后可在各模块中设置数据共享范围')
            .fontSize(this.fontSize - 1).fontColor('#666666').padding({ left: 4, bottom: 4 })

          ForEach(this.familyMembers, (member: FamilyMember) => {
            Row() {
              Text(member.avatar).fontSize(18).margin({ right: 8 })
              Column() {
                Text(member.name).fontSize(this.fontSize).fontWeight(FontWeight.Medium).fontColor('#333333')
                Text(member.role === MemberRole.DAD ? '爸爸' :
                  member.role === MemberRole.MOM ? '妈妈' : member.role === MemberRole.GRANDPA ? '爷爷' : member.role === MemberRole.GRANDMA ? '奶奶' :
                    member.role === MemberRole.CHILD ? '孩子' : '其他')
                  .fontSize(this.fontSize - 2).fontColor('#999999').margin({ top: 1 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Circle().width(16).height(16).fill(member.color).margin({ right: 6 })
              if (member.status === 'UNCLAIMED') {
                Text('待认领')
                  .fontSize(10).fontColor('#1565C0').backgroundColor('#E3F2FD')
                  .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 }).margin({ right: 4 })
              }
              if (member.isCustodial) {
                Text('代管').fontSize(10).fontColor('#FF9800').backgroundColor('#FFF8E1')
                  .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 }).margin({ right: 4 })
              }
              Text('✕').fontSize(12).fontColor('#C62828').margin({ left: 4 })
                .onClick(() => {
                  AlertDialog.show({
                    title: '确认删除',
                    message: `确定要删除成员"${member.name}"吗？删除后相关共享设置也会失效。`,
                    primaryButton: { value: '取消', action: () => {} },
                    secondaryButton: {
                      value: '删除', fontColor: '#C62828',
                      action: async () => {
                        await this.familyVm.removeMember(member.id);
                        this.familyMembers = this.familyVm.getFamilyMembers();
                      }
                    }
                  });
                })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(Color.White)
          }, (member: FamilyMember) => member.id)

          if (this.familyMembers.length === 0) {
            Column() {
              Text('👥').fontSize(40)
              Text('还没有家庭成员').fontSize(14).fontColor('#999999').margin({ top: 8 })
              Text('添加家庭成员后，可以在各模块设置数据共享范围').fontSize(12).fontColor('#BBBBBB').margin({ top: 4 })
            }
            .width('100%').padding(30).alignItems(HorizontalAlign.Center)
            .borderRadius(10).backgroundColor('#F5F5F5')
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
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F5F5F5')
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
        } else if (this.activeDialog === 'sharing') {
          this.SharingDialogContent()
        } else if (this.activeDialog === 'themeColor') {
          this.ThemeColorDialogContent()
        } else if (this.activeDialog === 'emojiStyle') {
          this.EmojiStyleDialogContent()
        } else if (this.activeDialog === 'fontSize') {
          this.FontSizeDialogContent()
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
    Text('色系会应用在顶部家庭卡、按钮、标签等位置').fontSize(12).fontColor('#999999').margin({ bottom: 16 })

    Column({ space: 10 }) {
      ForEach(THEME_PALETTES, (palette: ThemePalette) => {
        Row() {
          Column() {
            Row({ space: 6 }) {
              Circle().width(28).height(28).fill(palette.primary)
              Circle().width(28).height(28).fill(palette.gradientEnd)
              Circle().width(28).height(28).fill(palette.lightBg).border({ width: 1, color: '#E0E0E0' })
              Circle().width(28).height(28).fill(palette.border)
            }
            Text(palette.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#333333').margin({ top: 8 })
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
        .backgroundColor(this.currentTheme === palette.id ? palette.lightBg : '#F8F8F8')
        .border({ width: 1, color: this.currentTheme === palette.id ? palette.primary : '#E0E0E0' })
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
    Text('选择菜单图标的表情风格').fontSize(12).fontColor('#999999').margin({ bottom: 16 })

    Column({ space: 10 }) {
      ForEach(EMOJI_SETS, (emojiSet: EmojiSet) => {
        Row() {
          Column() {
            Text(emojiSet.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
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
        .backgroundColor(this.currentEmojiStyle === emojiSet.id ? this.getPalette().lightBg : '#F8F8F8')
        .border({ width: 1, color: this.currentEmojiStyle === emojiSet.id ? this.getPalette().primary : '#E0E0E0' })
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
    Text('大字体模式会增大页面文字，方便阅读').fontSize(12).fontColor('#999999').margin({ bottom: 16 })

    Column({ space: 10 }) {
      Row() {
        Column() {
          Text('标准').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
          Text('默认字体大小').fontSize(13).fontColor('#999999').margin({ top: 4 })
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
      .backgroundColor(!this.isLargeFont ? this.getPalette().lightBg : '#F8F8F8')
      .border({ width: 1, color: !this.isLargeFont ? this.getPalette().primary : '#E0E0E0' })
      .onClick(async () => {
        if (this.isLargeFont) {
          await this.setFontMode(FontSizeMode.NORMAL);
        }
      })

      Row() {
        Column() {
          Text('大字体').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#333333')
          Text('文字更大，阅读更轻松').fontSize(14).fontColor('#999999').margin({ top: 4 })
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
      .backgroundColor(this.isLargeFont ? this.getPalette().lightBg : '#F8F8F8')
      .border({ width: 1, color: this.isLargeFont ? this.getPalette().primary : '#E0E0E0' })
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
      Text('邀请码').fontSize(14).fontColor('#666666')
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
        .color('#333333')
        .backgroundColor(Color.White)
    }
    .width(160).height(160)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(Color.White)
    .margin({ bottom: 16 })

    Text('将邀请码或二维码分享给家人').fontSize(13).fontColor('#999999').margin({ bottom: 16 })
    Button('关闭')
      .width('100%').height(48).fontSize(16)
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
        .fontSize(15).fontColor('#666666').margin({ bottom: 20 })

      Column() {
        Text('认领码（分享给该家人）').fontSize(13).fontColor('#999999')
        Text(this.lastCreatedClaimToken)
          .fontSize(36).fontWeight(FontWeight.Bold).fontColor('#1565C0').margin({ top: 8, bottom: 8 })
        Text('该家人登录后，输入此码即可认领身份')
          .fontSize(12).fontColor('#999999')
      }
      .width('100%')
      .padding(16).borderRadius(12)
      .backgroundColor('#E3F2FD')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 16 })

      Text('💡 该家人也可以直接用家庭邀请码加入，系统会自动匹配并认领')
        .fontSize(11).fontColor('#888888').margin({ bottom: 16 })

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
        .width('100%').padding(10).borderRadius(8).margin({ bottom: 12 })
        .onChange((v: string) => { this.newMemberName = v; })

      Text('选择角色').fontSize(14).fontColor('#666666').width('100%').margin({ bottom: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach([
          { role: MemberRole.DAD, label: '👨 爸爸', color: '#1565C0' },
          { role: MemberRole.MOM, label: '👩 妈妈', color: '#E91E63' },
          { role: MemberRole.GRANDPA, label: '👴 爷爷', color: '#C62828' },
          { role: MemberRole.GRANDMA, label: '👵 奶奶', color: '#E65100' },
          { role: MemberRole.CHILD, label: '👧 孩子', color: '#2E7D32' },
          { role: MemberRole.OTHER, label: '🧑 其他', color: '#6A1B9A' }
        ], (item: MemberRoleOption) => {
          Text(item.label)
            .padding(8).borderRadius(16)
            .backgroundColor(this.newMemberRole === item.role ? item.color : '#F5F5F5')
            .fontColor(this.newMemberRole === item.role ? Color.White : '#333333')
            .margin(4)
            .onClick(() => { this.newMemberRole = item.role; })
        }, (item: MemberRoleOption) => item.role)
      }
      .margin({ bottom: 12 })

      Row() {
        Text('代管成员（没有自己的手机）').fontSize(13).fontColor('#666666').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.newMemberIsCustodial })
          .onChange((isOn: boolean) => { this.newMemberIsCustodial = isOn; })
      }
      .width('100%').padding({ top: 4, bottom: 4 })

      if (this.newMemberIsCustodial) {
        Text('代管成员由你代为操作，适用于没有手机的孩子或老人').fontSize(11).fontColor('#999999').margin({ top: 4 })
      } else {
        Text('非代管成员添加后需本人认领，系统会生成认领码')
          .fontSize(11).fontColor('#1565C0').margin({ top: 4 })
      }

      Row({ space: 12 }) {
        Button('取消')
          .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
          .borderRadius(20).layoutWeight(1)
          .onClick(() => {
            this.activeDialog = 'none';
            this.newMemberName = '';
            this.newMemberRole = MemberRole.DAD;
            this.newMemberIsCustodial = false;
          })
        Button('添加')
          .fontSize(14).fontColor(Color.White).backgroundColor(this.getPalette().primary)
          .borderRadius(20).layoutWeight(1)
          .onClick(async () => {
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
          })
      }
      .margin({ top: 16 })
    }
  }

  // ==================== 分享设置对话框 ====================
  @Builder
  SharingDialogContent() {
    Text('数据共享设置').fontSize(20).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
    Text(`为「${this.getModuleName(this.sharingModuleId)}」选择数据可见范围`)
      .fontSize(14).fontColor('#666666').margin({ bottom: 16 })

    Column({ space: 8 }) {
      this.ShareOption('🔒 仅自己', '只有你自己能看到该模块的数据', Visibility.PRIVATE)
      this.ShareOption('👨‍👩 指定成员', '仅你选择的家庭成员可以看到', Visibility.SELECTED)
      this.ShareOption('👨‍👩‍👧‍👦 家庭可见', '所有家庭成员都可以看到', Visibility.FAMILY)
    }
    .width('100%')

    if (this.tempVisibility === Visibility.SELECTED) {
      Text('选择可见成员').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#333333')
        .width('100%').margin({ top: 12, bottom: 8 })
      if (this.familyMembers.length === 0) {
        Text('暂无家庭成员，请先在成员管理中添加').fontSize(12).fontColor('#999999')
          .width('100%').margin({ top: 4 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.familyMembers, (member: FamilyMember) => {
            Text(`${member.avatar} ${member.name}`)
              .fontSize(12)
              .fontColor(this.tempMemberIds.includes(member.id) ? Color.White : '#666666')
              .backgroundColor(this.tempMemberIds.includes(member.id) ? member.color : '#F0F0F0')
              .borderRadius(14)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => {
                if (this.tempMemberIds.includes(member.id)) {
                  this.tempMemberIds = this.tempMemberIds.filter(id => id !== member.id);
                } else {
                  this.tempMemberIds = [...this.tempMemberIds, member.id];
                }
              })
          }, (member: FamilyMember) => member.id)
        }
        .width('100%')
      }
    }

    Text(this.getSharingHint()).fontSize(12).fontColor('#999999').margin({ top: 12 })
    Row({ space: 12 }) {
      Button('取消')
        .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
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
        Text(iconLabel).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#333333')
        Text(desc).fontSize(11).fontColor('#999999').margin({ top: 2 })
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
    .backgroundColor(this.tempVisibility === visibility ? this.getPalette().lightBg : '#F8F8F8')
    .border({ width: 1, color: this.tempVisibility === visibility ? this.getPalette().primary : '#E0E0E0' })
    .onClick(() => {
      this.tempVisibility = visibility;
      if (visibility !== Visibility.SELECTED) {
        this.tempMemberIds = [];
      }
    })
  }

  // ==================== 私有方法 ====================
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
    const config = this.db.getModuleVisibilityConfig(moduleId);
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
    const existing = this.db.getModuleVisibilityConfig(moduleId);
    if (existing) {
      this.tempVisibility = existing.visibility;
      this.tempMemberIds = existing.visibleMemberIds;
    } else {
      this.tempVisibility = Visibility.PRIVATE;
      this.tempMemberIds = [];
    }
    this.activeDialog = 'sharing';
  }

  private async saveSharingConfig(): Promise<void> {
    let visibility = this.tempVisibility;
    let memberIds = this.tempMemberIds;
    if (visibility === Visibility.SELECTED && memberIds.length === 0) {
      visibility = Visibility.PRIVATE;
      memberIds = [];
    }
    await this.db.saveModuleVisibilityConfig({
      moduleId: this.sharingModuleId,
      visibility: visibility,
      visibleMemberIds: memberIds
    });
    this.activeDialog = 'none';
  }

  private getSharingHint(): string {
    switch (this.tempVisibility) {
      case Visibility.PRIVATE:
        return '🔒 仅自己可见，其他家庭成员看不到该模块的数据';
      case Visibility.SELECTED:
        return this.tempMemberIds.length === 0
          ? '⚠️ 请至少选择一位成员，或切换为「仅自己」'
          : `👨‍👩 已选择 ${this.tempMemberIds.length} 位成员，仅他们可见`;
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
      this.isLargeFont = mode === FontSizeMode.LARGE;
      this.applyFontMode();
    }
  }

}
