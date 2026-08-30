/**
 * Cloud DB 服务端访问辅助层
 *
 * 使用 @hw-agconnect/cloud-server SDK 以服务端管理员权限读写 Cloud DB。
 * 注意：AGC 云函数运行时不会自动安装依赖，此模块必须打包 node_modules/。
 *
 * 初始化策略（双保险，因为 AGC 运行时可能不注入 AGC_CONFIG 环境变量）：
 *   1. 优先从打包的 agc-credential.json 创建 cloud 实例（不依赖环境变量）
 *   2. 兜底用默认 cloud 单例（依赖运行时注入 AGC_CONFIG）
 *
 * agc-credential.json 含明文 client_secret，已加入 .gitignore，切勿提交 git。
 *
 * 正确 API 用法（基于 SDK v1.0.5）：
 *   const { cloud } = require('@hw-agconnect/cloud-server');
 *   const db = cloud.database({ zoneName: 'kabaoHomeZone' });
 *   const results = await db.collection('ObjectType').query().equalTo('field', value).get();
 *   await db.collection('ObjectType').upsert(records);
 */
const { cloud, CloudDBZoneGenericObject } = require('@hw-agconnect/cloud-server');
const fs = require('fs');
const path = require('path');

const ZONE_NAME = 'kabaoHomeZone';
const CRED_FILE = path.join(__dirname, 'agc-credential.json');

/**
 * Cloud DB schema 字段白名单
 *
 * 必须与 AGC 控制台的 Cloud DB schema 完全一致。
 * CloudDBZoneGenericObject.addFieldValue() 不校验字段名是否存在于 schema —— 它只是
 * fieldMap.set(name, value)，任何字段名都会被静默接受。如果客户端模型含有 schema
 * 未定义的字段（如 FamilyMember.isDeleted），该字段会被发送到服务端，服务端返回
 * 2003067: internal error（SDK 无此错误码映射，回退为 "internal error"）。
 *
 * 此白名单在 addFieldValue 前过滤掉 schema 未定义的字段，防止 upsert 被服务端拒绝。
 */
var SCHEMA_PRIMARY_KEYS = { id: true }; // all object types use id as primary key

const SCHEMA_FIELDS = {
  Family: ['id', 'name', 'creatorId', 'inviteCode', 'inviteCodeExpiresAt', 'createdAt', 'updatedAt', 'syncStatus'],
  FamilyMember: ['id', 'familyId', 'userId', 'name', 'avatar', 'color', 'role', 'birthDate', 'phone', 'isCustodial', 'fontSizeMode', 'claimToken', 'status', 'createdAt', 'updatedAt', 'syncStatus'],
  PeriodRecord: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'startDate', 'endDate', 'cycleLength', 'duration', 'symptoms', 'mood', 'note'],
  IntimacyRecord: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'date', 'pregnancyRisk', 'cycleDay', 'note'],
  Medication: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'forMemberId', 'medicineName', 'dosage', 'frequency', 'timeSlots', 'startDate', 'endDate', 'isActive', 'note'],
  MedicationLog: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'medicationId', 'timeSlot', 'takenBy', 'takenAt', 'status', 'note'],
  HealthMetric: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'forMemberId', 'metricType', 'value', 'unit', 'measuredAt', 'isAbnormal', 'note'],
  KidEvent: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'forMemberId', 'title', 'description', 'eventType', 'eventTime', 'location', 'isRecurring', 'recurrenceRule', 'reminderSettings', 'isSharedWith', 'isCompleted', 'completedAt'],
  GrowthRecord: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'forMemberId', 'height', 'weight', 'headCircumference', 'milestone', 'recordDate', 'photoUrl', 'note'],
  Reminder: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'title', 'description', 'reminderType', 'dueTime', 'isRecurring', 'recurrenceRule', 'isCompleted', 'completedAt', 'reminderSettings'],
  ShoppingItem: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'itemName', 'category', 'quantity', 'isPurchased', 'purchasedBy', 'purchasedAt'],
  Photo: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'url', 'thumbnailUrl', 'description', 'eventTag', 'takenAt'],
  PhotoComment: ['id', 'familyId', 'photoId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'isLike', 'content'],
  Memo: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'title', 'content', 'category', 'isEncrypted'],
  AccountingRecord: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'type', 'amount', 'category', 'description', 'date', 'forMemberId'],
  Budget: ['id', 'familyId', 'year', 'month', 'amount', 'category', 'createdAt', 'updatedAt'],
  LocationPlace: ['id', 'familyId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'name', 'placeType', 'latitude', 'longitude', 'address', 'forMemberId', 'radius'],
  FamilyInvitation: ['id', 'familyId', 'inviterId', 'inviteeId', 'inviteePhone', 'inviteCode', 'inviteMethod', 'status', 'expiresAt', 'createdAt', 'respondedAt'],
  PushToken: ['id', 'userId', 'token', 'deviceId', 'isActive', 'updatedAt', 'version'],
  UserNotifySetting: ['id', 'userId', 'familyId', 'enabled', 'mutedModules', 'updatedAt', 'version'],
  FamilyNotification: ['id', 'familyId', 'recipientId', 'title', 'content', 'action', 'recordType', 'recordId', 'relatedUserId', 'read', 'createdAt', 'updatedAt', 'version'],
};

/**
 * 把普通 JS 对象转为 CloudDBZoneGenericObject 实例。
 *
 * SDK 的 convertTClass 用 t[o]=e[o] 直接赋值，不经过 addFieldValue，
 * 导致 fieldMap 为空，serializeObject → getObject() 返回 {}，
 * Cloud DB 报 "input data does not contain the primary key field"。
 * 正确做法：用 addFieldValue 设置每个字段，更新 fieldMap。
 *
 * 类型转换（Cloud DB schema 不支持 Boolean/Array，需转为 Integer/Text）：
 * - boolean -> Integer (1/0)，schema 中 isCustodial/isDeleted/isCompleted 等均为 Integer
 * - Array -> JSON.stringify，schema 中 visibleMembers/timeSlots/reminderSettings 等均为 Text
 * - 普通对象（非 CloudDBZoneGenericObject）-> JSON.stringify，同上
 */
function toGenericObjects(objectType, records) {
  if (!Array.isArray(records)) records = [records];
  var allowedFields = SCHEMA_FIELDS[objectType];
  if (!allowedFields) {
    console.warn('[db] toGenericObjects: no schema field list for objectType=%s, allowing all fields', objectType);
    allowedFields = null; // 未知类型不过滤（向后兼容）
  }
  var allowedSet = allowedFields ? new Set(allowedFields) : null;
  return records.map(function (r) {
    if (r instanceof CloudDBZoneGenericObject) return r;
    var obj = CloudDBZoneGenericObject.build(objectType);
    var skipped = [];
    for (var key of Object.keys(r)) {
      var val = r[key];
      if (typeof val === 'function' || val === undefined) continue;
      // 白名单过滤：跳过 schema 未定义的字段（如 FamilyMember.isDeleted）
      if (allowedSet && !allowedSet.has(key)) {
        skipped.push(key + '=' + JSON.stringify(val).slice(0, 50));
        continue;
      }
      // boolean -> Integer (0/1)
      if (typeof val === 'boolean') {
        val = val ? 1 : 0;
      }
      // Array -> JSON string (schema Text)
      else if (Array.isArray(val)) {
        val = JSON.stringify(val);
      }
      // 普通对象 -> JSON string (schema Text)，排除 null/Date
      else if (val !== null && typeof val === 'object' && !(val instanceof Date)) {
        val = JSON.stringify(val);
      }
      obj.addFieldValue(key, val, !!SCHEMA_PRIMARY_KEYS[key]);
    }
    if (skipped.length > 0) {
      console.warn('[db] toGenericObjects: %s skipped %d unknown fields: %s', objectType, skipped.length, skipped.join(', '));
    }
    return obj;
  });
}

let dbCache = null;
let cloudInstance = null;

/**
 * 获取已初始化的 cloud 实例
 *
 * 优先级（2026-08-24 修正，解决线上 validate-invite 504 超时）：
 *   1. AGC 云函数运行时：平台自动注入 AGC_CONFIG 环境变量 → 直接使用默认 cloud 单例。
 *      SDK 构造时检测到 AGC_CONFIG 会用其初始化 default 实例，Cloud DB 走项目内部通道，
 *      快且稳定。若在此环境用 createInstance(文件凭证) 会走外部 OAuth
 *      （connect-api.cloud.huawei.com 的 client/token），容器出站连接被静默丢弃且
 *      SDK 请求无 timeout → 永久挂起 → 网关 504。
 *   2. 本地测试/非 AGC 环境（无 AGC_CONFIG）：createInstance(凭证文件, 唯一name)。
 *      唯一 name 避免被本地误设的 AGC_CONFIG 抢占（默认 name='default' 会被抢占）。
 *   3. 兜底：默认 cloud 单例。
 */
function getCloud() {
  if (cloudInstance) return cloudInstance;

  // AGC 云函数运行时：优先使用平台注入的 AGC_CONFIG（官方推荐 Method 1）
  if (process.env.AGC_CONFIG) {
    console.log('[db] AGC_CONFIG detected, using default cloud singleton (runtime-injected credential)');
    cloudInstance = cloud;
    return cloudInstance;
  }

  const credExists = fs.existsSync(CRED_FILE);
  console.log('[db] getCloud: no AGC_CONFIG, credFile=%s exists=%s', CRED_FILE, credExists);

  // 本地/非 AGC 环境：从打包的凭证文件创建实例（用唯一 name，避免被误设的 AGC_CONFIG 抢占）
  if (credExists) {
    try {
      cloudInstance = cloud.createInstance(CRED_FILE, 'kabao-file-cred');
      console.log('[db] cloud instance initialized from agc-credential.json (name=kabao-file-cred)');
      return cloudInstance;
    } catch (e) {
      console.warn('[db] createInstance from file failed:', e.message);
    }
  }

  // 兜底：默认 cloud 单例（依赖运行时注入 AGC_CONFIG）
  cloudInstance = cloud;
  console.log('[db] using default cloud singleton (relies on AGC_CONFIG env, file missing or init failed)');
  return cloudInstance;
}

/**
 * 按条件查询 Cloud DB
 * @param {string} objectType - 对象类型名（如 'Family'、'FamilyMember'，需与 AGC 控制台定义一致）
 * @param {Function} buildQuery - 接收 CloudDBZoneQuery 对象并返回（链式 where 调用）
 * @returns {Promise<Array>} 查询结果数组
 *
 * 用法示例：
 *   const families = await db.query('Family', q => q.equalTo('inviteCode', '123456'));
 */
async function query(objectType, buildQuery) {
  const db = getDB();
  const collection = db.collection(objectType);
  let q = collection.query();

  if (typeof buildQuery === 'function') {
    q = buildQuery(q) || q;
  }

  try {
    const results = await q.get();
    return Array.isArray(results) ? results : (results ? [results] : []);
  } catch (err) {
    // 诊断：记录完整错误对象，定位 401 发生在换 token 还是 API 调用阶段
    console.error('[db] query failed:', JSON.stringify(diagError(err, objectType)));
    throw err;
  }
}

/**
 * 从 Error 对象提取诊断信息（AGC SDK 错误可能藏在 response.data 里）
 */
function diagError(err, objectType) {
  if (!err) return { objectType };
  const resp = err.response;
  return {
    objectType: objectType || null,
    message: err.message,
    code: err.code,
    errorCode: err.errorCode || err.errCode || null,
    statusCode: err.statusCode || err.status || (resp && resp.status) || null,
    name: err.name,
    responseData: resp && resp.data
      ? (typeof resp.data === 'string' ? resp.data : JSON.stringify(resp.data)).slice(0, 500)
      : null,
    credentialExists: fs.existsSync(CRED_FILE),
  };
}

/**
 * 批量 upsert
 * @param {string} objectType - 对象类型名
 * @param {Array|Object} records - 要写入的记录
 * @returns {Promise<number>} 成功写入的记录数
 */
async function upsertMany(objectType, records) {
  if (!records || (Array.isArray(records) && records.length === 0)) return 0;
  const db = getDB();
  const objects = toGenericObjects(objectType, records);
  // 诊断：打印 fieldMap 内容（getObject 返回 fieldMap 的纯对象形式），定位 2003067 等服务端错误
  if (objects.length > 0) {
    try {
      var firstObj = objects[0];
      if (firstObj && typeof firstObj.getObject === 'function') {
        console.log('[db] upsertMany %s, fields=%s', objectType, JSON.stringify(firstObj.getObject()).slice(0, 600));
      }
    } catch (e) { /* 诊断日志不影响主流程 */ }
  }
  try {
    return await db.collection(objectType).upsert(objects);
  } catch (err) {
    console.error('[db] upsert failed:', JSON.stringify(diagError(err, objectType)));
    throw err;
  }
}

/**
 * 批量删除
 * @param {string} objectType - 对象类型名
 * @param {Array|Object} records - 要删除的记录
 * @returns {Promise<number>}
 */
async function deleteMany(objectType, records) {
  if (!records || (Array.isArray(records) && records.length === 0)) return 0;
  const db = getDB();
  const objects = toGenericObjects(objectType, records);
  // 诊断：打印 fieldMap + primaryKeys，定位 delete 静默不删问题
  if (objects.length > 0) {
    try {
      var firstObj = objects[0];
      if (firstObj && typeof firstObj.getObject === 'function') {
        var pks = firstObj.getPrimaryKeys ? Array.from(firstObj.getPrimaryKeys()) : [];
        console.log('[db] deleteMany %s, fields=%s, primaryKeys=%s', objectType, JSON.stringify(firstObj.getObject()).slice(0, 300), JSON.stringify(pks));
      }
    } catch (e) { /* 诊断日志不影响主流程 */ }
  }
  try {
    return await db.collection(objectType).delete(objects);
  } catch (err) {
    console.error('[db] delete failed:', JSON.stringify(diagError(err, objectType)));
    throw err;
  }
}

function getDB() {
  if (dbCache) return dbCache;
  dbCache = getCloud().database({ zoneName: ZONE_NAME });
  return dbCache;
}

module.exports = {
  ZONE_NAME,
  query,
  upsertMany,
  deleteMany
};
