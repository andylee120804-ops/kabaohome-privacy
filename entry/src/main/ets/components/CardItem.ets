/**
 * 事项卡片组件 - 通用卡片布局
 * 设计原则：简约、字体大、间距舒适
 */
@Component
export struct CardItem {
  @Prop icon: string = '📋';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop rightLabel: string = '';
  @Prop rightColor: string = '#1565C0';
  @Prop leftBorderColor: string = '';
  @Prop cardBackgroundColor: string = '#FFFFFF';
  @Prop memberColor: string = '';
  onCardClick?: () => void;
  onLongPress?: () => void;

  build() {
    Row() {
      // 颜色条标识（可选）
      if (this.memberColor) {
        Column().width(4).height(24).borderRadius(2).backgroundColor(this.memberColor)
          .margin({ right: 8 })
      }

      Text(this.icon).fontSize(22).margin({ right: 10 })

      Column() {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle) {
          Text(this.subtitle)
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.rightLabel) {
        Text(this.rightLabel)
          .fontSize(13)
          .fontColor(this.rightColor)
          .backgroundColor(this.getBgColor())
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor(this.cardBackgroundColor)
    .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
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

  private getBgColor(): string {
    if (this.rightColor === '#4CAF50') return '#E8F5E9';
    if (this.rightColor === '#FF9800') return '#FFF8E1';
    if (this.rightColor === '#C62828') return '#FFEBEE';
    return '#E3F2FD';
  }
}
