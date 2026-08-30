/**
 * mergeConflict 云函数
 *
 * 功能：服务端冲突合并 —— "版本号优先 + last-write-wins"
 *
 * 策略：
 *  1) 客户端发现 push 失败（pushData 返回 conflicts）后，主动调用此函数提交冲突合并请求
 *  2) 服务端对每条冲突：
 *      - 取出服务端最新记录
 *      - 按字段级合并：客户端 updatedAt 较新的字段获胜 (last-write-wins)
 *      - 版本号 = max(server.version, client.version) + 1
 *  3) 返回最终合并后的记录，由客户端覆盖本地
 *
 * 请求 body 示例：
 * {
 *   "familyId": "fam_xxx",
 *   "conflicts": [
 *     {
 *       "type": "AccountingRecord",
 *       "client": { "id": "rec_1", "amount": 30, "version": 2, "updatedAt": 1717100000000, "_fieldUpdatedAt": {...} }
 *     }
 *   ]
 * }
 *
 * 响应：
 * {
 *   "code": 0,
 *   "data": {
 *     "merged": [ { "type": "...", "data": {...} } ],
 *     "failed": [ { "type": "...", "id": "...", "reason": "..." } ]
 *   }
 * }
 */
const { wrapHttp, success, fail, CODE } = require('./shared/response');
const { requireAuth } = require('./shared/auth');
const db = require('./shared/db');

const ALLOWED_TYPES = new Set([
  'AccountingRecord', 'Memo', 'Reminder', 'KidEvent',
  'HealthMetric', 'PeriodRecord', 'Medication',
  'ShoppingItem', 'LocationPlace', 'Photo',
  'Family', 'FamilyMember'
]);

/** 系统级保留字段，绝不可被客户端覆盖 */
const RESERVED_FIELDS = new Set(['id', 'familyId', 'createdAt', 'createdBy']);

async function handler(body, event) {
  const uid = requireAuth(event);

  const familyId = body.familyId;
  const conflicts = body.conflicts;

  if (!familyId) return fail(CODE.PARAM_ERROR, 'familyId is required');
  if (!Array.isArray(conflicts) || conflicts.length === 0) {
    return fail(CODE.PARAM_ERROR, 'conflicts must be a non-empty array');
  }
  if (conflicts.length > 200) {
    return fail(CODE.PARAM_ERROR, 'too many conflicts (max 200)');
  }

  // 权限校验
  const isMember = await checkMembership(uid, familyId);
  if (!isMember) {
    return fail(CODE.FORBIDDEN, 'not a member of this family');
  }

  const merged = [];
  const failed = [];

  // 按类型分组以批量写入
  const upsertByType = new Map();

  for (const item of conflicts) {
    const type = item && item.type;
    const client = item && item.client;

    if (!type || !ALLOWED_TYPES.has(type) || !client || !client.id) {
      failed.push({ type, id: client && client.id, reason: 'invalid payload' });
      continue;
    }
    if (client.familyId && client.familyId !== familyId) {
      failed.push({ type, id: client.id, reason: 'familyId mismatch' });
      continue;
    }

    try {
      const existing = await db.query(type, q => q.equalTo('id', client.id));
      const server = existing && existing.length > 0 ? existing[0] : null;

      const mergedRecord = mergeRecord(server, client, uid, familyId);
      merged.push({ type, data: mergedRecord });

      if (!upsertByType.has(type)) upsertByType.set(type, []);
      upsertByType.get(type).push(mergedRecord);
    } catch (e) {
      console.error(`[mergeConflict] merge ${type}/${client.id} failed:`, e.message);
      failed.push({ type, id: client.id, reason: e.message });
    }
  }

  // 批量写回
  for (const [type, records] of upsertByType) {
    try {
      await db.upsertMany(type, records);
    } catch (e) {
      console.error(`[mergeConflict] persist ${type} failed:`, e.message);
      // 把这批标记为失败
      for (const r of records) {
        failed.push({ type, id: r.id, reason: 'persist failed: ' + e.message });
      }
    }
  }

  return success({ merged, failed });
}

/**
 * 字段级合并算法
 *
 * - 如果服务端无此记录：直接采用客户端版本
 * - 如果客户端 version > 服务端：覆盖式 last-write-wins
 * - 否则字段级合并：对每个字段，比较 _fieldUpdatedAt[field]（若有）或 updatedAt，
 *   取时间戳较新者
 */
function mergeRecord(server, client, uid, familyId) {
  if (!server) {
    // 服务端无记录，直接接受客户端
    const result = sanitize(client, familyId);
    result.version = client.version || 1;
    result.updatedAt = client.updatedAt || Date.now();
    result.updatedBy = uid;
    return result;
  }

  const clientVer = client.version || 0;
  const serverVer = server.version || 0;

  // 客户端版本明显更新，整体覆盖
  if (clientVer > serverVer + 1) {
    const result = sanitize(Object.assign({}, server, client), familyId);
    result.id = server.id;
    result.version = clientVer + 1;
    result.updatedAt = Date.now();
    result.updatedBy = uid;
    return result;
  }

  // 字段级合并
  const result = Object.assign({}, server);
  const clientFieldTimes = client._fieldUpdatedAt || {};
  const serverFieldTimes = server._fieldUpdatedAt || {};
  const clientTs = client.updatedAt || 0;
  const serverTs = server.updatedAt || 0;

  for (const key of Object.keys(client)) {
    if (key.startsWith('_')) continue;
    if (RESERVED_FIELDS.has(key)) continue;
    if (key === 'version' || key === 'updatedAt' || key === 'updatedBy') continue;

    const cTs = clientFieldTimes[key] || clientTs;
    const sTs = serverFieldTimes[key] || serverTs;

    if (cTs >= sTs) {
      result[key] = client[key];
    }
    // 否则保留 server[key]
  }

  result.familyId = familyId;
  result.version = Math.max(clientVer, serverVer) + 1;
  result.updatedAt = Date.now();
  result.updatedBy = uid;
  return result;
}

/** 移除保留字段中的非法覆盖（除 id 外） */
function sanitize(obj, familyId) {
  const out = Object.assign({}, obj);
  delete out._fieldUpdatedAt;
  if (familyId) out.familyId = familyId;
  return out;
}

async function checkMembership(uid, familyId) {
  try {
    const list = await db.query('FamilyMember', q =>
      q.equalTo('userId', uid).equalTo('familyId', familyId));
    return list && list.length > 0;
  } catch (e) {
    console.error('[mergeConflict] checkMembership error:', e.message);
    return false;
  }
}

exports.handler = wrapHttp(handler);
exports.main = exports.handler;