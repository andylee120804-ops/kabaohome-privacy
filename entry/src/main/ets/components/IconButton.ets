/**
 * 图标按钮 — 方向 C 极简编辑
 * 无阴影、无描边圆。SVG stroke 图标 + 可选角标。
 * 'back' → 左箭头; 'bell' → 通知铃铛
 */
import { NEUTRAL_INK, BRAND_RED_LG, SEMANTIC_ERROR, NEUTRAL_INK_TERTIARY } from '../common/DesignTokens';

@Component
export struct IconButton {
  @Prop icon: string = 'back';
  @Prop iconSize: number = 40;
  @Prop badge: number = 0;
  @Prop activeColor: string = NEUTRAL_INK;
  onTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image(this.getIconRes())
        .width(22)
        .height(22)
        .fillColor(this.activeColor)
        .onClick(() => { this.onTap(); })

      if (this.icon === 'bell' && this.badge > 0) {
        Text(this.badge > 99 ? '99+' : `${this.badge}`)
          .fontSize(9)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(BRAND_RED_LG)
          .borderRadius(8)
          .border({ width: 1, color: '#FAF7F4' })
          .padding({ left: 4, right: 4, top: 0, bottom: 0 })
          .height(14)
          .minFontSize(8)
          .maxFontSize(10)
          .position({ x: 16, y: -4 })
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .alignContent(Alignment.Center)
  }

  private getIconRes(): Resource {
    if (this.icon === 'bell') return $r('app.media.icon_bell');
    if (this.icon === 'back') return $r('app.media.icon_back');
    return $r('app.media.icon_bell');
  }
}
