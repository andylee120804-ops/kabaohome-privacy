/**
 * PhotoComment 云端验证（本地直连 Cloud DB）
 *
 * 验证内容：
 *   1. upsert：写一条点赞记录（isLike=1）+ 一条评论记录（content 非空）
 *   2. 按 photoId 查询：两条都能查到
 *   3. isLike 区分：isLike=1 是点赞、content 非空是评论
 *   4. 墓碑删除：delete 一条后查询只剩另一条（isDeleted=1 保留可同步）
 *   5. 清理：测试结束后硬删除测试记录
 *
 * 用法：node test-photocomment.cjs
 * 注意：会向 Cloud DB 写入测试 PhotoComment（pc_e2e_test_*），结束自动清理。
 *       需要先在 AGC 控制台创建 PhotoComment 对象类型（用 agc-clouddb-photocomment.json 导入）。
 */
const db = require('./validate-invite/shared/db.js');

function plain(r) { return (typeof r.getObject === 'function') ? r.getObject() : r; }

const FAMILY_ID = 'fam_1786774196389_sajkip567'; // 缪缪家
const UID = 'AQBFyfPIsAkHertQRiiGHdtCu_eP';      // 卡卡小仙女（家庭成员）
const MEMBER_ID = 'mem_1786774196389_3l0pio16u';
const TEST_PHOTO = 'photo_e2e_test_' + Date.now();
const LIKE_ID = 'pc_e2e_like_' + Date.now();
const COMMENT_ID = 'pc_e2e_comment_' + Date.now();

const now = new Date().toISOString();

function base(id) {
  return {
    id: id,
    familyId: FAMILY_ID,
    photoId: TEST_PHOTO,
    creatorId: MEMBER_ID,
    visibility: 'FAMILY',
    visibleMembers: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
    isDeleted: 0
  };
}

(async () => {
  // 0) 确认测试用户是家庭成员
  const mems = await db.query('FamilyMember', q => q.equalTo('familyId', FAMILY_ID).equalTo('userId', UID));
  console.log('membership check:', mems.length > 0 ? 'OK' : 'NOT A MEMBER (abort)');
  if (mems.length === 0) process.exit(1);

  // 1) upsert 点赞记录 + 评论记录
  const like = { ...base(LIKE_ID), isLike: 1, content: '' };
  const comment = { ...base(COMMENT_ID), isLike: 0, content: '云端验证评论' };
  await db.upsertMany('PhotoComment', [like, comment]);
  console.log('\n[1] upserted like + comment for photo', TEST_PHOTO);

  // 2) 按 photoId 查询
  let rows = await db.query('PhotoComment', q => q.equalTo('photoId', TEST_PHOTO));
  console.log('[2] query by photoId ->', rows.length, 'records');
  if (rows.length !== 2) { console.error('UNEXPECTED: expected 2 records'); process.exit(1); }

  // 3) isLike 区分
  const likes = rows.filter(r => plain(r).isLike === 1);
  const comments = rows.filter(r => (plain(r).content || '').length > 0);
  console.log('[3] likes=%d comments=%d', likes.length, comments.length);
  if (likes.length !== 1 || comments.length !== 1) { console.error('UNEXPECTED: like/comment split'); process.exit(1); }

  // 4) 墓碑删除评论（isDeleted=1 保留字段，跨设备可同步清理）
  await db.upsertMany('PhotoComment', { ...comment, isDeleted: 1, version: 2, updatedAt: now });
  rows = await db.query('PhotoComment', q => q.equalTo('photoId', TEST_PHOTO));
  const deleted = rows.filter(r => plain(r).isDeleted === 1);
  console.log('[4] after tombstone: total=%d tombstones=%d', rows.length, deleted.length);
  if (deleted.length !== 1) { console.error('UNEXPECTED: tombstone not found'); process.exit(1); }

  console.log('\nALL CHECKS PASSED');

  // 5) 清理
  await db.deleteMany('PhotoComment', rows);
  console.log('[5] cleaned up', rows.length, 'test records');
  process.exit(0);
})().catch(err => {
  console.error('TEST FAILED:', err && err.message || err);
  process.exit(1);
});
