/**
 * 卡宝Home - 家庭备忘页面
 * 设计：简约、字体大、快捷添加
 */
import { Memo, MEMO_CATEGORIES } from '../model/Memo';
import { LocalDbService } from '../service/LocalDbService';
import { Visibility, FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { EmptyState } from '../components/EmptyState';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { generateId } from '../common/Utils';
import router from '@ohos.router';

// Simple base64 for obfuscation (not real encryption)
const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function b64idx(c: string): number {
  return Math.max(0, B64_CHARS.indexOf(c));
}

function btoaEncode(str: string): string {
  const bytes: number[] = [];
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  }
  let result = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    result += B64_CHARS.charAt(b0 >> 2);
    result += B64_CHARS.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
    result += i + 1 < bytes.length ? B64_CHARS.charAt(((b1 & 0x0F) << 2) | (b2 >> 6)) : '=';
    result += i + 2 < bytes.length ? B64_CHARS.charAt(b2 & 0x3F) : '=';
  }
  return result;
}

function btoaDecode(encoded: string): string {
  let bin: number[] = [];
  for (let i = 0; i < encoded.length; i += 4) {
    const c0 = b64idx(encoded.charAt(i));
    const c1 = b64idx(encoded.charAt(i + 1));
    const c2 = encoded.charAt(i + 2) === '=' ? 0 : b64idx(encoded.charAt(i + 2));
    const c3 = encoded.charAt(i + 3) === '=' ? 0 : b64idx(encoded.charAt(i + 3));
    bin.push((c0 << 2) | (c1 >> 4));
    if (encoded.charAt(i + 2) !== '=') bin.push(((c1 & 0x0F) << 4) | (c2 >> 2));
    if (encoded.charAt(i + 3) !== '=') bin.push(((c2 & 0x03) << 6) | c3);
  }
  let result = '';
  let idx = 0;
  while (idx < bin.length) {
    const byte = bin[idx];
    if (byte < 0x80) {
      result += String.fromCharCode(byte);
      idx++;
    } else if ((byte & 0xE0) === 0xC0) {
      result += String.fromCharCode(((byte & 0x1F) << 6) | (bin[idx + 1] & 0x3F));
      idx += 2;
    } else {
      result += String.fromCharCode(((byte & 0x0F) << 12) | ((bin[idx + 1] & 0x3F) << 6) | (bin[idx + 2] & 0x3F));
      idx += 3;
    }
  }
  return result;
}

interface VisibilityOption {
  value: Visibility;
  label: string;
}

@Entry
@Component
struct MemoPage {
  private visibilityOptions: VisibilityOption[] = [
    { value: Visibility.PRIVATE, label: '仅自己' },
    { value: Visibility.SELECTED, label: '指定成员' },
    { value: Visibility.FAMILY, label: '家庭可见' }
  ];

  @State memos: Memo[] = [];
  @State selectedCategory: string = '';
  @State showAddDialog: boolean = false;
  @State newTitle: string = '';
  @State newContent: string = '';
  @State newCategory: string = '其他';
  @State newIsEncrypted: boolean = false;
  @State newVisibility: Visibility = Visibility.PRIVATE;
  @State editingMemoId: string = '';
  @State searchText: string = '';
  @State showMemoDetail: boolean = false;
  @State detailMemo: Memo | null = null;
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themeLightBg: string = '#FFF5F0';
  @State themePrimary: string = '#E8654A';
  @State themeBorder: string = '#FFD4C2';

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  private isCreator(creatorId: string): boolean {
    return creatorId === this.db.getCurrentUserId();
  }

  aboutToAppear(): void {
    this.memos = this.db.getMemos();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themeLightBg = palette.lightBg;
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
  }

  build() {
    Stack() {
      Column() {
      // 标题栏
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { router.back(); })
        Text('📝 家庭备忘').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Row() {
          Text('+')
            .fontSize(20)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .width(32).height(32).borderRadius(16)
        .backgroundColor(this.themePrimary)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.editingMemoId = '';
          this.resetForm();
          this.showAddDialog = true;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 搜索栏
      Row() {
        TextInput({ placeholder: '🔍 搜索备忘...' })
          .fontSize(15)
          .layoutWeight(1)
          .padding(10)
          .borderRadius(20)
          .backgroundColor('#F0F0F0')
          .onChange((value: string) => { this.searchText = value; })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 分类筛选
      Scroll() {
        Row({ space: 6 }) {
          Text('全部')
            .fontSize(13)
            .fontColor(this.selectedCategory === '' ? Color.White : '#666666')
            .backgroundColor(this.selectedCategory === '' ? '#6A1B9A' : '#F5F5F5')
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .onClick(() => { this.selectedCategory = ''; })
          ForEach(MEMO_CATEGORIES, (cat: string) => {
            Text(cat)
              .fontSize(13)
              .fontColor(this.selectedCategory === cat ? Color.White : '#666666')
              .backgroundColor(this.selectedCategory === cat ? '#6A1B9A' : '#F5F5F5')
              .borderRadius(14)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .onClick(() => { this.selectedCategory = cat; })
          }, (cat: string) => cat)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 备忘列表
      Scroll() {
        if (this.memos.length === 0) {
          EmptyState({
            icon: '📝',
            title: '暂无备忘',
            subtitle: '记录密码、证件、地址等信息',
            actionText: '+ 添加备忘',
            buttonColor: this.themePrimary,
            onAction: () => { this.showAddDialog = true; }
          })
        } else {
          Column({ space: 8 }) {
            ForEach(this.getFilteredMemos(), (memo: Memo) => {
              Row() {
                Column() {
                  Text(memo.title)
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (memo.content) {
                    Text(memo.isEncrypted ? '🔒 已加密' : this.decodeContent(memo.content))
                      .fontSize(14)
                      .fontColor('#888888')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 3 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (memo.isEncrypted) {
                  Text('🔒').fontSize(18).margin({ right: 8 })
                }
                Text(memo.category)
                  .fontSize(13).fontColor('#6A1B9A').backgroundColor('#F3E5F5')
                  .borderRadius(8).padding({ left: 8, right: 8, top: 3, bottom: 3 })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(10)
              .backgroundColor(Color.White)
              .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
              .onClick(() => {
                this.detailMemo = memo;
                this.showMemoDetail = true;
              })
              .gesture(
                LongPressGesture()
                  .onAction(() => {
                    if (!this.isCreator(memo.creatorId)) {
                      AlertDialog.show({
                        title: '提示',
                        message: '只能删除自己创建的记录',
                        primaryButton: {
                          value: '确定',
                          action: () => {}
                        }
                      });
                      return;
                    }
                    AlertDialog.show({
                      title: '确认删除',
                      message: `确定删除备忘「${memo.title}」吗？`,
                      primaryButton: {
                        value: '取消',
                        action: () => {}
                      },
                      secondaryButton: {
                        value: '删除',
                        action: async () => {
                          await this.db.deleteMemo(memo.id);
                          this.memos = this.db.getMemos();
                        }
                      }
                    });
                  })
              )
            }, (memo: Memo) => memo.id)

            // 快捷添加按钮（和孩子事项页面一样）
            Button('+ 添加备忘')
              .fontSize(16).fontColor(Color.White).backgroundColor(this.themePrimary)
              .borderRadius(20).width('100%').margin({ top: 8 })
              .onClick(() => {
                this.editingMemoId = '';
                this.resetForm();
                this.showAddDialog = true;
              })
          }
          .padding(16)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.themeLightBg)
    .bindContentCover(this.showAddDialog, this.AddMemoDialog(), {
      onDisappear: () => {
        this.editingMemoId = '';
        this.resetForm();
      }
    })

    if (this.showMemoDetail) {
      this.MemoDetailOverlay()
    }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 备忘详情弹窗 ====================
  @Builder
  MemoDetailOverlay() {
    Column() {
      Column() {
        Row() {
          Text('📝 备忘详情').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999').onClick(() => {
            this.showMemoDetail = false;
            this.detailMemo = null;
          })
        }.width('100%').margin({ bottom: 16 })

        if (this.detailMemo) {
          Text(this.detailMemo.title)
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#333333')
            .width('100%').margin({ bottom: 8 })

          Row() {
            Text(this.detailMemo.category)
              .fontSize(13).fontColor('#6A1B9A').backgroundColor('#F3E5F5')
              .borderRadius(8).padding({ left: 8, right: 8, top: 3, bottom: 3 })
            if (this.detailMemo.isEncrypted) {
              Text('🔒 已加密').fontSize(13).fontColor('#FF6D00').margin({ left: 8 })
            }
          }
          .width('100%').margin({ bottom: 12 })

          if (this.detailMemo.content) {
            Text(this.decodeContent(this.detailMemo.content))
              .fontSize(15).fontColor('#444444')
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor('#F8F8F8')
              .margin({ bottom: 12 })
          }

          Text(`创建于 ${this.detailMemo.createdAt.slice(0, 16).replace('T', ' ')}`)
            .fontSize(12).fontColor('#BBBBBB').width('100%').margin({ bottom: 16 })

          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
              .borderRadius(20).layoutWeight(1)
              .onClick(() => {
                this.showMemoDetail = false;
                this.detailMemo = null;
              })

            if (this.isCreator(this.detailMemo.creatorId)) {
              Button('编辑')
                .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
                .borderRadius(20).layoutWeight(1)
                .onClick(() => {
                  const memo = this.detailMemo!;
                  this.editingMemoId = memo.id;
                  this.newTitle = memo.title;
                  this.newContent = this.decodeContent(memo.content);
                  this.newCategory = memo.category;
                  this.newIsEncrypted = memo.isEncrypted;
                  this.newVisibility = memo.visibility;
                  this.showMemoDetail = false;
                  this.detailMemo = null;
                  this.showAddDialog = true;
                })
            }
          }
          .width('100%')
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showMemoDetail = false;
      this.detailMemo = null;
    })
  }

  @Builder
  AddMemoDialog() {
    Column() {
      Column() {
        Text(this.editingMemoId ? '编辑备忘' : '添加备忘').fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 16 })

        TextInput({ placeholder: '标题' })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newTitle = v; })

        TextArea({ placeholder: '内容' })
          .width('100%').height(100).padding(10).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newContent = v; })

        // 分类选择
        Text('分类').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 4 })
        Row({ space: 6 }) {
          ForEach(MEMO_CATEGORIES, (cat: string) => {
            Text(cat)
              .fontSize(13)
              .fontColor(this.newCategory === cat ? Color.White : '#666666')
              .backgroundColor(this.newCategory === cat ? '#6A1B9A' : '#F5F5F5')
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => { this.newCategory = cat; })
          }, (cat: string) => cat)
        }
        .margin({ bottom: 12 })

        // 加密开关
        Row() {
          Text('🔒 加密').fontSize(14).fontColor('#333333').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.newIsEncrypted })
            .onChange((isOn: boolean) => { this.newIsEncrypted = isOn; })
        }
        .width('100%')
        .padding({ top: 4, bottom: 8 })

        if (this.newIsEncrypted) {
          Text('加密后内容将隐藏显示，仅本人可查看')
            .fontSize(12).fontColor('#FF6D00').width('100%').margin({ bottom: 8 })
        }

        // 可见范围
        Text('可见范围').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 4 })
        Row({ space: 6 }) {
          ForEach(this.visibilityOptions, (item: VisibilityOption) => {
            Text(item.label)
              .fontSize(13)
              .fontColor(this.newVisibility === item.value ? Color.White : '#666666')
              .backgroundColor(this.newVisibility === item.value ? '#6A1B9A' : '#F5F5F5')
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .onClick(() => { this.newVisibility = item.value; })
          }, (item: VisibilityOption) => item.value as string)
        }
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
            .borderRadius(20).layoutWeight(1)
            .onClick(() => {
              this.showAddDialog = false;
              this.editingMemoId = '';
              this.resetForm();
            })
          Button(this.editingMemoId ? '保存' : '添加')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .onClick(async () => {
              if (!this.newTitle) return;
              const now = new Date().toISOString();
              const contentToStore = this.newIsEncrypted ?
                'ENC:' + btoaEncode(this.newContent) :
                this.newContent;
              if (this.editingMemoId) {
                const existing = this.memos.find(m => m.id === this.editingMemoId);
                if (existing) {
                  const updated: Memo = {
                    id: existing.id,
                    familyId: existing.familyId,
                    creatorId: existing.creatorId,
                    visibility: this.newVisibility,
                    visibleMembers: existing.visibleMembers,
                    version: existing.version + 1,
                    createdAt: existing.createdAt,
                    updatedAt: now,
                    title: this.newTitle,
                    content: contentToStore,
                    category: this.newCategory,
                    isEncrypted: this.newIsEncrypted
                  };
                  await this.db.updateMemo(updated);
                }
              } else {
                const userId = this.db.getCurrentUserId();
                const family = this.db.getCurrentFamily();
                const memo: Memo = {
                  id: generateId('memo'),
                  familyId: family?.id ?? '',
                  creatorId: userId,
                  visibility: this.newVisibility,
                  visibleMembers: [],
                  version: 1,
                  createdAt: now,
                  updatedAt: now,
                  title: this.newTitle,
                  content: contentToStore,
                  category: this.newCategory,
                  isEncrypted: this.newIsEncrypted
                };
                await this.db.saveMemo(memo);
              }
              this.showAddDialog = false;
              this.editingMemoId = '';
              this.resetForm();
              this.memos = this.db.getMemos();
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.4)')
  }

  private decodeContent(content: string): string {
    if (content.startsWith('ENC:')) {
      try {
        return btoaDecode(content.slice(4));
      } catch (_) {
        return '🔒 加密内容';
      }
    }
    return content;
  }

  private getFilteredMemos(): Memo[] {
    let result = this.memos;
    if (this.selectedCategory) {
      result = result.filter(m => m.category === this.selectedCategory);
    }
    if (this.searchText) {
      const keyword = this.searchText.toLowerCase();
      result = result.filter(m =>
        m.title.toLowerCase().includes(keyword) ||
        this.decodeContent(m.content).toLowerCase().includes(keyword)
      );
    }
    return result;
  }

  private resetForm(): void {
    this.editingMemoId = '';
    this.newTitle = '';
    this.newContent = '';
    this.newCategory = '其他';
    this.newIsEncrypted = false;
    this.newVisibility = Visibility.PRIVATE;
  }
}
