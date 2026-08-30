# 家庭相册：长按下载 + 点赞评论 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 家庭相册新增「长按下载照片到系统相册」和「被分享者点赞/评论照片」两个能力，点赞评论跟随照片可见性，纯文字评论、只能删自己的。

**Architecture:** 新建云端对象类型 `PhotoComment`（点赞和评论共用一张表，每条互动独立记录避免并发覆盖），客户端通过现有 push/pull 云函数链路同步。下载走 Cloud Storage `downloadFile` + 免权限的 `photoAccessHelper.showAssetsCreationDialog` 存入系统相册。

**Tech Stack:** ArkTS/ArkUI（HarmonyOS NEXT, targetSdk 23）、AGC Cloud DB + Cloud Function（Node.js 18）、Cloud Storage、`@kit.MediaLibraryKit`。

**Spec:** `docs/superpowers/specs/2026-08-30-photo-download-like-comment-design.md`

---

## 关键背景（实现前必读）

- 客户端写操作模式：`LocalDbService.xxx()` → `saveItem/updateItem/removeItem` 写本地 Preferences → 自动 `pushToCloud` 推云（fire-and-forget）。读操作 `getList` 读本地，云端经 `CloudService.pullPhotos`/`syncAll` 合并。
- Cloud DB schema 不支持 Boolean/Array：`isLike` 用 Integer(0/1)，`visibleMembers` 用 Text(JSON)。服务端 `shared/db.js` 的 `toGenericObjects` 会自动做 boolean→Integer、Array→JSON 转换。
- `shared/db.js` 的 `SCHEMA_FIELDS` 白名单有 **4 份副本**（`cloud/shared/db.js` 为源头，部署脚本会从它覆盖到 zip 里；`cloud/push-data/shared/db.js`、`cloud/pull-data/shared/db.js`、`cloud/claim-member/shared/db.js` 是仓库内副本）。4 份都要改。
- 云函数部署：`node cloud/deploy.cjs push-data pull-data` 打包出 zip，需在 AGC 控制台上传部署。
- AGC Cloud DB 新表 `PhotoComment` 必须先由用户在 AGC 控制台创建（导入 Task 7 生成的 JSON），否则 Task 8 云端验证和真实同步都会失败。

---

## 文件结构

| 文件 | 责任 | 操作 |
|---|---|---|
| `entry/src/main/ets/model/PhotoComment.ets` | 照片互动模型 | 新建 |
| `entry/src/main/ets/common/CloudTypes.ets` | 本地 key ↔ 云端类型映射 | 修改 |
| `entry/src/main/ets/service/LocalDbService.ets` | photo_comments 本地存取 + 推云 | 修改 |
| `entry/src/main/ets/service/CloudService.ets` | pullPhotos 扩展拉取 PhotoComment | 修改 |
| `entry/src/main/ets/pages/AlbumPage.ets` | 长按下载 + 点赞评论 UI | 修改 |
| `cloud/shared/db.js` + 3 个函数包副本 | SCHEMA_FIELDS.PhotoComment 白名单 | 修改 |
| `cloud/push-data/index.js` | ALLOWED_TYPES 加 PhotoComment | 修改 |
| `cloud/pull-data/index.js` | ALL_TYPES + VISIBILITY_TYPES 加 PhotoComment | 修改 |
| `agc-clouddb-photocomment.json` | AGC 控制台导入用 schema | 新建 |
| `cloud/test-photocomment.cjs` | 云端 PhotoComment 读写验证 | 新建 |

---

## Task 1: PhotoComment 客户端模型

**Files:**
- Create: `entry/src/main/ets/model/PhotoComment.ets`

- [ ] **Step 1: 创建模型文件**

```typescript
/**
 * 照片互动模型：点赞 + 评论共用一张表
 * isLike=true 表示点赞记录（content 为空）；isLike=false 表示文字评论
 * 可见性字段（visibility/visibleMembers/creatorId）从所属照片复制，跟随照片共享范围
 */
import { BaseRecord } from './BaseRecord';

export class PhotoComment extends BaseRecord {
  photoId: string = '';
  isLike: boolean = false;
  content: string = '';
}
```

- [ ] **Step 2: 提交**

```bash
git add entry/src/main/ets/model/PhotoComment.ets
git commit -m "feat: add PhotoComment model for photo like/comment"
```

---

## Task 2: CloudTypes 类型映射

**Files:**
- Modify: `entry/src/main/ets/common/CloudTypes.ets`

- [ ] **Step 1: 在 `CLIENT_TO_CLOUD_TYPE` 加映射**

在 `'photos': 'Photo',` 后加一行：

```typescript
  'photo_comments': 'PhotoComment',
```

- [ ] **Step 2: 在 `ALL_CLOUD_TYPES` 数组加类型**

在 `'Photo', 'Memo',` 改为：

```typescript
  'Reminder', 'ShoppingItem', 'Photo', 'PhotoComment', 'Memo',
```

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/common/CloudTypes.ets
git commit -m "feat: register PhotoComment cloud type mapping"
```

---

## Task 3: LocalDbService 照片互动存取

**Files:**
- Modify: `entry/src/main/ets/service/LocalDbService.ets`

- [ ] **Step 1: 加 import**

在 `import { Photo } from '../model/Photo';` 后加：

```typescript
import { PhotoComment } from '../model/PhotoComment';
```

- [ ] **Step 2: 在家庭相册区块（`deletePhoto` 方法之后）加三个方法**

在 `async deletePhoto(id: string)` 方法结束后（第 626 行 `}` 之后、`// ---- 家庭备忘 ----` 之前）插入：

```typescript
  // ---- 照片互动（点赞/评论） ----
  async savePhotoComment(comment: PhotoComment): Promise<void> {
    await this.saveItem('photo_comments', comment);
    this.pushToCloud('photo_comments', comment, comment.version);
  }

  getPhotoComments(photoId: string): PhotoComment[] {
    const familyId = this.getCurrentFamilyId();
    let records: PhotoComment[];
    if (!familyId) {
      records = this.getList<PhotoComment>('photo_comments');
    } else {
      records = this.getList<PhotoComment>('photo_comments')
        .filter(c => c.familyId === familyId || c.familyId === '');
    }
    const visible = filterByVisibility(records, this.getCurrentUserId(), this.getCurrentMemberId());
    return visible.filter(c => c.photoId === photoId);
  }

  async deletePhotoComment(id: string): Promise<void> {
    const records = this.getList<PhotoComment>('photo_comments');
    const record = records.find(r => r.id === id);
    await this.removeItem('photo_comments', id);
    if (record) {
      record.isDeleted = true;
      this.pushToCloud('photo_comments', record, record.version + 1, 'delete');
    }
  }
```

- [ ] **Step 3: MODULE_LOCAL_KEYS 加 key**

将 `'album': ['photos'],` 改为：

```typescript
    'album': ['photos', 'photo_comments'],
```

- [ ] **Step 4: clearAllData 列表加 key**

在 `clearAllData()` 的 listKeys 中 `'shopping_items', 'photos', 'memos', 'invitations',` 改为：

```typescript
      'shopping_items', 'photos', 'photo_comments', 'memos', 'invitations',
```

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/service/LocalDbService.ets
git commit -m "feat: add photo comment local storage + cloud push"
```

---

## Task 4: CloudService 拉取照片互动

**Files:**
- Modify: `entry/src/main/ets/service/CloudService.ets`

- [ ] **Step 1: 扩展 `pullPhotos` 同时拉取 Photo + PhotoComment**

将 `pullPhotos` 方法体（约 619-634 行）整体替换为：

```typescript
  async pullPhotos(familyId: string): Promise<number> {
    if (!this.isCloudAvailable() || !familyId) return 0;
    try {
      const result = await this.pullFromCloudDb(familyId, ['Photo', 'PhotoComment']);
      let merged = 0;

      const photoRecords = result.snapshots['Photo'];
      if (Array.isArray(photoRecords) && photoRecords.length > 0) {
        await this.mergeToLocal('Photo', photoRecords);
        this.reconcileLocalDirty('Photo', photoRecords);
        merged += photoRecords.length;
      }

      const commentRecords = result.snapshots['PhotoComment'];
      if (Array.isArray(commentRecords) && commentRecords.length > 0) {
        await this.mergeToLocal('PhotoComment', commentRecords);
        this.reconcileLocalDirty('PhotoComment', commentRecords);
        merged += commentRecords.length;
      }

      return merged;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pullPhotos failed: %{public}s', (err as Error).message);
      return 0;
    }
  }
```

- [ ] **Step 2: 提交**

```bash
git add entry/src/main/ets/service/CloudService.ets
git commit -m "feat: pull PhotoComment records in pullPhotos"
```

---

## Task 5: 云端 SCHEMA_FIELDS.PhotoComment 白名单（4 份副本）

**Files:**
- Modify: `cloud/shared/db.js`
- Modify: `cloud/push-data/shared/db.js`
- Modify: `cloud/pull-data/shared/db.js`
- Modify: `cloud/claim-member/shared/db.js`

- [ ] **Step 1: 4 份文件各自在 `Photo: [...]` 行后加一行**

在 `SCHEMA_FIELDS` 对象中 `Photo: [...]` 行后加：

```javascript
  PhotoComment: ['id', 'familyId', 'photoId', 'creatorId', 'visibility', 'visibleMembers', 'version', 'createdAt', 'updatedAt', 'isDeleted', 'isLike', 'content'],
```

- [ ] **Step 2: 验证 4 份文件内容一致**

```bash
cd C:/Users/Andy/kabao
for f in cloud/shared/db.js cloud/push-data/shared/db.js cloud/pull-data/shared/db.js cloud/claim-member/shared/db.js; do
  grep -c "PhotoComment" "$f"
done
# 期望每份输出 1
```

- [ ] **Step 3: 提交**

```bash
git add cloud/shared/db.js cloud/push-data/shared/db.js cloud/pull-data/shared/db.js cloud/claim-member/shared/db.js
git commit -m "feat: add PhotoComment schema field whitelist to cloud db"
```

---

## Task 6: 云端 push-data / pull-data 类型白名单

**Files:**
- Modify: `cloud/push-data/index.js`
- Modify: `cloud/pull-data/index.js`

- [ ] **Step 1: push-data ALLOWED_TYPES 加类型**

在 `cloud/push-data/index.js` 的 `ALLOWED_TYPES` 中，`'Photo',` 后加：

```javascript
  'PhotoComment',
```

- [ ] **Step 2: pull-data ALL_TYPES 加类型**

在 `cloud/pull-data/index.js` 的 `ALL_TYPES` 中，`'Photo',` 后加：

```javascript
  'PhotoComment',
```

- [ ] **Step 3: pull-data VISIBILITY_TYPES 加类型**

在 `cloud/pull-data/index.js` 的 `VISIBILITY_TYPES` 中，`'Photo',` 后加：

```javascript
  'PhotoComment',
```

- [ ] **Step 4: 语法检查两个文件**

```bash
node --check cloud/push-data/index.js
node --check cloud/pull-data/index.js
# 期望：无输出（通过）
```

- [ ] **Step 5: 提交**

```bash
git add cloud/push-data/index.js cloud/pull-data/index.js
git commit -m "feat: allowlist PhotoComment in push-data and pull-data"
```

---

## Task 7: AGC PhotoComment schema JSON（供控制台导入）

**Files:**
- Create: `agc-clouddb-photocomment.json`

- [ ] **Step 1: 创建 schema JSON**

格式与 `agc-clouddb-object-types.json` 完全一致（主键无 defaultValue、indexes 用对象数组、permissions 顶层独立数组）：

```json
{
  "schemaVersion": 1,
  "objectTypes": [
    {
      "objectTypeName": "PhotoComment",
      "fields": [
        { "fieldName": "id", "fieldType": "String", "belongPrimaryKey": true, "notNull": true, "isNeedEncrypt": false, "isSensitive": false },
        { "fieldName": "familyId", "fieldType": "String", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "photoId", "fieldType": "String", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "creatorId", "fieldType": "String", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "visibility", "fieldType": "String", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "visibleMembers", "fieldType": "Text", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "version", "fieldType": "Integer", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": 0 },
        { "fieldName": "createdAt", "fieldType": "String", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "updatedAt", "fieldType": "String", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" },
        { "fieldName": "isDeleted", "fieldType": "Integer", "belongPrimaryKey": false, "notNull": false, "isNeedEncrypt": false, "isSensitive": false },
        { "fieldName": "isLike", "fieldType": "Integer", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": 0 },
        { "fieldName": "content", "fieldType": "Text", "belongPrimaryKey": false, "notNull": true, "isNeedEncrypt": false, "isSensitive": false, "defaultValue": "" }
      ],
      "indexes": [
        { "indexName": "familyId", "indexList": [{ "fieldName": "familyId", "sortType": "ASC" }] },
        { "indexName": "photoId", "indexList": [{ "fieldName": "photoId", "sortType": "ASC" }] }
      ]
    }
  ],
  "permissions": [
    {
      "objectTypeName": "PhotoComment",
      "permissions": [
        { "role": "World", "rights": [] },
        { "role": "Authenticated", "rights": ["Read", "Upsert"] },
        { "role": "Creator", "rights": ["Read", "Upsert", "Delete"] },
        { "role": "Administrator", "rights": ["Read", "Upsert", "Delete"] }
      ]
    }
  ]
}
```

- [ ] **Step 2: JSON 语法校验**

```bash
node -e "JSON.parse(require('fs').readFileSync('agc-clouddb-photocomment.json','utf8')); console.log('valid JSON')"
# 期望输出: valid JSON
```

- [ ] **Step 3: 提交**

```bash
git add agc-clouddb-photocomment.json
git commit -m "feat: add PhotoComment AGC Cloud DB schema for import"
```

> ⚠️ **用户操作（此时暂停，先让用户去 AGC 控制台建表）：**
> 打开 AGC 控制台 → 项目 → 构建 → Cloud DB → 对象类型 → 导入/新建 `PhotoComment`，粘贴 `agc-clouddb-photocomment.json` 的 objectType + permissions 内容（或按字段手动建），保存并部署。**表创建成功前不要执行 Task 8。**

---

## Task 8: 云端 PhotoComment 读写本地验证

**Files:**
- Create: `cloud/test-photocomment.cjs`

> 前置：AGC 控制台已创建 PhotoComment 表（Task 7 的用户操作）。

- [ ] **Step 1: 创建验证脚本**

```javascript
#!/usr/bin/env node
/**
 * PhotoComment 云端读写本地验证（连真实 Cloud DB，admin 凭证）
 * 用法（cloud/ 目录下）：
 *   node test-photocomment.cjs
 * 若报找不到 @hw-agconnect/cloud-server，先设置：
 *   NODE_PATH=c:\\Users\\Andy\\kabao\\cloud\\push-data\\node_modules node test-photocomment.cjs
 */
const db = require('./shared/db');

const TEST_FAMILY = 'fam_photocomment_test';
const TEST_PHOTO = 'ph_photocomment_test';
const TEST_PREFIX = 'pc_test_' + Date.now();

async function main() {
  const now = new Date().toISOString();
  const like = {
    id: TEST_PREFIX + '_like',
    familyId: TEST_FAMILY,
    photoId: TEST_PHOTO,
    creatorId: 'mem_test',
    visibility: 'FAMILY',
    visibleMembers: [],
    version: 1,
    createdAt: now,
    updatedAt: now,
    isLike: true,
    content: ''
  };
  const comment = {
    id: TEST_PREFIX + '_comment',
    familyId: TEST_FAMILY,
    photoId: TEST_PHOTO,
    creatorId: 'mem_test',
    visibility: 'FAMILY',
    visibleMembers: [],
    version: 1,
    createdAt: now,
    updatedAt: now,
    isLike: false,
    content: '测试评论'
  };

  // 1. upsert 点赞 + 评论
  await db.upsertMany('PhotoComment', [like, comment]);
  console.log('✓ upsert 2 records');

  // 2. 按 photoId 查询
  const list = await db.query('PhotoComment', q => q.equalTo('photoId', TEST_PHOTO));
  console.log('✓ query by photoId count =', list.length);
  if (list.length < 2) throw new Error('expected >= 2 records, got ' + list.length);

  // 3. 校验 isLike 区分（Integer 1=点赞 / 0=评论）
  const raw = list.map(r => (typeof r.getObject === 'function') ? r.getObject() : r);
  const isLikeRec = raw.find(r => r.isLike === 1 || r.isLike === true);
  const commentRec = raw.find(r => !(r.isLike === 1 || r.isLike === true));
  if (!isLikeRec || !commentRec) throw new Error('isLike 区分失败: ' + JSON.stringify(raw));
  console.log('✓ isLike 区分正确（点赞=', JSON.stringify(isLikeRec.isLike), '评论=', JSON.stringify(commentRec.isLike), '）');

  // 4. 墓碑删除（isDeleted=1）
  await db.upsertMany('PhotoComment', [{ ...like, isDeleted: 1, version: 2 }]);
  const after = await db.query('PhotoComment', q => q.equalTo('photoId', TEST_PHOTO));
  const rawAfter = after.map(r => (typeof r.getObject === 'function') ? r.getObject() : r);
  if (!rawAfter.some(r => r.isDeleted === 1)) throw new Error('tombstone 未生效');
  console.log('✓ 墓碑删除生效');

  // 5. 清理测试数据
  await db.deleteMany('PhotoComment', rawAfter);
  console.log('✓ 测试数据已清理');

  console.log('\n全部通过 ✅');
}

main().catch(e => {
  console.error('FAILED:', e && e.message);
  process.exit(1);
});
```

- [ ] **Step 2: 运行验证**

```bash
cd C:/Users/Andy/kabao/cloud
NODE_PATH="C:/Users/Andy/kabao/cloud/push-data/node_modules" node test-photocomment.cjs
# 期望：5 个 ✓ + "全部通过 ✅"；若 upsert 报 schema/字段错误，说明 AGC 表未建好或字段不一致
```

- [ ] **Step 3: 提交**

```bash
git add cloud/test-photocomment.cjs
git commit -m "test: add PhotoComment cloud read/write verification"
```

---

## Task 9: AlbumPage 长按下载照片

**Files:**
- Modify: `entry/src/main/ets/pages/AlbumPage.ets`

- [ ] **Step 1: 加 import**

在 `import { fileIo } from '@kit.CoreFileKit';` 改为：

```typescript
import { fileIo, fileUri } from '@kit.CoreFileKit';
```

在 `import { curves } from '@kit.ArkUI';` 改为：

```typescript
import { curves, promptAction } from '@kit.ArkUI';
```

- [ ] **Step 2: 加两个私有方法（放在 `toImageSrc` 方法之后）**

```typescript
  /** 把本地路径转成 file:// URI（showAssetsCreationDialog 要求 file:// 格式） */
  private toFileUri(path: string): string {
    if (path.startsWith('file://')) return path;
    return fileUri.getUriFromPath(path);
  }

  /** 下载照片到系统相册：云端图先下载到沙箱，再通过系统弹窗保存 */
  private async downloadPhoto(photo: Photo): Promise<void> {
    try {
      let localPath = '';
      if (photo.url && photo.url.startsWith('http')) {
        const context = getContext(this) as common.UIAbilityContext;
        localPath = `${context.filesDir}/download_${photo.id}.jpg`;
        const ok = await CloudService.getInstance().downloadFile(
          CloudService.photoCloudPath(photo.familyId, photo.id), localPath);
        if (!ok) {
          promptAction.showToast({ message: '下载失败，请检查网络', duration: 1500 });
          return;
        }
      } else if (photo.url) {
        localPath = photo.url;
      } else {
        promptAction.showToast({ message: '照片文件不存在', duration: 1500 });
        return;
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this) as common.UIAbilityContext);
      const result = await helper.showAssetsCreationDialog(
        [this.toFileUri(localPath)],
        [{ fileNameExtension: 'jpg', photoType: photoAccessHelper.PhotoType.IMAGE }]
      );
      if (result && result.length > 0) {
        promptAction.showToast({ message: '已保存到系统相册', duration: 1500 });
      } else {
        promptAction.showToast({ message: '已取消保存', duration: 1500 });
      }
    } catch (err) {
      promptAction.showToast({ message: '保存失败：' + (err as Error).message, duration: 2000 });
    }
  }
```

- [ ] **Step 3: 网格照片项加长按手势**

在网格视图的照片 `Column()`（`.width('48%')... .onClick(() => { this.openViewer(photo); })`，约 271-275 行）加手势。将：

```typescript
              .onClick(() => { this.openViewer(photo); })
            }, (photo: Photo) => `${photo.id}_${photo.updatedAt}`)
```

改为：

```typescript
              .onClick(() => { this.openViewer(photo); })
              .gesture(
                LongPressGesture()
                  .onAction((event: GestureEvent) => { this.downloadPhoto(photo); })
              )
            }, (photo: Photo) => `${photo.id}_${photo.updatedAt}`)
```

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/pages/AlbumPage.ets
git commit -m "feat: long-press photo to download to system gallery"
```

---

## Task 10: AlbumPage 点赞 + 评论

**Files:**
- Modify: `entry/src/main/ets/pages/AlbumPage.ets`

- [ ] **Step 1: 加 import**

在 `import { Photo } from '../model/Photo';` 后加：

```typescript
import { PhotoComment } from '../model/PhotoComment';
```

- [ ] **Step 2: 加 @State 状态**

在 `@State viewerPhoto: Photo | null = null;` 后加：

```typescript
  @State viewerLikes: PhotoComment[] = [];
  @State viewerComments: PhotoComment[] = [];
  @State viewerLikedByMe: boolean = false;
  @State commentInput: string = '';
  @State isSendingComment: boolean = false;
  @State isTogglingLike: boolean = false;
```

- [ ] **Step 3: 加互动逻辑方法（放在 `closeViewer` 方法之后）**

```typescript
  /** 从本地库刷新查看器当前照片的点赞/评论数据 */
  private refreshViewerInteractions(): void {
    if (!this.viewerPhoto) {
      this.viewerLikes = [];
      this.viewerComments = [];
      this.viewerLikedByMe = false;
      return;
    }
    const all = this.db.getPhotoComments(this.viewerPhoto.id);
    this.viewerLikes = all.filter(c => c.isLike && !c.isDeleted);
    this.viewerComments = all.filter(c => !c.isLike && !c.isDeleted)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    this.viewerLikedByMe = this.viewerLikes.some(c => this.db.isRecordCreator(c.creatorId));
  }

  /** 切换点赞：未赞 → 新建点赞记录；已赞 → 删除自己的点赞记录 */
  private async toggleLike(): Promise<void> {
    if (this.isTogglingLike || !this.viewerPhoto) return;
    this.isTogglingLike = true;
    try {
      const photo = this.viewerPhoto;
      const myLike = this.viewerLikes.find(c => this.db.isRecordCreator(c.creatorId));
      if (myLike) {
        await this.db.deletePhotoComment(myLike.id);
      } else {
        const now = new Date().toISOString();
        const comment: PhotoComment = {
          id: generateId('pc'),
          familyId: photo.familyId,
          photoId: photo.id,
          creatorId: this.db.getCurrentMemberId(),
          visibility: photo.visibility,
          visibleMembers: photo.visibleMembers,
          version: 1,
          createdAt: now,
          updatedAt: now,
          isLike: true,
          content: ''
        };
        await this.db.savePhotoComment(comment);
      }
      this.refreshViewerInteractions();
    } finally {
      this.isTogglingLike = false;
    }
  }

  /** 发送文字评论 */
  private async sendComment(): Promise<void> {
    if (this.isSendingComment || !this.viewerPhoto) return;
    const text = this.commentInput.trim();
    if (!text) return;
    this.isSendingComment = true;
    try {
      const photo = this.viewerPhoto;
      const now = new Date().toISOString();
      const comment: PhotoComment = {
        id: generateId('pc'),
        familyId: photo.familyId,
        photoId: photo.id,
        creatorId: this.db.getCurrentMemberId(),
        visibility: photo.visibility,
        visibleMembers: photo.visibleMembers,
        version: 1,
        createdAt: now,
        updatedAt: now,
        isLike: false,
        content: text
      };
      await this.db.savePhotoComment(comment);
      this.commentInput = '';
      this.refreshViewerInteractions();
    } finally {
      this.isSendingComment = false;
    }
  }

  /** 删除自己的评论 */
  private async deleteComment(comment: PhotoComment): Promise<void> {
    await this.db.deletePhotoComment(comment.id);
    this.refreshViewerInteractions();
  }
```

- [ ] **Step 4: openViewer 打开时刷新互动数据**

将 `openViewer` 改为：

```typescript
  private openViewer(photo: Photo): void {
    this.viewerPhoto = photo;
    this.showPhotoViewer = true;
    this.refreshViewerInteractions();
  }
```

- [ ] **Step 5: 查看器底部加点赞 + 评论 UI**

替换 `PhotoViewerOverlay` 中「底部信息」区块（从 `// 底部信息：描述 + 标签 + 时间 + 操作按钮` 注释开始到 `if (this.isCreator(this.viewerPhoto!.creatorId)) {` 之前的整个 `Column()` 内容，即原 383-419 行）：

原：

```typescript
        // 底部信息：描述 + 标签 + 时间 + 操作按钮
        Column() {
          if (this.viewerPhoto!.description) {
            Text(this.viewerPhoto!.description)
              .fontSize(15).fontColor(Color.White)
              .width('100%')
          }
          Row({ space: 12 }) {
            if (this.viewerPhoto!.eventTag) {
              Text(`🏷 ${this.viewerPhoto!.eventTag}`).fontSize(13).fontColor('#CCFFFFFF')
            }
            Text(formatIsoToLocal(this.viewerPhoto!.takenAt)).fontSize(13).fontColor('#CCFFFFFF')
          }
          .width('100%')
          .margin({ top: 6 })

          if (this.isCreator(this.viewerPhoto!.creatorId)) {
```

新：

```typescript
        // 底部信息：描述 + 标签 + 时间 + 点赞/评论 + 操作按钮
        Column() {
          if (this.viewerPhoto!.description) {
            Text(this.viewerPhoto!.description)
              .fontSize(15).fontColor(Color.White)
              .width('100%')
          }
          Row({ space: 12 }) {
            if (this.viewerPhoto!.eventTag) {
              Text(`🏷 ${this.viewerPhoto!.eventTag}`).fontSize(13).fontColor('#CCFFFFFF')
            }
            Text(formatIsoToLocal(this.viewerPhoto!.takenAt)).fontSize(13).fontColor('#CCFFFFFF')
          }
          .width('100%')
          .margin({ top: 6 })

          // 点赞 + 保存到相册（所有人可用）
          Row({ space: 20 }) {
            Row({ space: 6 }) {
              Text(this.viewerLikedByMe ? '❤️' : '🤍').fontSize(20)
              Text(`${this.viewerLikes.length}`)
                .fontSize(14).fontColor(this.viewerLikedByMe ? '#FF8A80' : Color.White)
            }
            .padding(4)
            .onClick(() => { this.toggleLike(); })
            Row({ space: 6 }) {
              Text('💾').fontSize(18)
              Text('保存到相册').fontSize(13).fontColor(Color.White)
            }
            .padding(4)
            .onClick(() => { this.downloadPhoto(this.viewerPhoto!); })
          }
          .width('100%')
          .margin({ top: 10 })

          // 评论列表
          if (this.viewerComments.length > 0) {
            Scroll() {
              Column({ space: 8 }) {
                ForEach(this.viewerComments, (c: PhotoComment) => {
                  Row() {
                    Text(this.getMemberLabel(c.creatorId))
                      .fontSize(12).fontColor('#FFD9B3')
                    Text(c.content)
                      .fontSize(14).fontColor(Color.White)
                      .layoutWeight(1)
                      .margin({ left: 6 })
                    if (this.db.isRecordCreator(c.creatorId)) {
                      Text('删除')
                        .fontSize(12).fontColor('#FF8A80')
                        .padding(4)
                        .onClick(() => { this.deleteComment(c); })
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }, (c: PhotoComment) => c.id + '_' + c.updatedAt)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(8)
            }
            .width('100%')
            .constraintSize({ maxHeight: 140 })
            .scrollBar(BarState.Auto)
            .margin({ top: 8 })
          }

          // 评论输入
          Row({ space: 8 }) {
            TextInput({ placeholder: '写评论...', text: this.commentInput })
              .fontSize(14).fontColor(Color.White)
              .placeholderColor('#66FFFFFF')
              .backgroundColor('#26FFFFFF')
              .borderRadius(16)
              .height(34)
              .layoutWeight(1)
              .onChange((v: string) => { this.commentInput = v; })
            Text(this.isSendingComment ? '...' : '发送')
              .fontSize(13).fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(16)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .onClick(() => { this.sendComment(); })
          }
          .width('100%')
          .margin({ top: 8 })

          if (this.isCreator(this.viewerPhoto!.creatorId)) {
```

- [ ] **Step 6: 删除照片时级联墓碑删除其评论**

在 `deletePhotoWithFile` 中，`await this.db.deletePhoto(photo.id);` 前插入：

```typescript
    // 级联删除该照片的点赞/评论（墓碑，跨设备同步）
    const comments = this.db.getPhotoComments(photo.id);
    for (const c of comments) {
      await this.db.deletePhotoComment(c.id);
    }
```

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/pages/AlbumPage.ets
git commit -m "feat: like and comment photos in album viewer"
```

---

## Task 11: 构建验证 + 云端打包部署

- [ ] **Step 1: 项目构建**

```bash
cd C:/Users/Andy/kabao
hvigorw assembleHap
# 期望：BUILD SUCCESSFUL；若有 ArkTS 编译错误，修复后重跑
```

- [ ] **Step 2: 打包云函数 zip**

```bash
cd C:/Users/Andy/kabao
node cloud/deploy.cjs push-data pull-data
# 期望：生成 cloud/dist/push-data.zip 和 cloud/dist/pull-data.zip
```

- [ ] **Step 3: 输出给用户的部署清单**

向用户交付以下待办（用户手动操作）：
1. AGC 控制台 Cloud DB 导入 `agc-clouddb-photocomment.json`（若 Task 7 已做则跳过）。
2. 在 AGC 控制台分别上传部署 `cloud/dist/push-data.zip`、`cloud/dist/pull-data.zip`（运行时 Node.js 18、HTTP POST + AGC Auth）。
3. 真机/模拟器手动测试清单：
   - 网格长按照片 → 系统相册出现该照片；查看器「保存到相册」按钮同样生效。
   - 查看器点 ❤️ → 数字 +1 且变红；再点 → 复原。
   - 发评论 → 列表出现（成员名 + 内容）；自己的评论有「删除」，点击删除后消失。
   - 双设备：A 传 FAMILY 照片，B 点赞评论，A 重开相册页（触发 pullPhotos）可见互动。
   - 并发：A、B 同时点赞同一张照片，两边都成功（各自独立记录，无覆盖）。
   - PRIVATE/SELECTED 照片：只有可见成员能看到/操作互动。

- [ ] **Step 4: 收尾提交（如有修复）**

```bash
git add -A
git commit -m "chore: verify photo download + like/comment feature"
```

---

## 自审记录

- **Spec 覆盖**：下载（Task 9）✓；点赞（Task 10）✓；评论纯文字+删自己（Task 10）✓；可见性跟随照片（Task 3/5/6 + AlbumPage 复制 photo 的 visibility）✓；无通知（未实现）✓；新建表避免并发覆盖（Task 1/5/6）✓。
- **占位符**：无 TBD/TODO。
- **类型一致性**：`PhotoComment` 字段 `photoId/isLike/content` 在 Task 1/3/10 一致；`db.getPhotoComments(photoId)` 签名一致；`downloadPhoto(photo)`、`toggleLike()`、`sendComment()`、`deleteComment(comment)` 在 Task 9/10 中定义与调用一致。
