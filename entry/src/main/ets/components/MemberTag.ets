/**
 * 成员标签组件 - 显示家庭成员名称和颜色标识
 */
import { FamilyMember } from '../model/FamilyMember';

@Component
export struct MemberTag {
  @Prop member: FamilyMember = new FamilyMember();
  @Prop isSelected: boolean = false;
  @Prop size: string = 'normal'; // 'normal' | 'small' | 'large'
  onSelected?: () => void;

  build() {
    Text(`${this.member.avatar} ${this.member.name}`)
      .fontSize(this.getFontSize())
      .fontColor(this.isSelected ? Color.White : '#333333')
      .backgroundColor(this.isSelected ? this.member.color : '#F5F5F5')
      .borderRadius(20)
      .padding(this.getPadding())
      .onClick(() => {
        if (this.onSelected) {
          this.onSelected();
        }
      })
  }

  private getFontSize(): number {
    if (this.size === 'small') return 11;
    if (this.size === 'large') return 16;
    return 13;
  }

  private getPadding(): Padding {
    if (this.size === 'small') return { left: 8, right: 8, top: 3, bottom: 3 };
    if (this.size === 'large') return { left: 18, right: 18, top: 8, bottom: 8 };
    return { left: 14, right: 14, top: 6, bottom: 6 };
  }
}
