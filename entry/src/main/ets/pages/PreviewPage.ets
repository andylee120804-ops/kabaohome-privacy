/**
 * Previewer 专用页面 - 不依赖任何原生Kit
 * 用于在 Previewer 中预览 UI 样式
 * 方向 C · 极简编辑：纸白底 + 墨黑衬线标题 + SVG 图标 + flat 卡片
 */
import { curves } from '@kit.ArkUI';
import { PAGE_TRANSITION_DURATION } from '../common/Constants';
import {
  BG_PAPER, BG_CARD, DIVIDER,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  FONT_BODY, FONT_BODY_LARGE, FONT_TITLE, FONT_DISPLAY,
  FONT_CAPTION, FONT_FAMILY_SERIF,
  SPACE_XS, SPACE_SM, SPACE_MD, SPACE_LG,
  getModuleIconRes
} from '../common/DesignTokens';

@Entry
@Component
struct PreviewPage {
  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(1)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).opacity(0)
  }

  build() {
    Column() {
      // App Logo — flat, no shadow
      Image($r('app.media.app_icon'))
        .width(72)
        .height(72)
        .borderRadius(0)
        .objectFit(ImageFit.Cover)
        .margin({ top: 60 })

      Text('卡宝Home')
        .fontSize(FONT_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(NEUTRAL_INK)
        .fontFamily(FONT_FAMILY_SERIF)
        .margin({ top: SPACE_SM })

      Text('家庭管理助手')
        .fontSize(FONT_BODY_LARGE)
        .fontColor(NEUTRAL_INK_SECONDARY)
        .margin({ top: SPACE_XS })

      // 功能卡片网格
      Column() {
        Text('核心功能')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .fontFamily(FONT_FAMILY_SERIF)
          .width('100%')
          .margin({ bottom: SPACE_MD })

        Row() {
          this.FuncCard('accounting', '记账')
          this.FuncCard('album', '相册')
          this.FuncCard('health', '健康')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          this.FuncCard('kids', '儿童')
          this.FuncCard('location', '位置')
          this.FuncCard('memo', '备忘')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: SPACE_SM })
      }
      .width('100%')
      .padding(SPACE_LG)
      .margin({ top: 40 })

      Text('Previewer 预览模式')
        .fontSize(FONT_CAPTION)
        .fontColor(NEUTRAL_INK_TERTIARY)
        .position({ x: '50%', y: '95%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAPER)
    .padding(SPACE_LG)
  }

  @Builder
  FuncCard(moduleId: string, label: string) {
    Column() {
      Image(getModuleIconRes(moduleId))
        .width(32)
        .height(32)
        .fillColor(NEUTRAL_INK_SECONDARY)
        .margin({ bottom: SPACE_SM })
      Text(label)
        .fontSize(FONT_BODY)
        .fontColor(NEUTRAL_INK)
    }
    .width('30%')
    .aspectRatio(1.0)
    .backgroundColor(BG_CARD)
    .border({ width: 0.5, color: DIVIDER })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
