/**
 * 卡宝Home - 购物清单页面
 * 设计：Direction C · 极简编辑风（纸白底 + 墨黑正文 + flat 分隔线）
 */
import { ShoppingItem, SHOPPING_CATEGORIES } from '../model/ShoppingItem';
import { LocalDbService } from '../service/LocalDbService';
import { EmptyState } from '../components/EmptyState';
import { FontSizeMode, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import {
  BG_PAPER, BG_CARD, BG_SUBTLE, DIVIDER,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  SEMANTIC_ERROR,
  FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_TITLE,
  FONT_FAMILY_SERIF, SPACE_MD, SPACE_LG, getModuleIconRes
} from '../common/DesignTokens';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { generateId } from '../common/Utils';
import router from '@ohos.router';

@Entry
@Component
struct ShoppingPage {
  @State items: ShoppingItem[] = [];
  @State selectedCategory: string = '';
  @State showAddDialog: boolean = false;
  @State isSavingItem: boolean = false;
  @State newItemName: string = '';
  @State newItemCategory: string = '其他';
  @State newItemQuantity: string = '';
  @State isLargeFont: boolean = false;
  @State editingItemId: string = '';
  @State fontSize: number = FONT_BODY_LARGE;
  @State titleFontSize: number = FONT_TITLE;

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  aboutToAppear(): void {
    this.items = this.db.getShoppingItems();
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
  }

  build() {
    Column() {
      // —— 顶栏 ——
      Row() {
        Image($r('app.media.icon_back'))
          .width(24).height(24).fillColor(NEUTRAL_INK)
          .onClick(() => { router.back(); })

        Row() {
          Image(getModuleIconRes('shopping'))
            .width(20).height(20).fillColor(NEUTRAL_INK)
          Text('购物清单')
            .fontSize(this.titleFontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
            .margin({ left: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        Text('+')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK)
          .onClick(() => {
            this.editingItemId = '';
            this.resetForm();
            this.showAddDialog = true;
          })
      }
      .width('100%')
      .padding({ left: SPACE_MD, right: SPACE_MD, top: 12, bottom: 8 })

      // —— 分类筛选（text-only with underline）——
      Scroll() {
        Row({ space: 24 }) {
          Text('全部')
            .fontSize(FONT_CAPTION)
            .fontColor(this.selectedCategory === '' ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
            .fontWeight(this.selectedCategory === '' ? FontWeight.Bold : FontWeight.Normal)
            .border({ width: { bottom: this.selectedCategory === '' ? 2 : 0 }, color: NEUTRAL_INK })
            .padding({ bottom: 4 })
            .onClick(() => { this.selectedCategory = ''; })
          ForEach(SHOPPING_CATEGORIES, (cat: string) => {
            Text(cat)
              .fontSize(FONT_CAPTION)
              .fontColor(this.selectedCategory === cat ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
              .fontWeight(this.selectedCategory === cat ? FontWeight.Bold : FontWeight.Normal)
              .border({ width: { bottom: this.selectedCategory === cat ? 2 : 0 }, color: NEUTRAL_INK })
              .padding({ bottom: 4 })
              .onClick(() => { this.selectedCategory = cat; })
          }, (cat: string) => cat)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ left: SPACE_MD, right: SPACE_MD, bottom: 8 })

      // —— 统计 ——
      Row() {
        Text(`待买 ${this.getPendingCount()} 项`)
          .fontSize(FONT_BODY).fontColor(NEUTRAL_INK).layoutWeight(1)
        Text(`已买 ${this.getPurchasedCount()} 项`)
          .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY)
      }
      .width('100%')
      .padding({ left: SPACE_MD, right: SPACE_MD, bottom: 8 })

      // —— 购物列表 ——
      Scroll() {
        if (this.items.length === 0) {
          EmptyState({
            icon: '🛒',
            title: '购物清单为空',
            subtitle: '添加需要购买的物品',
            actionText: '+ 添加物品',
            buttonColor: NEUTRAL_INK,
            onAction: () => {
              this.editingItemId = '';
              this.resetForm();
              this.showAddDialog = true;
            }
          })
        } else {
          Column({ space: 0 }) {
            // 待买
            if (this.getPendingItems().length > 0) {
              this.SectionTitle('待买')
              ForEach(this.getPendingItems(), (item: ShoppingItem) => {
                this.ShoppingItemRow(item)
              }, (item: ShoppingItem) => item.id + '_' + item.updatedAt)
            }

            // 已买
            if (this.getPurchasedItems().length > 0) {
              this.SectionTitle('已买')
              ForEach(this.getPurchasedItems(), (item: ShoppingItem) => {
                this.ShoppingItemRow(item)
              }, (item: ShoppingItem) => item.id + '_' + item.updatedAt)
            }

            // 底部添加按钮
            Text('+ 添加物品')
              .fontSize(FONT_BODY)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 14 })
              .backgroundColor(NEUTRAL_INK)
              .margin({ top: 16 })
              .onClick(() => {
                this.editingItemId = '';
                this.resetForm();
                this.showAddDialog = true;
              })
          }
          .padding({ left: SPACE_MD, right: SPACE_MD })
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BG_PAPER)
    .bindContentCover(this.showAddDialog, this.AddItemDialog())
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(FONT_BODY_LARGE)
      .fontWeight(FontWeight.Bold)
      .fontColor(NEUTRAL_INK)
      .fontFamily(FONT_FAMILY_SERIF)
      .width('100%')
      .padding({ top: 16, bottom: 8 })
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
          .fontSize(this.fontSize)
          .fontColor(item.isPurchased ? NEUTRAL_INK_TERTIARY : NEUTRAL_INK)
          .decoration({ type: item.isPurchased ? TextDecorationType.LineThrough : TextDecorationType.None })
        if (item.quantity) {
          Text(item.quantity)
            .fontSize(FONT_CAPTION)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Right: text-only, no bg pill
      Text(item.category)
        .fontSize(FONT_CAPTION)
        .fontColor(NEUTRAL_INK_TERTIARY)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
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
                fontColor: SEMANTIC_ERROR,
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
        Column() {
          Text(this.editingItemId ? '编辑物品' : '添加购物物品')
            .fontSize(FONT_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
            .width('100%')
            .margin({ bottom: 16 })

          Text('名称')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
          TextInput({ placeholder: '物品名称（如：牛奶）', text: this.newItemName })
            .fontSize(FONT_BODY)
            .width('100%').padding(10).borderRadius(0)
            .backgroundColor(BG_SUBTLE)
            .margin({ bottom: 12 })
            .onChange((v: string) => { this.newItemName = v; })

          Text('分类')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
          Scroll() {
            Row({ space: 12 }) {
              ForEach(SHOPPING_CATEGORIES, (cat: string) => {
                Text(cat)
                  .fontSize(FONT_CAPTION)
                  .fontColor(this.newItemCategory === cat ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
                  .fontWeight(this.newItemCategory === cat ? FontWeight.Bold : FontWeight.Normal)
                  .border({ width: { bottom: this.newItemCategory === cat ? 2 : 0 }, color: NEUTRAL_INK })
                  .padding({ bottom: 4 })
                  .onClick(() => { this.newItemCategory = cat; })
              }, (cat: string) => cat)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ bottom: 12 })

          Text('数量')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
          TextInput({ placeholder: '数量（如：2盒，可选）', text: this.newItemQuantity })
            .fontSize(FONT_BODY)
            .width('100%').padding(10).borderRadius(0)
            .backgroundColor(BG_SUBTLE)
            .margin({ bottom: 16 })
            .onChange((v: string) => { this.newItemQuantity = v; })

          Row({ space: 12 }) {
            Button('取消')
              .fontSize(FONT_BODY)
              .fontColor(NEUTRAL_INK_SECONDARY)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: DIVIDER })
              .borderRadius(0)
              .layoutWeight(1)
              .onClick(() => {
                this.showAddDialog = false;
                this.editingItemId = '';
                this.resetForm();
              })
            Button(this.isSavingItem ? '保存中...' : (this.editingItemId ? '保存' : '添加'))
              .fontSize(FONT_BODY)
              .fontColor(Color.White)
              .backgroundColor(NEUTRAL_INK)
              .borderRadius(0)
              .layoutWeight(1)
              .enabled(!this.isSavingItem)
              .onClick(async () => {
                if (this.isSavingItem) return;
                this.isSavingItem = true;
                try {
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
                    const family = this.db.getCurrentFamily();
                    const resolvedVis = this.db.resolveModuleVisibilityForRecord(ModuleId.SHOPPING);
                    const item: ShoppingItem = {
                      id: generateId('si'),
                      familyId: family?.id ?? '',
                      creatorId: this.db.getCurrentMemberId(),
                      visibility: resolvedVis.visibility,
                      visibleMembers: resolvedVis.visibleMembers,
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
                } finally {
                  this.isSavingItem = false;
                }
              })
          }
          .width('100%')
        }
        .width('90%')
        .padding(20)
        .backgroundColor(BG_CARD)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .justifyContent(FlexAlign.Center)
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
