/**
 * 事项列表行组件 — 方向 C 极简编辑
 * flat 行：底部分隔线 + 可选左侧 3px 强调条 + 右侧文本动作（无底色）
 */
import {
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, DIVIDER, FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, getActionColor
} from '../common/DesignTokens';

@Component
export struct CardItem {
  @Prop icon: string = '';
  @Prop iconRes: Resource | null = null;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop rightLabel: string = '';
  @Prop rightColor: string = BRAND_RED;
  @Prop leftAccent: boolean = false;
  @Prop memberColor: string = '';
  onCardClick?: () => void;
  onLongPress?: () => void;

  build() {
    Row() {
      // 左侧强调条（可选，3px 红色竖线）
      if (this.leftAccent) {
        Column().width(3).height(24).backgroundColor(BRAND_RED)
          .margin({ right: 12 })
      }

      // 图标（SVG 优先，回退 Text）
      if (this.iconRes) {
        Image(this.iconRes as Resource)
          .width(20).height(20)
          .fillColor(NEUTRAL_INK_TERTIARY)
          .margin({ right: 12 })
      } else if (this.icon) {
        Text(this.icon).fontSize(20).fontColor(NEUTRAL_INK_TERTIARY).margin({ right: 12 })
      }

      Column() {
        Text(this.title)
          .fontSize(FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(NEUTRAL_INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle) {
          Text(this.subtitle)
            .fontSize(FONT_CAPTION)
            .fontColor(NEUTRAL_INK_SECONDARY)
            .margin({ top: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧文本动作（编辑风：仅文字，1px 左分隔）
      if (this.rightLabel) {
        Text(this.rightLabel)
          .fontSize(FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.rightColor)
          .padding({ left: 12 })
          .border({ width: { left: 0.5 }, color: DIVIDER })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 16 })
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
    .onClick(() => {
      if (this.onCardClick) this.onCardClick();
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.onLongPress) this.onLongPress();
        })
    )
  }
}
