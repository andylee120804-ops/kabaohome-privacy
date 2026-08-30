/**
 * pushData 云函数
 *
 * 功能：接收客户端推送的数据变更，写入 Cloud DB
 *
 * 请求 body 示例：
 * {
 *   "familyId": "fam_xxx",
 *   "operations": [
 *     { "type": "AccountingRecord", "op": "upsert", "data": {...}, "version": 3 },
 *     { "type": "Memo", "op": "delete", "data": { "id": "memo_1" }, "version": 1 }
 *   ]
 * }
 *
 * 响应：
 * {
 *   "code": 0,
 *   "message": "success",
 *   "data": { "succeeded": 5, "failed": 0, "conflicts": [] }
 * }
 */
const { wrapHttp, success, fail, CODE } = require('./shared/response');
const { requireAuth } = require('./shared/auth');
const db = require('./shared/db');

/** 受支持的对象类型白名单（防止任意写表） */
const ALLOWED_TYPES = new Set([
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
]);

async function handler(body, event /*, context */) {
  const uid = requireAuth(event);

  const familyId = body.familyId;
  const operations = body.operations;

  if (!familyId || typeof familyId !== 'string') {
    return fail(CODE.PARAM_ERROR, 'familyId is required');
  }
  if (!Array.isArray(operations) || operations.length === 0) {
    return fail(CODE.PARAM_ERROR, 'operations must be a non-empty array');
  }
  if (operations.length > 500) {
    return fail(CODE.PARAM_ERROR, 'too many operations (max 500)');
  }

  // 校验该 uid 是否属于这个 familyId
  const isMember = await checkFamilyMembership(uid, familyId);
  if (!isMember) {
    return fail(CODE.FORBIDDEN, 'user is not a member of this family');
  }

  // 按对象类型分组聚合，减少 DB 调用次数
  const upsertGroups = new Map();   // type -> [records]
  const deleteGroups = new Map();   // type -> [records]
  const conflicts = [];
  let failed = 0;

  for (const op of operations) {
    const type = op && op.type;
    const action = op && op.op;
    const data = op && op.data;

    if (!type || !ALLOWED_TYPES.has(type)) {
      failed++;
      continue;
    }
    if (!data || typeof data !== 'object') {
      failed++;
      continue;
    }

    // 强制写入 familyId，防止跨家庭污染
    data.familyId = familyId;

    if (action === 'upsert') {
      // 版本号冲突检测
      const conflict = await detectConflict(type, data);
      if (conflict) {
        conflicts.push({ type, id: data.id, serverVersion: conflict.version, clientVersion: data.version });
        continue;
      }
      // 写入服务端时间戳
      data.updatedAt = Date.now();
      data.updatedBy = uid;
      if (!upsertGroups.has(type)) upsertGroups.set(type, []);
      upsertGroups.get(type).push(data);
    } else if (action === 'delete') {
      if (!deleteGroups.has(type)) deleteGroups.set(type, []);
      deleteGroups.get(type).push(data);
    } else {
      failed++;
    }
  }

  // 批量执行
  let succeeded = 0;
  for (const [type, records] of upsertGroups) {
    try {
      await db.upsertMany(type, records);
      succeeded += records.length;
    } catch (e) {
      console.error(`[pushData] upsert ${type} failed:`, e.message);
      failed += records.length;
    }
  }
  for (const [type, records] of deleteGroups) {
    try {
      await db.deleteMany(type, records);
      succeeded += records.length;
    } catch (e) {
      console.error(`[pushData] delete ${type} failed:`, e.message);
      failed += records.length;
    }
  }

  return success({ succeeded, failed, conflicts });
}

/**
 * 校验用户是否为指定家庭成员
 */
async function checkFamilyMembership(uid, familyId) {
  try {
    const list = await db.query('FamilyMember', q => q.equalTo('userId', uid).equalTo('familyId', familyId));
    return list && list.length > 0;
  } catch (e) {
    console.error('[pushData] checkFamilyMembership error:', e.message);
    return false;
  }
}

/**
 * 检测版本冲突：服务端版本 > 客户端版本则视为冲突
 */
async function detectConflict(type, data) {
  if (data.version === undefined || data.version === null) return null;
  if (!data.id) return null;
  try {
    const existing = await db.query(type, q => q.equalTo('id', data.id));
    if (!existing || existing.length === 0) return null;
    const server = existing[0];
    if (server.version !== undefined && server.version > data.version) {
      return server;
    }
    return null;
  } catch (e) {
    console.warn('[pushData] detectConflict error:', e.message);
    return null;
  }
}

/** 云函数入口 */
exports.handler = wrapHttp(handler);
exports.main = exports.handler; // 兼容部分平台命名
