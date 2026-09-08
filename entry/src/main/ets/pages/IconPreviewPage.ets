/**
 * 图标预览页 — 方向 C stroke 线性图标一览
 */
import { IconButton } from '../components/IconButton';
import { NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY, BRAND_RED_LG, DIVIDER, BG_PAPER, FONT_BODY, FONT_CAPTION } from '../common/DesignTokens';
import router from '@ohos.router';

@Entry
@Component
struct IconPreviewPage {
  build() {
    Column() {
      // Header
      Row() {
        IconButton({
          icon: 'back',
          activeColor: NEUTRAL_INK,
          onTap: () => { router.back(); }
        })
        Text('图标一览')
          .fontSize(FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(NEUTRAL_INK)
          .fontFamily('serif')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        IconButton({
          icon: 'bell',
          badge: 8,
          activeColor: NEUTRAL_INK,
          onTap: () => {}
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 12, bottom: 12 })
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      Scroll() {
        Column({ space: 0 }) {
          this.IconRow('首页', $r('app.media.icon_home'))
          this.IconRow('周期', $r('app.media.icon_heart'))
          this.IconRow('提醒', $r('app.media.icon_bell'))
          this.IconRow('记账', $r('app.media.icon_wallet'))
          this.IconRow('我的', $r('app.media.icon_profile'))
          this.IconRow('位置', $r('app.media.icon_location'))
          this.IconRow('相册', $r('app.media.icon_camera'))
          this.IconRow('购物', $r('app.media.icon_cart'))
          this.IconRow('备忘', $r('app.media.icon_memo'))
          this.IconRow('用药', $r('app.media.icon_pill'))
          this.IconRow('事项', $r('app.media.icon_book'))
          this.IconRow('确认', $r('app.media.icon_checklist'))
          this.IconRow('收藏', $r('app.media.icon_star'))
          this.IconRow('返回', $r('app.media.icon_back'))
          this.IconRow('时钟', $r('app.media.icon_clock'))

          // 通知角标状态
          Column({ space: 12 }) {
            Text('通知角标')
              .fontSize(FONT_CAPTION)
              .fontColor(NEUTRAL_INK_SECONDARY)
              .fontFamily('serif')
            Row({ space: 24 }) {
              Column({ space: 4 }) {
                IconButton({ icon: 'bell', badge: 0, onTap: () => {} })
                Text('无').fontSize(10).fontColor(NEUTRAL_INK_TERTIARY)
              }
              Column({ space: 4 }) {
                IconButton({ icon: 'bell', badge: 5, onTap: () => {} })
                Text('5').fontSize(10).fontColor(NEUTRAL_INK_TERTIARY)
              }
              Column({ space: 4 }) {
                IconButton({ icon: 'bell', badge: 99, onTap: () => {} })
                Text('99').fontSize(10).fontColor(NEUTRAL_INK_TERTIARY)
              }
            }
          }
          .width('100%')
          .padding(24)
          .border({ width: { top: 0.5 }, color: DIVIDER })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAPER)
  }

  @Builder
  IconRow(label: string, iconRes: Resource) {
    Row() {
      Image(iconRes).width(22).height(22).fillColor(NEUTRAL_INK).margin({ right: 16 })
      Text(label)
        .fontSize(FONT_BODY)
        .fontColor(NEUTRAL_INK)
        .layoutWeight(1)
      Image(iconRes).width(22).height(22).fillColor(NEUTRAL_INK_TERTIARY)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 14 })
    .border({ width: { bottom: 0.5 }, color: DIVIDER })
  }
}
