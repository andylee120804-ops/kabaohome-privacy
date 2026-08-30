/**
 * 动态底部Tab导航组件
 */
import { ModuleId, MAX_CUSTOM_TABS } from '../common/Constants';
import { ModuleManager } from '../viewmodel/ModuleManager';

@Component
export struct TabBar {
  @Prop enabledModules: ModuleId[] = [];
  @Prop currentTab: number = 0;
  @Prop themeColor: string = '#E8654A';
  onTabChange?: (index: number) => void;

  build() {
    Row() {
      // 首页（固定）
      Column() {
        Text('🏠').fontSize(22)
        Text('首页')
          .fontSize(11)
          .fontColor(this.currentTab === 0 ? this.themeColor : '#999999')
          .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 4, bottom: 4 })
      .onClick(() => {
        if (this.onTabChange) this.onTabChange(0);
      })

      // 动态模块Tab
      ForEach(this.enabledModules.slice(0, MAX_CUSTOM_TABS), (moduleId: ModuleId, index: number) => {
        Column() {
          Text(ModuleManager.getModuleDef(moduleId)?.icon ?? '📋').fontSize(22)
          Text(ModuleManager.getModuleDef(moduleId)?.name ?? '')
            .fontSize(11)
            .fontColor(this.currentTab === (index as number + 1) ? this.themeColor : '#999999')
            .fontWeight(this.currentTab === (index as number + 1) ? FontWeight.Bold : FontWeight.Normal)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          if (this.onTabChange) this.onTabChange((index as number) + 1);
        })
      }, (moduleId: ModuleId) => moduleId)

      // 我的（固定）
      Column() {
        Text('⚙️').fontSize(22)
        Text('我的')
          .fontSize(11)
          .fontColor(this.currentTab === this.enabledModules.length + 1 ? this.themeColor : '#999999')
          .fontWeight(this.currentTab === this.enabledModules.length + 1 ? FontWeight.Bold : FontWeight.Normal)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 4, bottom: 4 })
      .onClick(() => {
        if (this.onTabChange) this.onTabChange(this.enabledModules.length + 1);
      })
    }
    .width('100%')
    .padding({ top: 6, bottom: 10 })
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 0.5 }, color: '#F0F0F0' })
  }
}
