/**
 * 华为账号登录实现（基于 @kit.AccountKit）
 *
 * 正式签名包：完整华为账号登录功能
 * Debug 包：因缺少签名权限，API 调用会失败，返回空值（优雅降级）
 *
 * 在 EntryAbility.onCreate 中已注入到 AuthService：
 *   AuthService.getInstance().setHuaweiLoginProvider(
 *     HuaweiAccountProvider.silentLogin,
 *     HuaweiAccountProvider.explicitLogin
 *   );
 */
import { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = '[HuaweiAccountProvider]';

export class HuaweiAccountProvider {
  static async silentLogin(context: common.Context | null): Promise<string> {
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createLoginWithHuaweiIDRequest();
      request.forceLogin = false;
      const controller = new authentication.AuthenticationController(context ?? undefined);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const openID = response.data?.openID ?? '';
      if (openID) {
        hilog.info(0x0000, TAG, 'Silent login success');
      }
      return openID;
    } catch (err) {
      // debug 包或未登录状态：静默失败，返回空值让 LoginPage 显示登录选项
      hilog.warn(0x0000, TAG, 'Silent login failed: %{public}s', (err as Error).message);
      return '';
    }
  }

  static async explicitLogin(context: common.Context | null): Promise<string> {
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createLoginWithHuaweiIDRequest();
      request.forceLogin = true;
      const controller = new authentication.AuthenticationController(context ?? undefined);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const openID = response.data?.openID;
      if (!openID) {
        throw new Error('未获取到 Huawei OpenID');
      }
      hilog.info(0x0000, TAG, 'Explicit login success');
      return openID;
    } catch (err) {
      const msg = (err as Error).message;
      hilog.error(0x0000, TAG, 'Explicit login failed: %{public}s', msg);
      throw new Error(`华为账号登录失败：${msg}`);
    }
  }
}
