/**
 * 健康指标趋势图组件 - 适老化大字体柱状图
 */
@Component
export struct TrendChart {
  @Prop @Watch('onDataChange') dataPoints: number[] = [];
  @Prop @Watch('onDataChange') labels: string[] = [];
  @Prop barColor: string = '#1565C0';
  @Prop abnormalHigh: number = 0;
  @Prop abnormalLow: number = 0;
  @Prop unit: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private isCanvasReady: boolean = false;

  onDataChange(): void {
    if (this.isCanvasReady) {
      this.drawChart();
    }
  }

  build() {
    Column() {
      if (this.dataPoints.length === 0) {
        Text('暂无数据').fontSize(16).fontColor('#999999').textAlign(TextAlign.Center)
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
  }

  private calcMax(): number {
    let max = this.dataPoints[0];
    for (let i = 1; i < this.dataPoints.length; i++) {
      if (this.dataPoints[i] > max) max = this.dataPoints[i];
    }
    if (this.abnormalHigh > max) max = this.abnormalHigh;
    return max;
  }

  private calcMin(): number {
    let min = this.dataPoints[0];
    for (let i = 1; i < this.dataPoints.length; i++) {
      if (this.dataPoints[i] < min) min = this.dataPoints[i];
    }
    if (this.abnormalLow > 0 && this.abnormalLow < min) min = this.abnormalLow;
    return min;
  }

  private drawChart(): void {
    if (this.dataPoints.length === 0) return;
    const ctx = this.context;
    const width = 340;
    const height = 240;
    const leftPad = 68;
    const rightPad = 20;
    const topPad = 38;
    const bottomPad = 48;
    const chartWidth = width - leftPad - rightPad;
    const chartHeight = height - topPad - bottomPad;

    // 清除画布后重绘
    ctx.clearRect(0, 0, width, height);

    const maxVal = this.calcMax() * 1.1;
    const minVal = this.calcMin() * 0.9;
    const range = maxVal - minVal || 1;

    // 异常高值参考线
    if (this.abnormalHigh > 0) {
      const y = topPad + chartHeight - ((this.abnormalHigh - minVal) / range) * chartHeight;
      ctx.strokeStyle = '#FFCDD2';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(leftPad, y);
      ctx.lineTo(width - rightPad, y);
      ctx.stroke();
      ctx.setLineDash([]);
      // 参考值标签 - 适老化加大字体
      ctx.fillStyle = '#C62828';
      ctx.font = '15px sans-serif';
      ctx.textAlign = 'right';
      ctx.fillText(`高${this.abnormalHigh}`, leftPad - 4, y + 5);
    }

    // 异常低值参考线
    if (this.abnormalLow > 0) {
      const y = topPad + chartHeight - ((this.abnormalLow - minVal) / range) * chartHeight;
      ctx.strokeStyle = '#C8E6C9';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 5]);
      ctx.beginPath();
      ctx.moveTo(leftPad, y);
      ctx.lineTo(width - rightPad, y);
      ctx.stroke();
      ctx.setLineDash([]);
      // 参考值标签 - 适老化加大字体
      ctx.fillStyle = '#2E7D32';
      ctx.font = '15px sans-serif';
      ctx.textAlign = 'right';
      ctx.fillText(`低${this.abnormalLow}`, leftPad - 4, y + 5);
    }

    // 柱状图
    const barCount = this.dataPoints.length;
    const barGap = chartWidth / (barCount + 1);

    for (let i = 0; i < barCount; i++) {
      const val = this.dataPoints[i];
      const barHeight = ((val - minVal) / range) * chartHeight;
      const x = leftPad + barGap * (i + 0.5);
      const y = topPad + chartHeight - barHeight;

      const isAbnormal = (this.abnormalHigh > 0 && val > this.abnormalHigh) ||
        (this.abnormalLow > 0 && val < this.abnormalLow);

      // 柱子
      ctx.fillStyle = isAbnormal ? '#C62828' : this.barColor;
      ctx.beginPath();
      ctx.fillRect(x, y, barGap * 0.6, barHeight);

      // 数值标签 - 适老化加大字体
      ctx.fillStyle = isAbnormal ? '#C62828' : '#333333';
      ctx.font = 'bold 16px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(`${val}`, x + barGap * 0.3, y - 8);

      // 日期标签 - 适老化加大字体
      if (this.labels.length > i) {
        ctx.fillStyle = '#666666';
        ctx.font = '14px sans-serif';
        ctx.fillText(this.labels[i], x + barGap * 0.3, height - 14);
      }
    }
  }
}
