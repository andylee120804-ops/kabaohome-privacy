/**
 * pullData 云函数
 *
 * 功能：根据 familyId 和时间戳返回增量数据
 *
 * 请求 body 示例：
 * {
 *   "familyId": "fam_xxx",
 *   "sinceTimestamp": 1717000000000,   // 可选，增量拉取
 *   "objectTypes": ["AccountingRecord", "Memo"]  // 可选，只拉指定类型
 * }
 *
 * 响应：
 * {
 *   "code": 0,
 *   "message": "success",
 *   "data": {
 *     "serverTime": 1717123456789,
 *     "snapshots": {
 *       "AccountingRecord": [ ... ],
 *       "Memo": [ ... ]
 *     }
 *   }
 * }
 */
const { wrapHttp, success, fail, CODE } = require('./shared/response');
const { requireAuth } = require('./shared/auth');
const db = require('./shared/db');

/** 所有可同步的表 */
const ALL_TYPES = [
  'AccountingRecord',
  'Memo',
  'Reminder',
  'KidEvent',
  'HealthMetric',
  'PeriodRecord',
  'Medication',
  'ShoppingItem',
  'LocationPlace',
  'Photo',
  'Family',
  'FamilyMember',
  'FamilyInvitation'
];

async function handler(body, event) {
  const uid = requireAuth(event);

  const familyId = body.familyId;
  const since = body.sinceTimestamp || 0;
  let types = body.objectTypes;

  if (!familyId || typeof familyId !== 'string') {
    return fail(CODE.PARAM_ERROR, 'familyId is required');
  }

  // 限制查询类型白名单
  if (Array.isArray(types) && types.length > 0) {
    types = types.filter(t => ALL_TYPES.includes(t));
    if (types.length === 0) {
      return fail(CODE.PARAM_ERROR, 'invalid objectTypes');
    }
  } else {
    types = ALL_TYPES;
  }

  // 权限校验：必须为家庭成员
  const isMember = await checkFamilyMembership(uid, familyId);
  if (!isMember) {
    return fail(CODE.FORBIDDEN, 'user is not a member of this family');
  }

  // 并发查询所有类型
  const snapshots = {};
  const queries = types.map(async (type) => {
    try {
      // 服务端 SDK 中的 CloudDBQuery 用法
      const list = await db.query(type, q => {
        let query = q.equalTo('familyId', familyId);
        if (since > 0) {
          // 部分 SDK 用 greaterThan
          query = query.greaterThan('updatedAt', since);
        }
        return query;
      });
      return { type, data: list || [] };
    } catch (e) {
      console.warn(`[pullData] query ${type} failed:`, e.message);
      // 即使某个表查询失败，不应影响其他表的拉取
      return { type, data: [] };
    }
  });

  const results = await Promise.all(queries);
  for (const { type, data } of results) {
    snapshots[type] = data;
  }

  return success({
    serverTime: Date.now(),
    snapshots
  });
}

/**
 * 校验用户是否为家庭成员
 */
async function checkFamilyMembership(uid, familyId) {
  try {
    const list = await db.query('FamilyMember', q =>
      q.equalTo('userId', uid).equalTo('familyId', familyId));
    return list && list.length > 0;
  } catch (e) {
    console.error('[pullData] checkFamilyMembership error:', e.message);
    return false;
  }
}

exports.handler = wrapHttp(handler);
exports.main = exports.handler;