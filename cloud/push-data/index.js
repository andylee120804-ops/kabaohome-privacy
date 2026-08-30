/**
 * pushData 云函数
 *
 * 功能：接收客户端推送的数据变更，写入 Cloud DB
 *
 * 删除语义（2026-08-27 修正，修复删除不同步到其他设备）：
 *   - 内容类记录（有 isDeleted 字段的类型）：delete 改为「墓碑 upsert」（isDeleted=1），
 *     而非 deleteMany 硬删除。硬删除会直接移除行，其他设备 pull 时永远拉不到删除事件，
 *     mergeToLocal 只认 isDeleted=1 才清理本地 → 对方手机陈旧副本永久残留。
 *     墓碑保留原始字段（visibility/visibleMembers/creatorId），pull-data 的可见性过滤
 *     与客户端 mergeToLocal 均按原逻辑处理，删除即可同步到所有可见设备。
 *   - Family / FamilyMember：保持硬删除。这两个表无 isDeleted 字段，且退出/重入家庭的
 *     流程（isLeavingRelation、membership 恢复）依赖硬删除后行不存在的语义。
 *
 * 请求 body 示例：
 * {
 *   "familyId": "fam_xxx",
 *   "operations": [
 *     { "type": "AccountingRecord", "op": "upsert", "data": {...}, "version": 3 },
 *     { "type": "Memo", "op": "delete", "data": { "id": "memo_1", "isDeleted": true, ... }, "version": 1 }
 *   ]
 * }
 *
 * 响应：
 * {
 *   "code": 0,
 *   "message": "success",
 *   "data": { "succeeded": 5, "failed": 0, "conflicts": [], "failedReasons": [] }
 * }
 */
const { wrapHttp, success, fail, CODE } = require('./shared/response');
const { getUid } = require('./shared/auth');
const db = require('./shared/db');
const { notifyNewRecords } = require('./shared/notify');

/**
 * 硬删除白名单：delete 操作直接 deleteMany（行移除），不写墓碑。
 * 仅 Family/FamilyMember —— 这两个表 schema 无 isDeleted 字段（无法墓碑），
 * 且退出家庭/重入流程依赖硬删除后行不存在的语义（isLeavingRelation、membership 恢复）。
 * 其余 ALLOWED_TYPES 内的内容类型一律走墓碑 upsert（isDeleted=1），保证删除跨设备同步。
 */
const HARD_DELETE_TYPES = new Set(['Family', 'FamilyMember']);

/** 受支持的对象类型白名单（防止任意写表） */
const ALLOWED_TYPES = new Set([
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
  'FamilyInvitation'
]);

/**
 * 从 AGC SDK 错误对象提取 HTTP 响应体（含 AGC 错误码/描述），用于诊断 401 根因
 */
function extractErrDetail(err) {
  const resp = err && err.response;
  if (!resp || !resp.data) return null;
  return typeof resp.data === 'string' ? resp.data.slice(0, 300) : JSON.stringify(resp.data).slice(0, 300);
}

async function handler(body, event, context) {
  let uid = getUid(event, context);
  if (!uid && body && body.__uid) {
    uid = body.__uid;
  }

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
  // 例外1：createFamily / joinFamilyByCode / claimMemberByToken 时，Cloud DB 尚无该用户
  //   的成员记录（Family 和 FamilyMember 几乎同时推送，时序不保证），需根据 operations 判断
  //   是否正在建立从属关系，否则首次创建家庭会被 membership 检查死锁，Family 永远写不进去。
  // 例外2：leaveFamily 时用户删除自己的 FamilyMember 记录，可能 Cloud DB 中无此记录
  //   （之前 upsert 因 2003067 等错误失败），membership 检查会误拦。放行 uid 删除自己的
  //   FamilyMember（userId === uid）和以此为 creatorId 的 Family。
  const isMember = await checkFamilyMembership(uid, familyId);
  const isEstablishing = isEstablishingRelation(uid, operations);
  const isLeaving = isLeavingRelation(uid, operations);
  if (!isMember && !isEstablishing && !isLeaving) {
    return fail(CODE.FORBIDDEN, 'user is not a member of this family');
  }

  // 按对象类型分组聚合，减少 DB 调用次数
  const upsertGroups = new Map();   // type -> [records]
  const deleteGroups = new Map();   // type -> [records]
  const conflicts = [];
  const failedReasons = [];  // 每条失败操作的详细原因，便于客户端诊断
  let failed = 0;

  for (const op of operations) {
    const type = op && op.type;
    const action = op && op.op;
    const data = op && op.data;

    if (!type || !ALLOWED_TYPES.has(type)) {
      failed++;
      failedReasons.push({ type: type || null, id: data && data.id, reason: 'type not in allowlist: ' + type });
      continue;
    }
    if (!data || typeof data !== 'object') {
      failed++;
      failedReasons.push({ type, id: null, reason: 'data is not an object' });
      continue;
    }

    // 强制写入 familyId，防止跨家庭污染
    // Family 表无 familyId 字段（以 id 主键作为家庭标识），跳过避免写入未知字段
    if (type !== 'Family') {
      data.familyId = familyId;
    }

    if (action === 'upsert') {
      // FamilyMember 去重：同 familyId+userId 已有活跃记录时，拒绝重复创建
      // （防止客户端重复点击等原因导致同一用户在同一家庭出现多条成员记录）
      if (type === 'FamilyMember' && data.userId && data.familyId) {
        const dup = await checkDuplicateMember(data.familyId, data.userId, data.id);
        if (dup) {
          console.log('[pushData] duplicate FamilyMember skipped: familyId=%s, userId=%s, existingId=%s, incomingId=%s',
            data.familyId, data.userId, dup, data.id);
          succeeded++;
          continue;
        }
      }
      // 版本号冲突检测
      const conflict = await detectConflict(type, data);
      if (conflict) {
        conflicts.push({ type, id: data.id, serverVersion: conflict.version, clientVersion: data.version });
        continue;
      }
      // 写入服务端时间戳；schema 的 updatedAt 为 String 类型，必须用 ISO 字符串而非 Date.now() 数字
      data.updatedAt = new Date().toISOString();
      if (!upsertGroups.has(type)) upsertGroups.set(type, []);
      upsertGroups.get(type).push(data);
    } else if (action === 'delete') {
      if (HARD_DELETE_TYPES.has(type)) {
        // Family/FamilyMember：硬删除（行移除），退出/重入流程依赖此语义
        if (!deleteGroups.has(type)) deleteGroups.set(type, []);
        deleteGroups.get(type).push(data);
      } else {
        // 内容类记录：写墓碑（isDeleted=1）而非硬删除，使删除能通过 pull-data
        // 同步到其他设备（客户端 mergeToLocal 见 isDeleted=1 即清理本地陈旧副本）。
        // 客户端 delete 已携带完整记录（含 visibility/visibleMembers/creatorId），
        // 墓碑保留这些字段，pull-data 的可见性过滤照常生效。
        // 强制 isDeleted=1 与 updatedAt（不信任客户端），绕过 detectConflict：
        // 删除应当总是生效（与历史硬删除语义一致，防止陈旧删除被并发编辑拒绝）。
        data.isDeleted = 1;
        data.updatedAt = new Date().toISOString();
        if (!upsertGroups.has(type)) upsertGroups.set(type, []);
        upsertGroups.get(type).push(data);
      }
    } else {
      failed++;
      failedReasons.push({ type, id: data.id, reason: 'unknown action: ' + action });
    }
  }

  // 批量执行
  let succeeded = 0;
  for (const [type, records] of upsertGroups) {
    // 诊断：打印第一条记录的完整内容，确认主键字段是否存在
    if (records.length > 0) {
      console.log('[pushData] upsert %s, count=%d, firstRecord=%s', type, records.length, JSON.stringify(records[0]).slice(0, 500));
    }
    try {
      await db.upsertMany(type, records);
      succeeded += records.length;
    } catch (e) {
      const detail = extractErrDetail(e);
      console.error(`[pushData] upsert ${type} failed:`, e.message, detail ? '| resp:' + detail : '');
      console.error('[pushData] failed record sample:', JSON.stringify(records[0]).slice(0, 500));
      failed += records.length;
      for (const r of records) {
        failedReasons.push({ type, id: r && r.id, reason: 'upsert failed: ' + e.message + (detail ? ' | resp: ' + detail : '') });
      }
    }
  }
  for (const [type, records] of deleteGroups) {
    try {
      await db.deleteMany(type, records);
      succeeded += records.length;
    } catch (e) {
      const detail = extractErrDetail(e);
      console.error(`[pushData] delete ${type} failed:`, e.message, detail ? '| resp:' + detail : '');
      failed += records.length;
      for (const r of records) {
        failedReasons.push({ type, id: r && r.id, reason: 'delete failed: ' + e.message + (detail ? ' | resp: ' + detail : '') });
      }
    }
  }

  // 通知分发（fire-and-forget，不阻塞主流程）
  if (succeeded > 0) {
    notifyNewRecords(uid, familyId, operations).catch(e => {
      console.warn('[pushData] notify error:', e.message);
    });
  }

  return success({ succeeded, failed, conflicts, failedReasons });
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
 * 检查同 familyId+userId 是否已存在不同的 FamilyMember 记录
 * 返回已存在记录的 id（如有），null 表示无重复
 */
async function checkDuplicateMember(familyId, userId, incomingId) {
  try {
    const list = await db.query('FamilyMember', q =>
      q.equalTo('familyId', familyId).equalTo('userId', userId));
    if (!list || list.length === 0) return null;
    for (const raw of list) {
      const m = (typeof raw.getObject === 'function') ? raw.getObject() : raw;
      if (m.id && m.id !== incomingId) {
        return m.id;
      }
    }
    return null;
  } catch (e) {
    console.warn('[pushData] checkDuplicateMember error:', e.message);
    return null;
  }
}

/**
 * 判断本次 operations 是否正在建立 uid 与家庭的从属关系（用于放行首次创建/加入）
 *
 * 命中条件：
 *   - Family upsert 且 data.creatorId === uid：创建家庭（createFamily）
 *   - FamilyMember upsert 且 data.userId === uid：自己加入家庭
 *     （createFamily 的首个成员 / joinFamilyByCode / claimMemberByToken）
 *
 * 安全权衡：允许 uid 自行 upsert userId=自己的 FamilyMember 可绕过邀请码校验。
 * V1 阶段为打通跨设备加入接受此风险；V2 应在服务端对 join 场景二次校验邀请码。
 */
function isEstablishingRelation(uid, operations) {
  if (!uid || !Array.isArray(operations)) return false;
  for (const op of operations) {
    if (!op || !op.data) continue;
    if (op.type === 'Family' && op.op === 'upsert' && op.data.creatorId === uid) {
      return true;
    }
    if (op.type === 'FamilyMember' && op.op === 'upsert' && op.data.userId === uid) {
      return true;
    }
  }
  return false;
}

/**
 * 判断本次 operations 是否正在断开 uid 与家庭的从属关系（用于放行 leaveFamily）
 *
 * 命中条件：
 *   - FamilyMember delete 且 data.userId === uid：用户删除自己的成员记录
 *   - Family delete 且 data.creatorId === uid：创建者解散家庭
 *
 * 安全权衡：允许 uid 删除 userId=自己的 FamilyMember 是安全的（只能删自己的记录）。
 * 删除 Family 需 creatorId===uid，非创建者无法删除他人家庭。
 */
function isLeavingRelation(uid, operations) {
  if (!uid || !Array.isArray(operations)) return false;
  for (const op of operations) {
    if (!op || !op.data) continue;
    if (op.type === 'FamilyMember' && op.op === 'delete' && op.data.userId === uid) {
      return true;
    }
    if (op.type === 'Family' && op.op === 'delete' && op.data.creatorId === uid) {
      return true;
    }
  }
  return false;
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
