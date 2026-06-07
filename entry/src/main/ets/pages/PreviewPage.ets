/**
 * Previewer 专用页面 - 不依赖任何原生Kit
 * 用于在 Previewer 中预览 UI 样式
 */
@Entry
@Component
struct PreviewPage {
  build() {
    Column() {
      // App Logo
      Text('📱')
        .fontSize(64)
        .margin({ top: 60 })

      Text('卡宝Home')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1565C0')
        .margin({ top: 8 })

      Text('家庭管理助手')
        .fontSize(16)
        .fontColor('#666666')
        .margin({ top: 4 })

      // 功能卡片网格
      Column() {
        Text('核心功能')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .margin({ bottom: 12 })

        Row() {
          this.FuncCard('💰', '记账', '#FFE0B2')
          this.FuncCard('📸', '相册', '#BBDEFB')
          this.FuncCard('🏃', '健康', '#C8E6C9')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          this.FuncCard('👶', '儿童', '#E1BEE7')
          this.FuncCard('📍', '位置', '#B2EBF2')
          this.FuncCard('📝', '备忘', '#FFECB3')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 12 })
      }
      .width('100%')
      .padding(24)
      .margin({ top: 40 })

      Text('Previewer 预览模式')
        .fontSize(13)
        .fontColor('#999999')
        .position({ x: '50%', y: '95%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
    .padding(24)
  }

  @Builder
  FuncCard(icon: string, label: string, bgColor: string) {
    Column() {
      Text(icon)
        .fontSize(36)
        .margin({ bottom: 8 })
      Text(label)
        .fontSize(14)
        .fontColor('#333333')
    }
    .width('30%')
    .aspectRatio(1.0)
    .backgroundColor(bgColor)
    .borderRadius(16)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
