/**
 * 共享范围选择器组件
 */
import { Visibility } from '../common/Constants';
import { FamilyMember } from '../model/FamilyMember';

@Component
export struct VisibilityPicker {
  @State selectedVisibility: Visibility = Visibility.PRIVATE;
  @State selectedMemberIds: string[] = [];
  @Prop familyMembers: FamilyMember[] = [];
  onVisibilityChange?: (visibility: Visibility, memberIds: string[]) => void;

  build() {
    Column({ space: 8 }) {
      Text('共享范围').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#333333')

      // 三个选项
      Row({ space: 8 }) {
        this.VisibilityOption('👁 仅自己', Visibility.PRIVATE)
        this.VisibilityOption('👨‍👩 部分成员', Visibility.SELECTED)
        this.VisibilityOption('👨‍👩‍👧‍👦 家庭可见', Visibility.FAMILY)
      }
      .width('100%')

      // SELECTED时显示成员选择
      if (this.selectedVisibility === Visibility.SELECTED) {
        this.MemberSelection()
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor('#F8F8F8')
  }

  @Builder
  VisibilityOption(label: string, visibility: Visibility) {
    Text(label)
      .fontSize(12)
      .fontColor(this.selectedVisibility === visibility ? Color.White : '#666666')
      .backgroundColor(this.selectedVisibility === visibility ? '#1565C0' : Color.White)
      .borderRadius(16)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .onClick(() => {
        this.selectedVisibility = visibility;
        this.notifyChange();
      })
  }

  @Builder
  MemberSelection() {
    Wrap({ space: 6 }) {
      ForEach(this.familyMembers, (member: FamilyMember) => {
        Text(`${member.avatar} ${member.name}`)
          .fontSize(11)
          .fontColor(this.selectedMemberIds.includes(member.id) ? Color.White : '#666666')
          .backgroundColor(this.selectedMemberIds.includes(member.id) ? member.color : '#FFFFFF')
          .borderRadius(12)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            if (this.selectedMemberIds.includes(member.id)) {
              this.selectedMemberIds = this.selectedMemberIds.filter(id => id !== member.id);
            } else {
              this.selectedMemberIds = [...this.selectedMemberIds, member.id];
            }
            this.notifyChange();
          })
      }, (member: FamilyMember) => member.id)
    }
    .width('100%')
    .margin({ top: 8 })
  }

  private notifyChange(): void {
    if (this.onVisibilityChange) {
      this.onVisibilityChange(this.selectedVisibility, this.selectedMemberIds);
    }
  }
}
