/**
 * 可左滑确认的待办行 — 方向 C 极简编辑
 * flat 行 + 底部分隔线 + 右侧文本动作（无底色，1px 左分隔线）
 * 左滑逻辑保持不变，操作按钮为墨黑底色
 */
import {
  BG_PAPER, DIVIDER, BRAND_RED, NEUTRAL_INK, NEUTRAL_INK_SECONDARY,
  SEMANTIC_SUCCESS, FONT_BODY_LARGE, FONT_CAPTION,
  getActionBgColor
} from '../common/DesignTokens';

const ACTION_WIDTH: number = 88;
const ACTION_MAX_WIDTH: number = 150;
const SNAP_THRESHOLD: number = 32;
const WARN_THRESHOLD: number = 140;
const TRIGGER_THRESHOLD: number = 250;
const ANIM_DURATION: number = 250;
const EXIT_ANIM_DURATION: number = 320;
const EXIT_DISTANCE: number = 600;

/** 动作标签文本 */
function getActionLabel(action: string): string {
  if (action === '待服') return '服药';
  if (action === '完成') return '完成';
  if (action === '知道了') return '确认';
  return action;
}

@Component
export struct SwipeableTodoCard {
  @Prop moduleIcon: string = '';
  @Prop iconRes: Resource | null = null;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop timeLabel: string = '';
  @Prop action: string = '完成';
  @Prop primaryColor: string = BRAND_RED;
  @Prop accent: boolean = false;
  @Prop disableSwipe: boolean = false;
  @Prop autoTriggerOnSwipe: boolean = true;

  onTap: () => void = () => {};
  onComplete: () => void = () => {};
  onPrimaryAction: () => void = () => {};

  @State translateX: number = 0;
  @State cardOpacity: number = 1;
  @State isAnimating: boolean = false;
  @State exitMode: boolean = false;
  @State hasTriggered: boolean = false;
  @State triggerProgress: number = 0;
  private dragStartX: number = 0;

  build() {
    Column() {
      Row() {
        // ── 卡片主体（flat 行） ──
        Row() {
          // 左侧强调条
          if (this.accent) {
            Column().width(3).height(24).backgroundColor(BRAND_RED)
              .margin({ right: 12 })
          }

          // 时间标签（大号衬线，如 demo C 的 todo-time）
          if (this.timeLabel) {
            Text(this.timeLabel)
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor(NEUTRAL_INK)
              .fontFamily('serif')
              .width(56)
              .margin({ right: 8 })
          }

          // 图标
          if (this.iconRes) {
            Image(this.iconRes as Resource)
              .width(20).height(20)
              .fillColor(NEUTRAL_INK_SECONDARY)
              .margin({ right: 12 })
          } else if (this.moduleIcon) {
            Text(this.moduleIcon).fontSize(20).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 12 })
          }

          Column() {
            Text(this.title)
              .fontSize(FONT_BODY_LARGE).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.subtitle) {
              Text(this.subtitle)
                .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 3 })
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // 右侧文本动作（编辑风：文字 + 左分隔线）
          Text(this.action)
            .fontSize(FONT_CAPTION).fontWeight(FontWeight.Medium)
            .fontColor(this.getActionTextColor())
            .padding({ left: 12 })
            .border({ width: { left: 0.5 }, color: DIVIDER })
            .onClick(() => { this.onPrimaryAction(); })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })
        .border({ width: { bottom: 0.5 }, color: DIVIDER })
        .backgroundColor(BG_PAPER)
        .onClick(() => {
          if (this.exitMode) return;
          if (this.translateX < 0) { this.resetPosition(); return; }
          this.onTap();
        })

        // ── 左滑操作按钮 ──
        if (!this.disableSwipe) {
          Column() {
            Text(this.triggerProgress >= 0.5 ? '✓' : '✓')
              .fontSize(20 + this.triggerProgress * 8)
              .fontColor(Color.White)
            Text(this.triggerProgress >= 0.5 ? '已确认' : getActionLabel(this.action))
              .fontSize(FONT_CAPTION).fontColor(Color.White).margin({ top: 4 })
          }
          .width(ACTION_WIDTH + this.triggerProgress * (ACTION_MAX_WIDTH - ACTION_WIDTH))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 14, bottom: 14 })
          .backgroundColor(this.getProgressActionBgColor())
          .margin({ left: 8 })
          .onClick(() => {
            this.onComplete();
            this.resetPosition();
          })
        }
      }
      .translate({ x: this.translateX })
      .opacity(this.cardOpacity)
      .animation(this.exitMode
        ? { duration: EXIT_ANIM_DURATION, curve: Curve.EaseIn }
        : this.isAnimating
          ? { duration: ANIM_DURATION, curve: Curve.EaseOut }
          : { duration: 0 })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
          .onActionStart(() => {
            if (this.disableSwipe) return;
            this.isAnimating = false;
            this.exitMode = false;
            this.hasTriggered = false;
            this.triggerProgress = 0;
            this.dragStartX = this.translateX;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.disableSwipe) return;
            if (this.hasTriggered) return;
            let next = this.dragStartX + event.offsetX;
            if (next > 8) next = 8;
            const maxLeft = this.autoTriggerOnSwipe
              ? -(TRIGGER_THRESHOLD + 40)
              : -(ACTION_WIDTH + 16);
            if (next < maxLeft) next = maxLeft;
            this.translateX = next;
            if (this.autoTriggerOnSwipe) {
              const dragDist = -next;
              if (dragDist >= WARN_THRESHOLD) {
                this.triggerProgress = Math.min(1,
                  (dragDist - WARN_THRESHOLD) / (TRIGGER_THRESHOLD - WARN_THRESHOLD));
              } else {
                this.triggerProgress = 0;
              }
            }
            if (this.autoTriggerOnSwipe && next <= -TRIGGER_THRESHOLD) {
              this.hasTriggered = true;
              this.exitMode = true;
              this.translateX = -EXIT_DISTANCE;
              this.cardOpacity = 0;
              this.onComplete();
            }
          })
          .onActionEnd(() => {
            if (this.disableSwipe) return;
            if (this.hasTriggered) { this.hasTriggered = false; return; }
            this.isAnimating = true;
            if (this.translateX <= -SNAP_THRESHOLD) {
              this.translateX = -(ACTION_WIDTH + 8);
            } else {
              this.translateX = 0;
            }
            this.triggerProgress = 0;
          })
      )
    }
    .width('100%')
    .clip(true)
  }

  private resetPosition(): void {
    this.isAnimating = true;
    this.exitMode = false;
    this.translateX = 0;
    this.cardOpacity = 1;
    this.triggerProgress = 0;
  }

  private getProgressActionBgColor(): string {
    if (this.triggerProgress <= 0) return this.getActionBgColor();
    if (this.triggerProgress >= 1) return SEMANTIC_SUCCESS;
    if (this.triggerProgress < 0.5) return this.getActionBgColor();
    return '#4A7A6B';
  }

  private getActionBgColor(): string {
    return getActionBgColor(this.action, this.primaryColor);
  }

  private getActionTextColor(): string {
    if (this.action === '完成') return SEMANTIC_SUCCESS;
    if (this.action === '查看') return NEUTRAL_INK_SECONDARY;
    return BRAND_RED;
  }
}
