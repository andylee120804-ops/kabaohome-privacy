/**
 * 卡宝Home - 购物清单页面
 */
import { ShoppingItem, SHOPPING_CATEGORIES } from '../model/ShoppingItem';
import { LocalDbService } from '../service/LocalDbService';
import { EmptyState } from '../components/EmptyState';
import { Visibility, FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { generateId } from '../common/Utils';
import router from '@ohos.router';

@Entry
@Component
struct ShoppingPage {
  @State items: ShoppingItem[] = [];
  @State selectedCategory: string = '';
  @State showAddDialog: boolean = false;
  @State newItemName: string = '';
  @State newItemCategory: string = '其他';
  @State newItemQuantity: string = '';
  @State isLargeFont: boolean = false;
  @State editingItemId: string = '';
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
    this.items = this.db.getShoppingItems();
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
    Column() {
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { router.back(); })
        Text('🛒 购物清单').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Row() { Text('+').fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold) }.width(32).height(32).borderRadius(16).backgroundColor(this.themePrimary).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.editingItemId = '';
            this.resetForm();
            this.showAddDialog = true;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 分类筛选
      Scroll() {
        Row({ space: 6 }) {
          Text('全部')
            .fontSize(13)
            .fontColor(this.selectedCategory === '' ? Color.White : '#666666')
            .backgroundColor(this.selectedCategory === '' ? '#2E7D32' : '#F5F5F5')
            .borderRadius(12)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .onClick(() => { this.selectedCategory = ''; })
          ForEach(SHOPPING_CATEGORIES, (cat: string) => {
            Text(cat)
              .fontSize(13)
              .fontColor(this.selectedCategory === cat ? Color.White : '#666666')
              .backgroundColor(this.selectedCategory === cat ? '#2E7D32' : '#F5F5F5')
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .onClick(() => { this.selectedCategory = cat; })
          }, (cat: string) => cat)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 统计
      Row() {
        Text(`待买 ${this.getPendingCount()} 项`).fontSize(16).fontColor('#2E7D32').layoutWeight(1)
        Text(`已买 ${this.getPurchasedCount()} 项`).fontSize(16).fontColor('#999999')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 购物列表
      Scroll() {
        if (this.items.length === 0) {
          EmptyState({
            icon: '🛒',
            title: '购物清单为空',
            subtitle: '添加需要购买的物品',
            actionText: '+ 添加物品',
            buttonColor: this.themePrimary,
            onAction: () => {
              this.editingItemId = '';
              this.resetForm();
              this.showAddDialog = true;
            }
          })
        } else {
          Column({ space: 8 }) {
            // 待买
            if (this.getPendingItems().length > 0) {
              Text('📝 待买').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')
              ForEach(this.getPendingItems(), (item: ShoppingItem) => {
                this.ShoppingItemRow(item)
              }, (item: ShoppingItem) => item.id)
            }

            // 已买
            if (this.getPurchasedItems().length > 0) {
              Text('✅ 已买').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#999999').width('100%').margin({ top: 8 })
              ForEach(this.getPurchasedItems(), (item: ShoppingItem) => {
                this.ShoppingItemRow(item)
              }, (item: ShoppingItem) => item.id)
            }

            Button('+ 添加物品')
              .fontSize(16).fontColor(Color.White).backgroundColor(this.themePrimary)
              .borderRadius(20).width('100%').margin({ top: 8 })
              .onClick(() => {
                this.editingItemId = '';
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
    .bindContentCover(this.showAddDialog, this.AddItemDialog())
  }

  @Builder
  ShoppingItemRow(item: ShoppingItem) {
    Row() {
      Checkbox()
        .select(item.isPurchased)
        .onChange(async (isChecked: boolean) => {
          const now = new Date().toISOString();
          const updated: ShoppingItem = {
            id: item.id, familyId: item.familyId, creatorId: item.creatorId,
            visibility: item.visibility, visibleMembers: item.visibleMembers,
            version: item.version + 1, createdAt: item.createdAt, updatedAt: now,
            itemName: item.itemName, category: item.category, quantity: item.quantity,
            isPurchased: isChecked,
            purchasedAt: isChecked ? now : '',
            purchasedBy: isChecked ? this.db.getCurrentUserId() : ''
          };
          await this.db.updateShoppingItem(updated);
          this.items = this.db.getShoppingItems();
        })
        .margin({ right: 10 })

      Column() {
        Text(item.itemName)
          .fontSize(18)
          .fontColor(item.isPurchased ? '#999999' : '#333333')
          .decoration({ type: item.isPurchased ? TextDecorationType.LineThrough : TextDecorationType.None })
        if (item.quantity) {
          Text(item.quantity).fontSize(15).fontColor('#999999').margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(item.category)
        .fontSize(14).fontColor('#2E7D32').backgroundColor('#E8F5E9')
        .borderRadius(8).padding({ left: 10, right: 10, top: 3, bottom: 3 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor(Color.White)
    .opacity(item.isPurchased ? 0.6 : 1)
    .onClick(() => {
      if (this.isCreator(item.creatorId)) {
        this.editingItemId = item.id;
        this.newItemName = item.itemName;
        this.newItemCategory = item.category;
        this.newItemQuantity = item.quantity;
        this.showAddDialog = true;
      }
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (!this.isCreator(item.creatorId)) {
            AlertDialog.show({
              title: '提示',
              message: '只能删除自己创建的记录',
              primaryButton: {
                value: '知道了',
                action: () => {}
              }
            });
          } else {
            AlertDialog.show({
              title: '确认删除',
              message: `确定删除「${item.itemName}」吗？`,
              primaryButton: {
                value: '取消',
                action: () => {}
              },
              secondaryButton: {
                value: '删除',
                action: async () => {
                  await this.db.deleteShoppingItem(item.id);
                  this.items = this.db.getShoppingItems();
                }
              }
            });
          }
        })
    )
  }

  @Builder
  AddItemDialog() {
    if (this.showAddDialog) {
      Column() {
        Text(this.editingItemId ? '编辑物品' : '添加购物物品')
          .fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 16 })

        TextInput({ placeholder: '物品名称（如：牛奶）', text: this.newItemName })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newItemName = v; })

        // 分类选择
        Text('分类').fontSize(13).fontColor('#999999').width('100%').margin({ bottom: 4 })
        Scroll() {
          Row({ space: 6 }) {
            ForEach(SHOPPING_CATEGORIES, (cat: string) => {
              Text(cat)
                .fontSize(12)
                .fontColor(this.newItemCategory === cat ? Color.White : '#666666')
                .backgroundColor(this.newItemCategory === cat ? '#2E7D32' : '#F5F5F5')
                .borderRadius(12)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .onClick(() => { this.newItemCategory = cat; })
            }, (cat: string) => cat)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .width('100%')
        .margin({ bottom: 8 })

        TextInput({ placeholder: '数量（如：2盒，可选）', text: this.newItemQuantity })
          .width('100%').padding(10).borderRadius(8).margin({ bottom: 12 })
          .onChange((v: string) => { this.newItemQuantity = v; })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
            .borderRadius(20).layoutWeight(1)
            .onClick(() => {
              this.showAddDialog = false;
              this.editingItemId = '';
              this.resetForm();
            })
          Button(this.editingItemId ? '保存' : '添加')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .onClick(async () => {
              if (!this.newItemName) return;
              const now = new Date().toISOString();
              if (this.editingItemId) {
                const existing = this.items.find(i => i.id === this.editingItemId);
                if (existing) {
                  const updated: ShoppingItem = {
                    id: existing.id, familyId: existing.familyId, creatorId: existing.creatorId,
                    visibility: existing.visibility, visibleMembers: existing.visibleMembers,
                    version: existing.version + 1, createdAt: existing.createdAt, updatedAt: now,
                    itemName: this.newItemName, category: this.newItemCategory, quantity: this.newItemQuantity,
                    isPurchased: existing.isPurchased,
                    purchasedAt: existing.purchasedAt, purchasedBy: existing.purchasedBy
                  };
                  await this.db.updateShoppingItem(updated);
                }
              } else {
                const userId = this.db.getCurrentUserId();
                const family = this.db.getCurrentFamily();
                const item: ShoppingItem = {
                  id: generateId('si'),
                  familyId: family?.id ?? '',
                  creatorId: userId,
                  visibility: Visibility.PRIVATE,
                  visibleMembers: [],
                  version: 1,
                  createdAt: now,
                  updatedAt: now,
                  itemName: this.newItemName,
                  category: this.newItemCategory,
                  quantity: this.newItemQuantity,
                  isPurchased: false,
                  purchasedBy: '',
                  purchasedAt: ''
                };
                await this.db.saveShoppingItem(item);
              }
              this.showAddDialog = false;
              this.editingItemId = '';
              this.resetForm();
              this.items = this.db.getShoppingItems();
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
    }
  }

  private getFilteredItems(): ShoppingItem[] {
    if (!this.selectedCategory) return this.items;
    return this.items.filter(i => i.category === this.selectedCategory);
  }

  private getPendingCount(): number {
    return this.items.filter(i => !i.isPurchased).length;
  }

  private getPurchasedCount(): number {
    return this.items.filter(i => i.isPurchased).length;
  }

  private getPendingItems(): ShoppingItem[] {
    return this.getFilteredItems().filter(i => !i.isPurchased);
  }

  private getPurchasedItems(): ShoppingItem[] {
    return this.getFilteredItems().filter(i => i.isPurchased);
  }

  private resetForm(): void {
    this.newItemName = '';
    this.newItemCategory = '其他';
    this.newItemQuantity = '';
    this.editingItemId = '';
  }
}
