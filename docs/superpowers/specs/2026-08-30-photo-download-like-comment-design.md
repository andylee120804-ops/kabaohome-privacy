# 家庭相册：长按下载 + 点赞评论 设计文档

- 日期：2026-08-30
- 模块：家庭相册（AlbumPage）
- 状态：已与用户确认设计决策

## 1. 背景与目标

家庭相册（AlbumPage）目前支持：上传照片、按成员/日期/标签筛选、全屏查看、编辑描述/标签、删除（仅创建者）。用户希望新增两个能力：

1. **长按下载照片**：长按照片 → 保存到系统相册。
2. **点赞 + 评论**：被分享者（能看到照片的成员）可以对照片点赞、发表文字评论。

### 已确认的设计决策（与用户逐项确认）

| 决策点 | 选择 |
|--------|------|
| 点赞/评论可见范围 | **跟随照片共享范围**（能看照片 → 能点赞评论 → 能看到全部互动） |
| 评论能力 | **纯文字**，只能删除自己的评论（不编辑、不删别人、不带图） |
| 下载目标 | **保存到系统相册**，优先免权限的系统弹窗方案，退回申请 `WRITE_IMAGEVIDEO` |
| 互动通知 | **不需要**（打开相册页即见） |

## 2. 数据模型：新建 `PhotoComment` 云端表

### 为什么新建表而不是把互动塞进 Photo 记录

Photo 记录走版本号冲突检测（push-data `detectConflict`：服务端版本 > 客户端版本即拒绝）。若把点赞数/评论数组放进 Photo 字段，多成员并发互动会互相覆盖：A、B 几乎同时点赞同一张照片，后写入的本地副本不含对方互动，覆盖导致丢点赞。

把每条点赞/评论独立成记录（各自有 id/version）即可完全避免丢失，且与 App 现有"每条记录一行"的架构一致（如 MedicationLog 之于 Medication）。

### 表结构（与现有 Photo 同风格，含可见性字段）

```
PhotoComment:
  id             String  主键（'pc_' 前缀 + generateId）
  familyId       String
  photoId        String  指向照片记录 id
  creatorId      String  互动者（memberId，兼容旧 userId）
  visibility     String  FAMILY / PRIVATE / SELECTED（从照片复制）
  visibleMembers Text    JSON 数组（从照片复制，存 userId）
  version        Integer
  createdAt      String  (ISO)
  updatedAt      String  (ISO)
  isDeleted      Integer 0/1 墓碑
  isLike         Integer 0/1  1=点赞记录，0=文字评论
  content        Text    评论文字（点赞记录为空）
```

- 点赞 = 写一条 `isLike:1` 记录；取消点赞 = 删除自己那条（墓碑）。
- 评论 = 写一条 `content` 非空记录；删除 = 墓碑删除，仅限 creatorId === 自己。
- 照片点赞数 = 该 photoId 下 `isLike:1` 且未删除的记录数。
- 照片评论列表 = 该 photoId 下 `content` 非空的记录，按 createdAt 升序。
- 可见性跟随照片：新建互动时从照片复制 `visibility`/`visibleMembers`/`creatorId`。pull-data 的可见性过滤（`VISIBILITY_TYPES`）对 PhotoComment 直接生效，无需与 Photo 联表。

## 3. 客户端改动

### 3.1 新增模型 `entry/src/main/ets/model/PhotoComment.ets`

```typescript
import { BaseRecord } from './BaseRecord';

export class PhotoComment extends BaseRecord {
  photoId: string = '';
  isLike: boolean = false;
  content: string = '';
}
```

（BaseRecord 已含 id/familyId/creatorId/visibility/visibleMembers/version/createdAt/updatedAt/isDeleted。）

### 3.2 LocalDbService

- 本地 key：`photo_comments` → 云端 `PhotoComment`。
- 新增方法：
  - `savePhotoComment(comment)`：saveItem + pushToCloud（upsert）
  - `getPhotoComments(photoId)`：按 familyId 过滤 + `filterByVisibility` + 按 photoId 过滤
  - `deletePhotoComment(id)`：removeItem + 墓碑推云（delete）
- 把 `photo_comments` 加入模块关联表（`'album': ['photos', 'photo_comments']`）和数据清理清单（getAllLocalKeys 附近）。

### 3.3 CloudTypes

- `CLIENT_TO_CLOUD_TYPE['photo_comments'] = 'PhotoComment'`
- `ALL_CLOUD_TYPES` 数组追加 `'PhotoComment'`（反向映射 CLOUD_TO_CLIENT 自动生成）。

### 3.4 AlbumPage UI

**长按下载（网格）**
- 网格照片项挂 `.gesture(LongPressGesture().onAction(...))` → `downloadPhoto(photo)`。
- 下载流程：
  1. 若 `photo.url` 是 https（已上云）：`CloudService.downloadFile(photoCloudPath(familyId, photoId), 沙箱临时路径)`；若 url 是本地路径：直接用该路径。
  2. 保存到系统相册：优先 `photoAccessHelper.showAssetsCreationDialog`（系统弹窗确认，免权限，API 12+）；若该 API 不可用，则申请 `ohos.permission.WRITE_IMAGEVIDEO` 后 `PhotoAccessHelper.createAsset` 写入。
  3. toast 提示成功/失败。
- 查看器底部同样加"保存到相册"按钮，便于发现（长按是快捷入口，按钮是显式入口）。

**点赞（全屏查看器）**
- 底部操作区加 ❤️ 按钮 + 点赞数。点击切换：
  - 未点赞 → 新建 `PhotoComment{photoId, isLike:true}`；本地 @State 立即 +1 并标记已赞，异步推云。
  - 已点赞 → 删除自己的点赞记录；本地立即回退，异步推云。
- 点赞数/是否已赞：`getPhotoComments(photoId)` 实时统计。

**评论（全屏查看器）**
- 底部评论区：滚动列表显示评论（成员 avatar+name + content + 相对时间），自己（creatorId === 当前 memberId）的评论带删除按钮。
- 输入框 + 发送按钮；发送 → 新建 `PhotoComment{photoId, isLike:false, content}`，本地追加 + 推云。
- 删除自己的评论 → 墓碑删除 + 本地移除。

**数据加载**
- AlbumPage.aboutToAppear 的 `pullPhotos` 扩展为同时拉 `Photo` 与 `PhotoComment`（或新增 `pullPhotoInteractions`），合并后刷新。
- 查看器打开时从 `getPhotoComments(viewerPhoto.id)` 取互动数据。

## 4. 云端改动（需重新部署 + AGC 控制台建表）

| 文件 | 改动 |
|------|------|
| `cloud/push-data/index.js` | `ALLOWED_TYPES` 加 `'PhotoComment'` |
| `cloud/pull-data/index.js` | `ALL_TYPES` 加 `'PhotoComment'`；`VISIBILITY_TYPES` 加 `'PhotoComment'` |
| `cloud/push-data/shared/db.js`（含各函数包内 shared 副本） | `SCHEMA_FIELDS.PhotoComment = [id, familyId, photoId, creatorId, visibility, visibleMembers, version, createdAt, updatedAt, isDeleted, isLike, content]` |
| **AGC 控制台** | 创建 `PhotoComment` 对象类型（导入 schema JSON，见仓库 `agc-clouddb-object-types.json` 同格式） |

注意：`cloud/push-data/shared/db.js` 与各函数包内的 `shared/` 是复制关系，改完源文件需重新同步到各函数目录再打包部署。部署方式沿用现有 deploy 流程（如 `cloud/deploy.cjs`）。

## 5. 不做的事（YAGNI）

- 评论编辑、图片评论、评论/点赞通知推送、评论数角标、点赞排行榜。

## 6. 测试计划

- **云端**：本地脚本验证 PhotoComment 的 upsert/delete/query（复用 cloud/ 下的 test-*.cjs 模式）。
- **客户端**：`hvigorw assembleHap` 构建通过；模拟器/真机手测：
  1. 长按网格照片 → 系统相册出现该照片。
  2. 点赞 → 数字 +1、❤️ 高亮；取消 → 复原。
  3. 发评论 → 列表出现；删除自己的评论 → 消失。
  4. 双设备：A 上传照片（FAMILY），B 点赞评论，A 刷新后可见；SELECTED/PRIVATE 照片互动只对有权成员可见。
  5. 并发：A、B 同时点赞同一张照片，两边都成功（无覆盖）。
