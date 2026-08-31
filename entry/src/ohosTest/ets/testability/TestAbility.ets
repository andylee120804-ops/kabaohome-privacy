/**
 * 测试入口 Ability
 */
import Ability from '@ohos.app.ability.UIAbility';
import { window } from '@kit.ArkUI';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

export default class TestAbility extends Ability {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    console.log('[TestAbility] onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    windowStage.loadContent('testability/pages/Index', (err, data) => {
      if (err.code) {
        console.error('[TestAbility] Failed to load content: ' + JSON.stringify(err));
        return;
      }
      console.info('[TestAbility] Succeeded in loading content');
      const abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
      const abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
      Hypium.hypiumTest(abilityDelegator, abilityDelegatorArguments, testsuite);
    });
  }
}
