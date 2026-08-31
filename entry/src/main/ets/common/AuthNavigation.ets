/**
 * 登录/登出路由策略
 */
export const LOGIN_ROUTE_URL = 'pages/LoginPage';
export const FAMILY_SETUP_ROUTE_URL = 'pages/FamilySetupPage';
export const INDEX_ROUTE_URL = 'pages/Index';

const EXPLICIT_LOGOUT_PARAM = 'explicitLogout';

export interface ExplicitLogoutRouteParams {
  explicitLogout: boolean;
}

export function buildExplicitLogoutRouteParams(): ExplicitLogoutRouteParams {
  return { explicitLogout: true };
}

export function shouldSkipSilentLogin(params: object | undefined): boolean {
  if (!params) return false;
  const val = (params as Record<string, Object>)[EXPLICIT_LOGOUT_PARAM];
  // 兼容 router 序列化可能把 boolean 转成 string 的情况
  return val === true || val === 'true';
}
