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
const { getUid } = require('./shared/auth');
const db = require('./shared/db');

/** 所有可同步的表 */
const ALL_TYPES = [
  'AccountingRecord',
  'Budget',
  'Memo',
  'Reminder',
  'KidEvent',
  'GrowthRecord',
  'HealthMetric',
  'PeriodRecord',
  'IntimacyRecord',
  'Medication',
  'MedicationLog',
  'ShoppingItem',
  'LocationPlace',
  'Photo',
  'PhotoComment',
  'Family',
  'FamilyMember',
  'FamilyInvitation',
  'FamilyNotification'
];

/** 有可见性字段（visibility/visibleMembers/creatorId）的记录表，拉取时按 uid 过滤 */
const VISIBILITY_TYPES = new Set([
  'PeriodRecord',
  'IntimacyRecord',
  'Medication',
  'MedicationLog',
  'HealthMetric',
  'KidEvent',
  'GrowthRecord',
  'Reminder',
  'ShoppingItem',
  'Photo',
  'PhotoComment',
  'Memo',
  'AccountingRecord',
  'LocationPlace'
]);

async function handler(body, event, context) {
  let uid = getUid(event, context);
  if (!uid && body && body.__uid) {
    uid = body.__uid;
  }

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

  // 权限校验：必须为家庭成员（顺便取全量成员，用于 memberId->userId 映射）
  const members = await queryFamilyMembers(familyId);
  const isMember = members.some(m => m.userId === uid);
  if (!isMember) {
    return fail(CODE.FORBIDDEN, 'user is not a member of this family');
  }

  // creatorId 可能存 memberId（新格式）或 openID（旧格式），建映射统一解析为 userId
  const memberIdToUid = {};
  for (const m of members) {
    if (m.id && m.userId) {
      memberIdToUid[m.id] = m.userId;
    }
  }

  // 并发查询所有类型
  const snapshots = {};
  const queries = types.map(async (type) => {
    try {
      // 服务端 SDK 中的 CloudDBQuery 用法
      const list = await db.query(type, q => {
        // Family 表无 familyId 字段，按主键 id 查询；其余表按 familyId
        let query = type === 'Family'
          ? q.equalTo('id', familyId)
          : q.equalTo('familyId', familyId);
        if (since > 0) {
          // 部分 SDK 用 greaterThan
          query = query.greaterThan('updatedAt', since);
        }
        return query;
      });
      // CloudDBZoneGenericObject 的字段存在内部 fieldMap，不能直接序列化！
      // 必须用 getObject() 转为普通对象，否则客户端收到空字段。
      const data = (list || []).map(r =>
        (typeof r.getObject === 'function') ? r.getObject() : r
      );
      // 服务端可见性过滤：PRIVATE/SELECTED 记录不下发给无权成员，
      // 避免私密数据落到其他成员设备本地存储（客户端 filterByVisibility 只管显示）
      if (VISIBILITY_TYPES.has(type)) {
        const before = data.length;
        const filtered = data.filter(r => isRecordVisibleTo(r, uid, memberIdToUid));
        if (filtered.length < before) {
          console.log(`[pullData] visibility filter ${type}: ${before} -> ${filtered.length}`);
        }
        return { type, data: filtered };
      }
      // FamilyNotification 只返回当前用户的消息
      if (type === 'FamilyNotification') {
        const before = data.length;
        const filtered = data.filter(r => r.recipientId === uid);
        if (filtered.length < before) {
          console.log(`[pullData] recipient filter FamilyNotification: ${before} -> ${filtered.length}`);
        }
        return { type, data: filtered };
      }
      return { type, data };
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
 * 校验用户是否为家庭成员（保留旧接口，membership 校验已改为一次性取全量成员）
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

/** 查询家庭全量成员并转为普通对象 */
async function queryFamilyMembers(familyId) {
  try {
    const list = await db.query('FamilyMember', q => q.equalTo('familyId', familyId));
    return (list || []).map(r => (typeof r.getObject === 'function') ? r.getObject() : r);
  } catch (e) {
    console.error('[pullData] queryFamilyMembers error:', e.message);
    return [];
  }
}

/**
 * 服务端可见性过滤（语义与客户端 filterByVisibility 完全一致）
 * - FAMILY：全员可见
 * - PRIVATE：仅创建者
 * - SELECTED：创建者 + visibleMembers（存 userId）里的成员
 * - 未设置：仅创建者（fail-closed）
 */
function isRecordVisibleTo(record, uid, memberIdToUid) {
  const vis = record.visibility;
  const creatorUid = (record.creatorId && memberIdToUid[record.creatorId]) || record.creatorId;
  const isCreator = creatorUid === uid;
  if (vis === 'FAMILY') return true;
  if (vis === 'PRIVATE') return isCreator;
  if (vis === 'SELECTED') {
    return isCreator || parseVisibleMembers(record.visibleMembers).includes(uid);
  }
  return isCreator;
}

/** visibleMembers 在 Cloud DB 存为 Text(JSON 数组字符串) */
function parseVisibleMembers(v) {
  if (Array.isArray(v)) return v;
  if (typeof v === 'string' && v) {
    try {
      const arr = JSON.parse(v);
      return Array.isArray(arr) ? arr : [];
    } catch (e) {
      return [];
    }
  }
  return [];
}

exports.handler = wrapHttp(handler);
exports.main = exports.handler;