/**
 * AuthNavigation 登录路由策略测试
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LOGIN_ROUTE_URL,
  buildExplicitLogoutRouteParams,
  shouldSkipSilentLogin
} from '../../../main/ets/common/AuthNavigation';

export default function authNavigationTest() {
  describe('AuthNavigation 登录路由策略', () => {
    it('退出登录应回到登录页并跳过静默登录', 0, () => {
      const params = buildExplicitLogoutRouteParams();

      expect(LOGIN_ROUTE_URL).assertEqual('pages/LoginPage');
      expect(shouldSkipSilentLogin(params)).assertTrue();
    });

    it('普通启动进入登录页时不应跳过静默登录', 0, () => {
      const params: Record<string, Object> = {};

      expect(shouldSkipSilentLogin(undefined)).assertFalse();
      expect(shouldSkipSilentLogin(params)).assertFalse();
    });
  });
}
