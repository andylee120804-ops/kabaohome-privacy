/**
 * 可左滑确认的待办卡片
 *
 * 交互设计：
 *   - 轻滑吸附：拖动 > 32vp 松手，露出右侧操作按钮
 *   - 渐进反馈：拖过 140vp 后，按钮逐步膨胀 + 变绿 → "快到了"
 *   - 自动触发：拖过 250vp，卡片向左飘走淡出 → 确认完成
 *   - 点击主体：折叠状态先复位，正常状态走导航
 *
 * 布局同前：外层 clip Column → 内层 Row(.translate) → [卡片(100%) | 操作按钮]
 */

const ACTION_WIDTH: number = 88;           // 操作按钮基础宽度
const ACTION_MAX_WIDTH: number = 150;      // 拖到触发阈值按钮膨胀到的宽度
const SNAP_THRESHOLD: number = 32;         // 松手时超过此距离吸附到展开
const WARN_THRESHOLD: number = 140;        // 拖过此距离开始渐进膨胀 + 变色预警
const TRIGGER_THRESHOLD: number = 250;     // 拖过此距离自动确认（≈70% 屏宽）
const ANIM_DURATION: number = 250;         // 普通吸附动画
const EXIT_ANIM_DURATION: number = 320;    // 退出飘走动画（稍慢，丝滑）
const EXIT_DISTANCE: number = 600;         // 退出时卡片飘走的横向距离

@Component
export struct SwipeableTodoCard {
  @Prop moduleIcon: string = '📋';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop action: string = '完成';
  @Prop primaryColor: string = '#E8654A';
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
  /** 0.0~1.0：从 WARN → TRIGGER 的渐进进度，驱动按钮膨胀和变色 */
  @State triggerProgress: number = 0;
  private dragStartX: number = 0;

  build() {
    Column() {
      Row() {
        // ── 1) 卡片主体 ──
        Row() {
          Text(this.moduleIcon).fontSize(22).margin({ right: 12 })

          Column() {
            Text(this.title)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.subtitle) {
              Text(this.subtitle)
                .fontSize(14).fontColor('#888888').margin({ top: 3 })
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          // 右侧主操作按钮（始终可见，与左滑独立）
          Button(this.getPrimaryButtonLabel())
            .fontSize(14).fontColor(Color.White).backgroundColor(this.getPrimaryButtonColor())
            .borderRadius(10).padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .type(ButtonType.Normal)
            .onClick(() => {
              this.onPrimaryAction();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .borderRadius(12)
        .backgroundColor(Color.White)
        .shadow({ radius: 2, color: '#0A000000', offsetX: 0, offsetY: 1 })
        .onClick(() => {
          if (this.exitMode) return;
          if (this.translateX < 0) {
            this.resetPosition();
            return;
          }
          this.onTap();
        })

        // ── 2) 左滑操作按钮 ──
        if (!this.disableSwipe) {
          Column() {
            Text(this.triggerProgress >= 0.5 ? '✓' : this.getActionIcon())
              .fontSize(20 + this.triggerProgress * 8)
              .fontColor(Color.White)
            Text(this.triggerProgress >= 0.5 ? '已确认' : this.getActionLabel())
              .fontSize(12).fontColor(Color.White).margin({ top: 4 })
          }
          .width(ACTION_WIDTH + this.triggerProgress * (ACTION_MAX_WIDTH - ACTION_WIDTH))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 14, bottom: 14 })
          .borderRadius(12)
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

            // 渐进进度：WARN ↔ TRIGGER 之间线性增长 0→1
            if (this.autoTriggerOnSwipe) {
              const dragDist = -next;
              if (dragDist >= WARN_THRESHOLD) {
                this.triggerProgress = Math.min(1,
                  (dragDist - WARN_THRESHOLD) / (TRIGGER_THRESHOLD - WARN_THRESHOLD));
              } else {
                this.triggerProgress = 0;
              }
            }

            // 达到触发阈值：飘走 + 确认
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
            if (this.hasTriggered) {
              this.hasTriggered = false;
              return;
            }
            this.isAnimating = true;
            const dx = this.translateX;
            if (dx <= -SNAP_THRESHOLD) {
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

  /** 复位到初始位置（动画） */
  private resetPosition(): void {
    this.isAnimating = true;
    this.exitMode = false;
    this.translateX = 0;
    this.cardOpacity = 1;
    this.triggerProgress = 0;
  }

  // ── 操作按钮：根据 triggerProgress 渐进变色 ──

  private getProgressActionBgColor(): string {
    if (this.triggerProgress <= 0) return this.getActionBgColor();
    if (this.triggerProgress >= 1) return '#43A047';
    // 0 < progress < 1：在原始色和绿色之间取中间态
    const baseColor = this.getActionBgColor();
    if (this.triggerProgress < 0.5) return baseColor;
    return '#388E3C';
  }

  // ── 以下为原有辅助方法（不变） ──

  private getActionIcon(): string {
    if (this.action === '待服') return '💊';
    if (this.action === '知道了') return '👁';
    return '✓';
  }

  private getActionLabel(): string {
    if (this.action === '待服') return '已服';
    if (this.action === '知道了') return '已读';
    if (this.action === '完成') return '已完成';
    return '✓';
  }

  private getActionBgColor(): string {
    if (this.action === '待服') return this.primaryColor;
    if (this.action === '完成') return '#2E7D32';
    return '#1565C0';
  }

  private getPrimaryButtonLabel(): string {
    if (this.action === '待服') return '💊 服药';
    if (this.action === '完成') return '✓ 完成';
    return this.action;
  }

  private getPrimaryButtonColor(): string {
    if (this.action === '待服') return this.primaryColor;
    if (this.action === '完成') return '#1565C0';
    if (this.action === '查看') return '#2E7D32';
    return this.primaryColor;
  }
}
