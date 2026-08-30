/**
 * 统一响应结构 - 所有云函数返回结构一致
 * 客户端 CloudService 期望格式：{ code, message, data? }
 */

const CODE = {
  OK: 0,
  PARAM_ERROR: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  SERVER_ERROR: 500
};

function success(data, message) {
  return {
    code: CODE.OK,
    message: message || 'success',
    data: data || null
  };
}

function fail(code, message, data) {
  return {
    code: code,
    message: message || 'error',
    data: data || null
  };
}

/**
 * 包装 HTTP 处理器，统一异常处理
 * 华为云函数 HTTP 触发的入口为 (event, context, callback)
 */
function wrapHttp(handler) {
  return async function (event, context, callback) {
    try {
      // event.body 可能是 string，需要解析
      let body = {};
      if (event && event.body) {
        if (typeof event.body === 'string') {
          try {
            body = JSON.parse(event.body);
          } catch (e) {
            return callback(null, {
              statusCode: 400,
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(fail(CODE.PARAM_ERROR, 'Invalid JSON body'))
            });
          }
        } else {
          body = event.body;
        }
      }

      const result = await handler(body, event, context);

      callback(null, {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(result)
      });
    } catch (err) {
      console.error('[wrapHttp] error:', err && err.stack || err);
      callback(null, {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(fail(CODE.SERVER_ERROR, (err && err.message) || 'Internal error'))
      });
    }
  };
}

module.exports = { CODE, success, fail, wrapHttp };
