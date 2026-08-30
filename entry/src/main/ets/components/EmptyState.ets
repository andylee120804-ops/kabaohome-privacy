/**
 * 空状态提示组件
 */
@Component
export struct EmptyState {
  @Prop icon: string = '📭';
  @Prop title: string = '暂无数据';
  @Prop subtitle: string = '';
  @Prop actionText: string = '';
  @Prop buttonColor: string = '#1565C0';
  onAction?: () => void;

  build() {
    Column({ space: 12 }) {
      Text(this.icon).fontSize(52)
      Text(this.title).fontSize(18).fontColor('#666666').fontWeight(FontWeight.Bold)
      if (this.subtitle) {
        Text(this.subtitle).fontSize(15).fontColor('#999999')
      }
      if (this.actionText) {
        Button(this.actionText)
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor(this.buttonColor)
          .borderRadius(20)
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .margin({ top: 8 })
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
  }
}
