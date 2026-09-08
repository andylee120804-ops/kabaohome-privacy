/**
 * 成员标签组件 — 方向 C 极简编辑
 * 下划线式 tab：选中 = 墨黑字 + 底 2px 线；未选 = 二级灰字
 * 替代旧的胶囊/pill 样式
 */
import { FamilyMember } from '../model/FamilyMember';
import { NEUTRAL_INK, NEUTRAL_INK_SECONDARY, DIVIDER, FONT_BODY, FONT_CAPTION, FONT_CAPTION_SM } from '../common/DesignTokens';

@Component
export struct MemberTag {
  @Prop member: FamilyMember = new FamilyMember();
  @Prop isSelected: boolean = false;
  @Prop size: string = 'normal'; // 'normal' | 'small' | 'large'
  onSelected?: () => void;

  build() {
    Column() {
      Row({ space: 6 }) {
        // 小圆点（成员色）
        Circle()
          .width(this.size === 'small' ? 4 : 6)
          .height(this.size === 'small' ? 4 : 6)
          .fill(this.member.color || NEUTRAL_INK_SECONDARY)
        Text(this.member.name)
          .fontSize(this.getFontSize())
          .fontColor(this.isSelected ? NEUTRAL_INK : NEUTRAL_INK_SECONDARY)
          .fontWeight(this.isSelected ? FontWeight.Medium : FontWeight.Normal)
      }
      .padding({ bottom: 6 })

      // 选中下划线
      if (this.isSelected) {
        Row()
          .width('100%')
          .height(2)
          .backgroundColor(NEUTRAL_INK)
      }
    }
    .onClick(() => {
      if (this.onSelected) {
        this.onSelected();
      }
    })
  }

  private getFontSize(): number {
    if (this.size === 'small') return FONT_CAPTION_SM;
    if (this.size === 'large') return FONT_BODY;
    return FONT_CAPTION;
  }
}
