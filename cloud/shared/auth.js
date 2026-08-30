/**
 * 鉴权辅助
 *
 * 华为云函数 HTTP 触发器在请求经 AGC Auth 校验后，
 * 会将用户身份注入 event.context 或 event.headers 中：
 *   event.context.auth.uid  或  event.headers['x-agc-user-id']
 *
 * 此处提供统一获取方法。
 */

function getUid(event) {
  if (!event) return null;

  // 方式1：AGC 标准注入
  if (event.context && event.context.auth && event.context.auth.uid) {
    return event.context.auth.uid;
  }

  // 方式2：从 headers 提取
  if (event.headers) {
    const uid = event.headers['x-agc-user-id']
      || event.headers['X-AGC-User-Id']
      || event.headers['x-uid'];
    if (uid) return uid;
  }

  // 方式3：body 中携带（仅作兜底，不推荐生产环境信任）
  if (event.body) {
    const body = typeof event.body === 'string' ? safeParse(event.body) : event.body;
    if (body && body.__uid) return body.__uid;
  }

  return null;
}

function safeParse(s) {
  try { return JSON.parse(s); } catch (e) { return null; }
}

function requireAuth(event) {
  const uid = getUid(event);
  if (!uid) {
    const err = new Error('Unauthorized: missing user identity');
    err.code = 401;
    throw err;
  }
  return uid;
}

module.exports = { getUid, requireAuth };
