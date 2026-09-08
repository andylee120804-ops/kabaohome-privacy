/**
 * 月视图日历组件 — 方向 C 极简编辑
 * flat：border-top/bottom 分隔线替代卡片阴影，无圆角
 * today = 墨黑反白方格；period = 红字 + 底点；ovulation = 粗体；fertile = 灰字
 * 月份导航用 < > 文字 + 墨色，周标签小号大写衬线
 */
import {
  BG_PAPER, DIVIDER, BRAND_RED, BRAND_RED_LG, NEUTRAL_INK,
  NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY, FONT_BODY, FONT_CAPTION, FONT_CAPTION_SM
} from '../common/DesignTokens';
import { PERIOD_MARK_COLORS } from '../common/Constants';

@Component
export struct CalendarView {
  @State displayYear: number = new Date().getFullYear();
  @State displayMonth: number = new Date().getMonth() + 1;
  @State selectedDate: string = '';
  @Prop markedDates: MarkedDate[] = [];
  @Prop themePrimary: string = BRAND_RED_LG;
  onDateSelected?: (date: string) => void;
  onMonthChanged?: (year: number, month: number) => void;

  private readonly WEEKDAYS: string[] = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  build() {
    Column({ space: 0 }) {
      // 月份导航
      Row() {
        Text('<')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => this.prevMonth())

        Text(`${this.displayMonth}月 ${this.displayYear}`)
          .fontSize(FONT_BODY).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          .fontFamily('serif')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text('>')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => this.nextMonth())
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })

      // 星期标题行（小号大写衬线 + 底部分隔线）
      Row() {
        ForEach(this.WEEKDAYS, (day: string) => {
          Text(day)
            .fontSize(FONT_CAPTION_SM)
            .fontColor(NEUTRAL_INK_TERTIARY)
            .fontFamily('serif')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
        }, (day: string) => day)
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      // 日期网格
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.getCalendarDays(), (dayInfo: CalendarDay) => {
          this.DayCell(dayInfo)
        }, (dayInfo: CalendarDay) => `${dayInfo.date}_${dayInfo.markColor}_${dayInfo.isPeriodStart}_${dayInfo.markIcons.join(',')}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 8 })
    .border({ width: { top: 0.5, bottom: 0.5 }, color: DIVIDER })
    .backgroundColor(BG_PAPER)
  }

  @Builder
  DayCell(dayInfo: CalendarDay) {
    Column() {
      if (dayInfo.isCurrentMonth) {
        Stack() {
          // 经期标记：红色小圆点（底部）
          if (dayInfo.markColor === PERIOD_MARK_COLORS.PERIOD && !dayInfo.isPeriodStart) {
            Circle().width(4).height(4).fill(BRAND_RED_LG)
              .position({ x: '50%', y: 26 }).translate({ x: -2 })
          }
          // 经期第一天：红色方格
          if (dayInfo.isPeriodStart) {
            Column().width(28).height(28).backgroundColor(BRAND_RED_LG)
          }
          // 日期文字
          Text(`${dayInfo.day}`)
            .fontSize(FONT_BODY)
            .fontColor(this.getDayFontColor(dayInfo))
            .fontWeight(this.isToday(dayInfo.date) || dayInfo.isPeriodStart ? FontWeight.Bold : FontWeight.Normal)
            .fontFamily('serif')
        }
        .width(28).height(28)
        .backgroundColor(this.getCellBg(dayInfo))
        .onClick(() => {
          this.selectedDate = dayInfo.date;
          if (this.onDateSelected) {
            this.onDateSelected(dayInfo.date);
          }
        })

        // 标记图标行
        Row() {
          if (dayInfo.markIcons.length > 0) {
            ForEach(dayInfo.markIcons, (icon: string) => {
              Text(icon).fontSize(8)
            }, (icon: string) => icon)
          } else if (dayInfo.markLabel) {
            Text(dayInfo.markLabel).fontSize(8).fontColor(dayInfo.markColor)
          }
        }
        .height(10)
        .justifyContent(FlexAlign.Center)
      } else {
        Text(`${dayInfo.day}`).fontSize(FONT_BODY).fontColor('#D5D5D5').fontFamily('serif')
      }
    }
    .width(`${100 / 7}%`)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getCellBg(dayInfo: CalendarDay): string | Color {
    if (dayInfo.isPeriodStart) return Color.Transparent; // bg set by Stack child
    if (this.selectedDate === dayInfo.date) return NEUTRAL_INK;
    if (this.isToday(dayInfo.date)) return BRAND_RED_LG;
    return Color.Transparent;
  }

  private getCalendarDays(): CalendarDay[] {
    const days: CalendarDay[] = [];
    const firstDay = new Date(this.displayYear, this.displayMonth - 1, 1);
    const startWeekday = firstDay.getDay();
    const daysInMonth = new Date(this.displayYear, this.displayMonth, 0).getDate();
    const daysInPrevMonth = new Date(this.displayYear, this.displayMonth - 1, 0).getDate();

    for (let i = startWeekday - 1; i >= 0; i--) {
      days.push({
        day: daysInPrevMonth - i, date: `prev_${daysInPrevMonth - i}`,
        isCurrentMonth: false, markColor: '', markIcons: [], markLabel: '', isPeriodStart: false
      });
    }
    for (let d = 1; d <= daysInMonth; d++) {
      const dateStr = this.formatDateStr(this.displayYear, this.displayMonth, d);
      const mark = this.markedDates.find(m => m.date === dateStr);
      days.push({
        day: d, date: dateStr, isCurrentMonth: true,
        markColor: mark?.color ?? '', markIcons: mark?.icons ?? [],
        markLabel: mark?.label ?? '', isPeriodStart: mark?.isPeriodStart ?? false
      });
    }
    const remaining = 42 - days.length;
    for (let i = 1; i <= remaining; i++) {
      days.push({
        day: i, date: `next_${i}`, isCurrentMonth: false,
        markColor: '', markIcons: [], markLabel: '', isPeriodStart: false
      });
    }
    return days;
  }

  private prevMonth(): void {
    if (this.displayMonth === 1) { this.displayYear--; this.displayMonth = 12; }
    else { this.displayMonth--; }
    if (this.onMonthChanged) this.onMonthChanged(this.displayYear, this.displayMonth);
  }

  private nextMonth(): void {
    if (this.displayMonth === 12) { this.displayYear++; this.displayMonth = 1; }
    else { this.displayMonth++; }
    if (this.onMonthChanged) this.onMonthChanged(this.displayYear, this.displayMonth);
  }

  private isToday(dateStr: string): boolean {
    const now = new Date();
    return dateStr === this.formatDateStr(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  private getDayFontColor(dayInfo: CalendarDay): string {
    if (this.selectedDate === dayInfo.date) return '#FFFFFF';
    if (dayInfo.isPeriodStart) return '#FFFFFF';
    if (dayInfo.markColor === PERIOD_MARK_COLORS.PERIOD) return BRAND_RED;
    if (this.isToday(dayInfo.date)) return '#FFFFFF';
    return NEUTRAL_INK;
  }

  private formatDateStr(year: number, month: number, day: number): string {
    return `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
  }
}

export interface MarkedDate {
  date: string;
  color: string;
  icons?: string[];
  label?: string;
  isPeriodStart?: boolean;
}

interface CalendarDay {
  day: number;
  date: string;
  isCurrentMonth: boolean;
  markColor: string;
  markIcons: string[];
  markLabel: string;
  isPeriodStart: boolean;
}
