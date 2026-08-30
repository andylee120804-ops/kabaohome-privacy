/**
 * Cloud DB 访问辅助层
 *
 * 华为云函数运行时内置 @hw-agconnect/cloud-server SDK，
 * 通过该 SDK 可以以服务端管理员权限直接读写 Cloud DB。
 *
 * Zone 名称需与客户端 AgcConfig.CLOUD_DB_ZONE_NAME 保持一致：'kabaoHomeZone'
 */
const agconnect = require('@hw-agconnect/cloud-server');

const ZONE_NAME = 'kabaoHomeZone';

let initialized = false;

/**
 * 初始化 AGC Server SDK
 * 云函数环境会自动注入凭证，但显式 init 一次更安全
 */
function ensureInit() {
  if (initialized) return;
  try {
    // 云函数环境下通常会自动加载凭证文件
    // 也支持手动调用 agconnect.AGCClient.initialize(...)
    if (typeof agconnect.AGCClient !== 'undefined' && agconnect.AGCClient.getInstance) {
      // 已通过环境变量初始化
    }
    initialized = true;
  } catch (e) {
    console.warn('[db] agconnect init warning:', e.message);
  }
}

/**
 * 获取 Cloud DB Zone 操作对象
 */
function getZone() {
  ensureInit();
  const cloudDB = agconnect.cloudDB || agconnect.CloudDB;
  if (!cloudDB) {
    throw new Error('CloudDB SDK not available in runtime');
  }
  const dbInstance = cloudDB.getInstance ? cloudDB.getInstance() : cloudDB;
  return dbInstance.zone(ZONE_NAME);
}

/**
 * 按条件查询
 * @param {string} objectType - 对象类型名（如 'FamilyMember'）
 * @param {Function} buildQuery - 接收 query 对象并返回（链式 where 调用）
 */
async function query(objectType, buildQuery) {
  const zone = getZone();
  const cloudDB = agconnect.cloudDB || agconnect.CloudDB;
  let q = cloudDB.CloudDBQuery
    ? cloudDB.CloudDBQuery.where(objectType)
    : zone.query(objectType);

  if (typeof buildQuery === 'function') {
    q = buildQuery(q) || q;
  }
  const snapshot = await zone.executeQuery(q);
  return snapshot && snapshot.getSnapshotObjects
    ? snapshot.getSnapshotObjects()
    : (snapshot || []);
}

/**
 * 批量 upsert
 */
async function upsertMany(objectType, records) {
  if (!records || records.length === 0) return 0;
  const zone = getZone();
  // 不同 SDK 版本接口略有差异；以下为兼容写法
  if (typeof zone.executeUpsert === 'function') {
    return await zone.executeUpsert(objectType, records);
  }
  return await zone.upsert(objectType, records);
}

/**
 * 批量删除
 */
async function deleteMany(objectType, records) {
  if (!records || records.length === 0) return 0;
  const zone = getZone();
  if (typeof zone.executeDelete === 'function') {
    return await zone.executeDelete(objectType, records);
  }
  return await zone.delete(objectType, records);
}

module.exports = {
  ZONE_NAME,
  ensureInit,
  getZone,
  query,
  upsertMany,
  deleteMany
};
