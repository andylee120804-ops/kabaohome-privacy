/**
 * validateInvite 云函数
 *
 * 功能：验证邀请码有效性，返回家庭信息
 *
 * 请求 body 示例：
 * {
 *   "inviteCode": "ABC123",
 *   "acceptIfValid": true   // 可选；若为 true 则验证通过后自动将当前 uid 加入家庭
 * }
 *
 * 响应：
 * {
 *   "code": 0,
 *   "message": "success",
 *   "data": {
 *     "valid": true,
 *     "family": { "id": "fam_xxx", "name": "我的家", "memberCount": 3 },
 *     "inviter": { "id": "u_xxx", "nickname": "爸爸" },
 *     "joined": false
 *   }
 * }
 */
const { wrapHttp, success, fail, CODE } = require('./shared/response');
const { requireAuth } = require('./shared/auth');
const db = require('./shared/db');

const STATUS_PENDING = 'pending';
const STATUS_ACCEPTED = 'accepted';
const STATUS_EXPIRED = 'expired';

async function handler(body, event) {
  const uid = requireAuth(event);

  const inviteCode = body.inviteCode && String(body.inviteCode).trim();
  const acceptIfValid = body.acceptIfValid === true;

  if (!inviteCode) {
    return fail(CODE.PARAM_ERROR, 'inviteCode is required');
  }
  if (inviteCode.length > 32) {
    return fail(CODE.PARAM_ERROR, 'inviteCode too long');
  }

  // 1) 查询邀请记录
  const invites = await db.query('FamilyInvitation', q =>
    q.equalTo('inviteCode', inviteCode));

  if (!invites || invites.length === 0) {
    return fail(CODE.NOT_FOUND, '邀请码不存在或已失效');
  }

  const invite = invites[0];

  // 2) 校验状态
  if (invite.status === STATUS_ACCEPTED) {
    return fail(CODE.CONFLICT, '邀请码已被使用');
  }
  if (invite.status === STATUS_EXPIRED) {
    return fail(CODE.FORBIDDEN, '邀请码已过期');
  }

  // 3) 校验过期时间
  const now = Date.now();
  const expiresAt = parseTime(invite.expiresAt);
  if (expiresAt > 0 && expiresAt < now) {
    // 标记过期
    try {
      invite.status = STATUS_EXPIRED;
      await db.upsertMany('FamilyInvitation', [invite]);
    } catch (e) {
      console.warn('[validateInvite] mark expired failed:', e.message);
    }
    return fail(CODE.FORBIDDEN, '邀请码已过期');
  }

  // 4) 加载家庭信息
  const families = await db.query('Family', q => q.equalTo('id', invite.familyId));
  if (!families || families.length === 0) {
    return fail(CODE.NOT_FOUND, '关联家庭不存在');
  }
  const family = families[0];

  // 5) 加载邀请人
  let inviter = null;
  try {
    const inviters = await db.query('FamilyMember', q =>
      q.equalTo('userId', invite.inviterId).equalTo('familyId', invite.familyId));
    if (inviters && inviters.length > 0) {
      const m = inviters[0];
      inviter = { id: m.userId, nickname: m.nickname || m.name || '' };
    }
  } catch (e) {
    console.warn('[validateInvite] load inviter failed:', e.message);
  }

  // 6) 统计成员数
  let memberCount = 0;
  try {
    const members = await db.query('FamilyMember', q => q.equalTo('familyId', invite.familyId));
    memberCount = (members && members.length) || 0;
  } catch (e) {
    console.warn('[validateInvite] count members failed:', e.message);
  }

  // 7) 自动加入
  let joined = false;
  if (acceptIfValid) {
    try {
      // 检查是否已经是成员
      const existing = await db.query('FamilyMember', q =>
        q.equalTo('userId', uid).equalTo('familyId', invite.familyId));

      if (!existing || existing.length === 0) {
        const newMember = {
          id: `mem_${uid}_${invite.familyId}`,
          familyId: invite.familyId,
          userId: uid,
          role: 'member',
          joinedAt: new Date(now).toISOString(),
          updatedAt: now,
          version: 1
        };
        await db.upsertMany('FamilyMember', [newMember]);
        memberCount += 1;
      }

      // 更新邀请状态为已接受
      invite.status = STATUS_ACCEPTED;
      invite.inviteeId = uid;
      invite.respondedAt = new Date(now).toISOString();
      await db.upsertMany('FamilyInvitation', [invite]);
      joined = true;
    } catch (e) {
      console.error('[validateInvite] accept failed:', e.message);
      return fail(CODE.SERVER_ERROR, '加入家庭失败：' + e.message);
    }
  }

  return success({
    valid: true,
    family: {
      id: family.id,
      name: family.name || '',
      memberCount
    },
    inviter,
    joined
  });
}

/** 兼容数字时间戳/ISO 字符串 */
function parseTime(v) {
  if (!v) return 0;
  if (typeof v === 'number') return v;
  const t = Date.parse(v);
  return isNaN(t) ? 0 : t;
}

exports.handler = wrapHttp(handler);
exports.main = exports.handler;