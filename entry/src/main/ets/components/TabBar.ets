/**
 * 动态底部 Tab 导航组件 — 方向 C 极简编辑
 * flat 底栏 + 1px 顶分隔线 + SVG stroke 图标（激活红，非激活灰）
 * TabItemView：图标 + 小字 label，选中态仅色变无线底
 * TabBar：首页 + 动态模块 + 我的
 */
import { MAX_CUSTOM_TABS, ModuleId } from '../common/Constants';
import { ModuleManager } from '../viewmodel/ModuleManager';
import {
  BG_PAPER, DIVIDER, BRAND_RED_LG, NEUTRAL_INK, NEUTRAL_INK_TERTIARY,
  FONT_CAPTION_SM, getTabIconRes, getModuleIconRes
} from '../common/DesignTokens';

@Component
struct TabItemView {
  @Prop isActive: boolean = false;
  @Prop iconRes: Resource = $r('app.media.icon_home');
  @Prop label: string = '';
  onTabChange: () => void = () => {};

  build() {
    Column({ space: 4 }) {
      Image(this.iconRes)
        .width(22)
        .height(22)
        .fillColor(this.isActive ? BRAND_RED_LG : NEUTRAL_INK_TERTIARY)
      Text(this.label)
        .fontSize(FONT_CAPTION_SM)
        .fontColor(this.isActive ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
        .fontWeight(this.isActive ? FontWeight.Medium : FontWeight.Normal)
        .fontFamily('serif')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    .onClick(() => {
      this.onTabChange();
    })
  }
}

@Component
export struct TabBar {
  @Prop enabledModules: ModuleId[] = [];
  @Prop currentTab: number = 0;
  onTabChange: (index: number) => void = () => {};

  build() {
    Row() {
      // 首页（固定）
      TabItemView({
        isActive: this.currentTab === 0,
        iconRes: getTabIconRes('home'),
        label: '首页',
        onTabChange: () => { this.onTabChange(0); }
      })

      // 动态模块 Tab
      ForEach(this.enabledModules.slice(0, MAX_CUSTOM_TABS), (moduleId: ModuleId, index: number) => {
        TabItemView({
          isActive: this.currentTab === index + 1,
          iconRes: getModuleIconRes(moduleId),
          label: ModuleManager.getModuleDef(moduleId)?.name ?? '',
          onTabChange: () => { this.onTabChange(index + 1); }
        })
      }, (moduleId: ModuleId) => moduleId)

      // 我的（固定）
      TabItemView({
        isActive: this.currentTab === this.enabledModules.length + 1,
        iconRes: getTabIconRes('profile'),
        label: '我的',
        onTabChange: () => { this.onTabChange(this.enabledModules.length + 1); }
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 12 })
    .backgroundColor(BG_PAPER)
    .border({ width: { top: 0.5 }, color: DIVIDER })
  }
}
