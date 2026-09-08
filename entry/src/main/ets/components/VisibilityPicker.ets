/**
 * 共享范围选择器组件 — 方向 C 极简编辑
 * flat：底部分隔线；选中项用墨黑下划线 + 粗体，未选灰字
 */
import { Visibility } from '../common/Constants';
import { FamilyMember } from '../model/FamilyMember';
import {
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  DIVIDER, FONT_BODY, FONT_CAPTION
} from '../common/DesignTokens';

@Component
export struct VisibilityPicker {
  @State selectedVisibility: Visibility = Visibility.PRIVATE;
  @State selectedMemberIds: string[] = [];
  @Prop familyMembers: FamilyMember[] = [];
  onVisibilityChange?: (visibility: Visibility, memberIds: string[]) => void;

  build() {
    Column({ space: 8 }) {
      Text('共享范围')
        .fontSize(FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(NEUTRAL_INK_SECONDARY)
        .fontFamily('serif')

      // 三个选项（下划线 tab 式）
      Row({ space: 0 }) {
        this.VisibilityOption('仅自己', Visibility.PRIVATE)
        this.VisibilityOption('部分成员', Visibility.SELECTED)
        this.VisibilityOption('家庭可见', Visibility.FAMILY)
      }
      .width('100%')
      .border({ width: { bottom: 0.5 }, color: DIVIDER })

      // SELECTED 时显示成员选择
      if (this.selectedVisibility === Visibility.SELECTED) {
        this.MemberSelection()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  VisibilityOption(label: string, visibility: Visibility) {
    Column() {
      Text(label)
        .fontSize(FONT_CAPTION)
        .fontColor(this.selectedVisibility === visibility ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
        .fontWeight(this.selectedVisibility === visibility ? FontWeight.Medium : FontWeight.Normal)
        .padding({ left: 12, right: 12, top: 8, bottom: 6 })

      if (this.selectedVisibility === visibility) {
        Row().height(2).backgroundColor(NEUTRAL_INK)
      }
    }
    .layoutWeight(1)
    .onClick(() => {
      this.selectedVisibility = visibility;
      this.notifyChange();
    })
  }

  @Builder
  MemberSelection() {
    Wrap({ space: 8 }) {
      ForEach(this.familyMembers, (member: FamilyMember) => {
        Text(member.name)
          .fontSize(FONT_CAPTION)
          .fontColor(this.selectedMemberIds.includes(member.id) ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
          .fontWeight(this.selectedMemberIds.includes(member.id) ? FontWeight.Medium : FontWeight.Normal)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .border(this.selectedMemberIds.includes(member.id)
            ? { width: { bottom: 1 }, color: NEUTRAL_INK }
            : { width: { bottom: 0 }, color: DIVIDER })
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
    .margin({ top: 12 })
  }

  private notifyChange(): void {
    if (this.onVisibilityChange) {
      this.onVisibilityChange(this.selectedVisibility, this.selectedMemberIds);
    }
  }
}
