/**
 * 健康指标趋势图组件 — 方向 C 极简编辑
 * 适老化大字体柱状图；用 DesignTokens 色板 + serif 字体标签
 */
import { NEUTRAL_INK, NEUTRAL_INK_SECONDARY, SEMANTIC_ERROR, SEMANTIC_INFO, SEMANTIC_SUCCESS, DIVIDER } from '../common/DesignTokens';

@Component
export struct TrendChart {
  @Prop @Watch('onDataChange') dataPoints: number[] = [];
  @Prop @Watch('onDataChange') labels: string[] = [];
  @Prop barColor: string = SEMANTIC_INFO;
  @Prop abnormalHigh: number = 0;
  @Prop abnormalLow: number = 0;
  @Prop unit: string = '';
  @Prop canvasWidth: number = 340;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private isCanvasReady: boolean = false;

  onDataChange(): void {
    if (this.isCanvasReady) this.drawChart();
  }

  build() {
    Column() {
      if (this.dataPoints.length === 0) {
        Text('暂无数据').fontSize(16).fontColor(NEUTRAL_INK_SECONDARY).textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 20 })
      } else {
        Canvas(this.context)
          .width('100%')
          .height(240)
          .onReady(() => {
            this.isCanvasReady = true;
            this.drawChart();
          })
      }
    }
    .width('100%')
    .border({ width: { top: 0.5, bottom: 0.5 }, color: DIVIDER })
  }

  private getDataPoints(): number[] { return this.dataPoints; }

  private calcMax(): number {
    const dp = this.getDataPoints();
    if (!dp || dp.length === 0) return 0;
    let max = dp[0];
    for (let i = 1; i < dp.length; i++) { if (dp[i] > max) max = dp[i]; }
    if (this.abnormalHigh > max) max = this.abnormalHigh;
    return max;
  }

  private calcMin(): number {
    const dp = this.getDataPoints();
    if (!dp || dp.length === 0) return 0;
    let min = dp[0];
    for (let i = 1; i < dp.length; i++) { if (dp[i] < min) min = dp[i]; }
    if (this.abnormalLow > 0 && this.abnormalLow < min) min = this.abnormalLow;
    return min;
  }

  private drawChart(): void {
    if (this.dataPoints.length === 0) return;
    const ctx = this.context;
    const width = this.canvasWidth;
    const height = 240;
    const leftPad = 68;
    const rightPad = 20;
    const topPad = 38;
    const bottomPad = 48;
    const chartWidth = width - leftPad - rightPad;
    const chartHeight = height - topPad - bottomPad;

    ctx.clearRect(0, 0, width, height);

    const maxVal = this.calcMax() * 1.1;
    const minVal = this.calcMin() * 0.9;
    const range = maxVal - minVal || 1;

    // 异常高值参考线
    if (this.abnormalHigh > 0) {
      const y = topPad + chartHeight - ((this.abnormalHigh - minVal) / range) * chartHeight;
      ctx.strokeStyle = '#FAEEE8';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(leftPad, y);
      ctx.lineTo(width - rightPad, y);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = SEMANTIC_ERROR;
      ctx.font = '15px serif';
      ctx.textAlign = 'right';
      ctx.fillText(`高${this.abnormalHigh}`, leftPad - 4, y + 5);
    }

    // 异常低值参考线
    if (this.abnormalLow > 0) {
      const y = topPad + chartHeight - ((this.abnormalLow - minVal) / range) * chartHeight;
      ctx.strokeStyle = '#E8F0EC';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(leftPad, y);
      ctx.lineTo(width - rightPad, y);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = SEMANTIC_SUCCESS;
      ctx.font = '15px serif';
      ctx.textAlign = 'right';
      ctx.fillText(`低${this.abnormalLow}`, leftPad - 4, y + 5);
    }

    // 柱状图
    const dataPoints = this.getDataPoints();
    const barCount = dataPoints.length;
    const barGap = chartWidth / (barCount + 1);
    const barColor = this.barColor;
    const labels = this.labels;

    for (let i = 0; i < barCount; i++) {
      const val = dataPoints[i];
      const barHeight = ((val - minVal) / range) * chartHeight;
      const x = leftPad + barGap * (i + 0.5);
      const y = topPad + chartHeight - barHeight;
      const isAbnormal = (this.abnormalHigh > 0 && val > this.abnormalHigh) ||
        (this.abnormalLow > 0 && val < this.abnormalLow);

      ctx.fillStyle = isAbnormal ? SEMANTIC_ERROR : barColor;
      ctx.fillRect(x, y, barGap * 0.6, barHeight);

      ctx.fillStyle = isAbnormal ? SEMANTIC_ERROR : NEUTRAL_INK;
      ctx.font = 'bold 16px serif';
      ctx.textAlign = 'center';
      ctx.fillText(`${val}`, x + barGap * 0.3, y - 8);

      if (labels.length > i) {
        ctx.fillStyle = NEUTRAL_INK_SECONDARY;
        ctx.font = '14px serif';
        ctx.fillText(labels[i], x + barGap * 0.3, height - 14);
      }
    }
  }
}
