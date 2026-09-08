/**
 * 空状态提示组件 — 方向 C 极简编辑
 * 墨黑标题 + 纸白背景 + 墨黑主按钮（直角）
 */
import {
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, BRAND_RED, BG_PAPER,
  FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION
} from '../common/DesignTokens';

@Component
export struct EmptyState {
  @Prop icon: string = '';
  @Prop title: string = '暂无数据';
  @Prop subtitle: string = '';
  @Prop actionText: string = '';
  onAction?: () => void;

  build() {
    Column({ space: 12 }) {
      if (this.icon) {
        Text(this.icon).fontSize(48).fontColor(NEUTRAL_INK_SECONDARY)
      }
      Text(this.title)
        .fontSize(FONT_BODY_LARGE)
        .fontColor(NEUTRAL_INK)
        .fontWeight(FontWeight.Medium)
      if (this.subtitle) {
        Text(this.subtitle)
          .fontSize(FONT_BODY)
          .fontColor(NEUTRAL_INK_SECONDARY)
      }
      if (this.actionText) {
        Button(this.actionText)
          .fontSize(FONT_BODY)
          .fontColor(Color.White)
          .backgroundColor(NEUTRAL_INK)
          .borderRadius(0)
          .padding({ left: 32, right: 32, top: 12, bottom: 12 })
          .margin({ top: 8 })
          .type(ButtonType.Normal)
          .onClick(() => {
            if (this.onAction) this.onAction();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(40)
    .backgroundColor(BG_PAPER)
  }
}
