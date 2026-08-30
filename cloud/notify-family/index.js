/**
 * notifyFamily 云函数
 *
 * 触发器：Cloud DB Trigger - 监听 FamilyMember 表的 INSERT / UPDATE
 *
 * 事件 event 结构（AGC Cloud DB Trigger 规范）：
 * {
 *   "eventType": "INSERT" | "UPDATE" | "DELETE",
 *   "objectType": "FamilyMember",
 *   "zoneName": "kabaoHomeZone",
 *   "before": { ... },   // UPDATE/DELETE 时存在
 *   "after":  { ... }    // INSERT/UPDATE 时存在
 * }
 *
 * 功能：
 * 1) 当某个 FamilyMember 被新增/修改时，向同一家庭的所有其他成员推送通知
 * 2) 通过 AGC Push Kit 发送消息
 * 3) 通过 Cloud DB 写入 FamilyNotification 表（供应用内消息中心展示）
 */
const { wrapHttp, success } = require('./shared/response');
const db = require('./shared/db');

let pushClient = null;
function getPushClient() {
  if (pushClient !== null) return pushClient;
  try {
    const agconnect = require('@hw-agconnect/cloud-server');
    pushClient = agconnect.push ? agconnect.push : null;
  } catch (e) {
    console.warn('[notifyFamily] push SDK not available:', e.message);
    pushClient = null;
  }
  return pushClient;
}

async function dbTriggerHandler(event /*, context */) {
  if (!event || event.objectType !== 'FamilyMember') {
    return { skipped: true, reason: 'not a FamilyMember event' };
  }

  const eventType = event.eventType || '';
  const after = event.after || {};
  const before = event.before || {};

  // 取受影响的 familyId 与变更者
  const familyId = after.familyId || before.familyId;
  const changedUserId = after.userId || before.userId;
  if (!familyId || !changedUserId) {
    return { skipped: true, reason: 'missing familyId or userId' };
  }

  // 构造通知内容
  let title = '家庭成员变更';
  let content = '';
  let action = '';
  if (eventType === 'INSERT') {
    action = 'JOIN';
    content = `${after.nickname || after.name || '新成员'} 加入了家庭`;
  } else if (eventType === 'UPDATE') {
    action = 'UPDATE';
    const oldName = before.nickname || before.name || '';
    const newName = after.nickname || after.name || '';
    if (oldName !== newName) {
      content = `${oldName || '成员'} 修改了昵称为 ${newName}`;
    } else if (before.role !== after.role) {
      content = `${newName} 的角色变更为 ${after.role}`;
    } else {
      content = `${newName} 更新了个人信息`;
    }
  } else if (eventType === 'DELETE') {
    action = 'LEAVE';
    content = `${before.nickname || before.name || '成员'} 离开了家庭`;
  }

  // 取家庭内所有成员（用于群发）
  let members = [];
  try {
    members = await db.query('FamilyMember', q => q.equalTo('familyId', familyId)) || [];
  } catch (e) {
    console.error('[notifyFamily] query members failed:', e.message);
    return { error: e.message };
  }

  // 排除变更对象本人
  const recipients = members
    .map(m => m.userId)
    .filter(uid => uid && uid !== changedUserId);

  if (recipients.length === 0) {
    return { skipped: true, reason: 'no recipients' };
  }

  const now = Date.now();
  const notificationId = `notif_${familyId}_${now}_${Math.random().toString(36).slice(2, 8)}`;

  // 1) 写入应用内消息中心
  const notifyRecords = recipients.map(uid => ({
    id: `${notificationId}_${uid}`,
    familyId,
    recipientId: uid,
    title,
    content,
    action,
    relatedUserId: changedUserId,
    read: false,
    createdAt: now,
    updatedAt: now,
    version: 1
  }));

  try {
    await db.upsertMany('FamilyNotification', notifyRecords);
  } catch (e) {
    console.warn('[notifyFamily] write FamilyNotification failed (table may not exist):', e.message);
  }

  // 2) 通过 Push Kit 推送
  const push = getPushClient();
  if (push) {
    try {
      await push.sendMessage({
        tokens: recipients,   // 实际使用时需要根据 uid 查询 pushToken 表
        notification: { title, body: content },
        data: { action, familyId, relatedUserId: changedUserId }
      });
    } catch (e) {
      console.warn('[notifyFamily] push send failed:', e.message);
    }
  }

  return {
    notified: recipients.length,
    title,
    content,
    action
  };
}

/**
 * Cloud DB 触发器入口
 * 不同于 HTTP，DB 触发器一般直接 return 即可，无需 callback HTTP 包装
 */
exports.handler = async function (event, context) {
  try {
    const result = await dbTriggerHandler(event, context);
    console.log('[notifyFamily] result:', JSON.stringify(result));
    return success(result);
  } catch (err) {
    console.error('[notifyFamily] handler error:', err && err.stack || err);
    return { code: 500, message: (err && err.message) || 'error' };
  }
};

exports.main = exports.handler;