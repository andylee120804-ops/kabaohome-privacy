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
 *
 * 返回格式：openID|idToken （用 | 分隔，便于现有 string 返回类型兼容）
 * - 无 idToken 时只返回 openID
 */
import authentication from "@hms.core.authentication";
import hilog from "@ohos.hilog";
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = '[HuaweiAccountProvider]';
const SEP = '|';

/** 从 HuaweiIDResponseData 中提取 openID 和 idToken，组合成 "openID|idToken" */
function packCredential(openID: string, idToken?: string): string {
  if (!openID) {
    return '';
  }
  return idToken ? `${openID}${SEP}${idToken}` : openID;
}

/** 从 packed 字符串中解析 openID */
export function unpackOpenID(packed: string): string {
  if (!packed) {
    return '';
  }
  const idx = packed.indexOf(SEP);
  return idx >= 0 ? packed.substring(0, idx) : packed;
}

/** 从 packed 字符串中解析 idToken */
export function unpackIdToken(packed: string): string {
  if (!packed) {
    return '';
  }
  const idx = packed.indexOf(SEP);
  return idx >= 0 ? packed.substring(idx + 1) : '';
}

export class HuaweiAccountProvider {
  /** 静默登录：已授权设备直接换 openID；失败返回空串（由 LoginPage 走显式登录） */
  static async silentLogin(context: common.Context | null): Promise<string> {
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createLoginWithHuaweiIDRequest();
      request.forceLogin = false;
      const controller = new authentication.AuthenticationController(context ?? undefined);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const credential = response.data;
      const openID: string = credential?.openID ?? '';
      const idToken: string | undefined = credential
        ? (JSON.parse(JSON.stringify(credential)) as Record<string, string | undefined>)['idToken']
        : undefined;
      if (openID) {
        hilog.info(0x0000, TAG, 'Silent login success, hasIdToken=%{public}s', idToken ? 'true' : 'false');
      }
      return packCredential(openID, idToken);
    } catch (err) {
      // debug 包或未登录状态：静默失败，返回空值让 LoginPage 显示登录选项
      hilog.warn(0x0000, TAG, 'Silent login failed: %{public}s', (err as BusinessError).message);
      return '';
    }
  }

  /** 显式登录：拉起华为账号授权页；失败抛错由调用方展示 */
  static async explicitLogin(context: common.Context | null): Promise<string> {
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createLoginWithHuaweiIDRequest();
      request.forceLogin = true;
      const controller = new authentication.AuthenticationController(context ?? undefined);
      const response = await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      const credential = response.data;
      const openID: string | undefined = credential?.openID;
      if (!openID) {
        throw new Error('未获取到 Huawei OpenID');
      }
      const idToken: string | undefined = credential
        ? (JSON.parse(JSON.stringify(credential)) as Record<string, string | undefined>)['idToken']
        : undefined;
      hilog.info(0x0000, TAG, 'Explicit login success, hasIdToken=%{public}s', idToken ? 'true' : 'false');
      return packCredential(openID, idToken);
    } catch (err) {
      const msg = (err as Error).message;
      hilog.error(0x0000, TAG, 'Explicit login failed: %{public}s', msg);
      throw new Error(`华为账号登录失败：${msg}`);
    }
  }
}
