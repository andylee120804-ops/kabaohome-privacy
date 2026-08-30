/**
 * 月视图日历组件 - 用于周期页面和提醒页面
 */
@Component
export struct CalendarView {
  @State displayYear: number = new Date().getFullYear();
  @State displayMonth: number = new Date().getMonth() + 1;
  @State selectedDate: string = '';
  @Prop markedDates: MarkedDate[] = [];
  @Prop themePrimary: string = '#1565C0';
  @Prop themeBorder: string = '#FFD4C2';
  onDateSelected?: (date: string) => void;
  onMonthChanged?: (year: number, month: number) => void;

  private readonly WEEKDAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

  build() {
    Column({ space: 8 }) {
      // 月份导航
      Row() {
        Row() {
          Text('<')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(22).height(22).borderRadius(11)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.prevMonth())
        .margin({ right: 4 })
        Text(`${this.displayYear}年${this.displayMonth}月`)
          .fontSize(16).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center)
          .margin({ left: 4, right: 4 })
        Row() {
          Text('>')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(22).height(22).borderRadius(11)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.nextMonth())
        .margin({ left: 4 })
      }
      .width('auto')

      // 星期标题
      Row() {
        ForEach(this.WEEKDAYS, (day: string) => {
          Text(day)
            .fontSize(12).fontColor('#999999').textAlign(TextAlign.Center).layoutWeight(1)
        }, (day: string) => day)
      }
      .width('100%')

      // 日期网格
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.getCalendarDays(), (dayInfo: CalendarDay) => {
          this.DayCell(dayInfo)
        }, (dayInfo: CalendarDay) => `${dayInfo.date}_${dayInfo.markColor}_${dayInfo.isPeriodStart}_${dayInfo.markIcons.join(',')}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(Color.White)
  }

  @Builder
  DayCell(dayInfo: CalendarDay) {
    Column() {
      if (dayInfo.isCurrentMonth) {
        Stack() {
          // 背景色块 - 经期用实心圆，其他类型用半透明圆
          if (dayInfo.markColor) {
            if (dayInfo.markColor === '#E91E63') {
              // 经期：实心填充，更醒目
              Circle().width(32).height(32).fill('#E91E63').opacity(0.75)
            } else {
              Circle().width(32).height(32).fill(dayInfo.markColor).opacity(0.25)
            }
          }
          // 经期第一天标记
          if (dayInfo.isPeriodStart) {
            Circle().width(32).height(32).fill('#E91E63')
          }
          // 日期文字
          Text(`${dayInfo.day}`)
            .fontSize(14)
            .fontColor(this.getDayFontColor(dayInfo))
            .fontWeight(this.isToday(dayInfo.date) || dayInfo.isPeriodStart ? FontWeight.Bold : FontWeight.Normal)
        }
        .width(32).height(32)
        .borderRadius(16)
        .backgroundColor(this.selectedDate === dayInfo.date ? '#1565C0' : Color.Transparent)
        .onClick(() => {
          this.selectedDate = dayInfo.date;
          if (this.onDateSelected) {
            this.onDateSelected(dayInfo.date);
          }
        })

        // 标记图标或标签 — 支持同一天显示多个 emoji
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
        Text(`${dayInfo.day}`).fontSize(14).fontColor('#CCCCCC')
      }
    }
    .width(`${100 / 7}%`)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getCalendarDays(): CalendarDay[] {
    const days: CalendarDay[] = [];
    const firstDay = new Date(this.displayYear, this.displayMonth - 1, 1);
    const startWeekday = firstDay.getDay();
    const daysInMonth = new Date(this.displayYear, this.displayMonth, 0).getDate();
    const daysInPrevMonth = new Date(this.displayYear, this.displayMonth - 1, 0).getDate();

    // 上月补齐
    for (let i = startWeekday - 1; i >= 0; i--) {
      days.push({
        day: daysInPrevMonth - i,
        date: `prev_${daysInPrevMonth - i}`,
        isCurrentMonth: false,
        markColor: '',
        markIcons: [],
        markLabel: '',
        isPeriodStart: false
      });
    }

    // 当月
    for (let d = 1; d <= daysInMonth; d++) {
      const dateStr = this.formatDateStr(this.displayYear, this.displayMonth, d);
      const mark = this.markedDates.find(m => m.date === dateStr);
      days.push({
        day: d,
        date: dateStr,
        isCurrentMonth: true,
        markColor: mark?.color ?? '',
        markIcons: mark?.icons ?? [],
        markLabel: mark?.label ?? '',
        isPeriodStart: mark?.isPeriodStart ?? false
      });
    }

    // 下月补齐
    const remaining = 42 - days.length;
    for (let i = 1; i <= remaining; i++) {
      days.push({
        day: i,
        date: `next_${i}`,
        isCurrentMonth: false,
        markColor: '',
        markIcons: [],
        markLabel: '',
        isPeriodStart: false
      });
    }

    return days;
  }

  private prevMonth(): void {
    if (this.displayMonth === 1) {
      this.displayYear--;
      this.displayMonth = 12;
    } else {
      this.displayMonth--;
    }
    if (this.onMonthChanged) {
      this.onMonthChanged(this.displayYear, this.displayMonth);
    }
  }

  private nextMonth(): void {
    if (this.displayMonth === 12) {
      this.displayYear++;
      this.displayMonth = 1;
    } else {
      this.displayMonth++;
    }
    if (this.onMonthChanged) {
      this.onMonthChanged(this.displayYear, this.displayMonth);
    }
  }

  private isToday(dateStr: string): boolean {
    const now = new Date();
    return dateStr === this.formatDateStr(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  private getDayFontColor(dayInfo: CalendarDay): string {
    // 选中日期用白色
    if (this.selectedDate === dayInfo.date) return '#FFFFFF';
    // 经期第一天用白色（深色背景上）
    if (dayInfo.isPeriodStart) return '#FFFFFF';
    // 经期日期用深粉色
    if (dayInfo.markColor === '#E91E63') return '#880E4F';
    // 今天用蓝色
    if (this.isToday(dayInfo.date)) return '#1565C0';
    return '#333333';
  }

  private formatDateStr(year: number, month: number, day: number): string {
    return `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
  }
}

export interface MarkedDate {
  date: string;
  color: string;
  icons?: string[]; // 日期下方显示的 emoji 图标数组，支持同一天多个事件
  label?: string;   // 日期上显示的文字标签，如 "1" 表示经期第1天
  isPeriodStart?: boolean; // 是否为经期第一天
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
