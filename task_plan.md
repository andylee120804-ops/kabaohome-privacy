# Task Plan: 全局可见性过滤 + 点击查看详情改造

## 目标
1. **可见性过滤**：只有被分享的人才能看到记录（在全应用范围应用 `visibility`/`visibleMembers` 过滤）
2. **点击查看详情**：所有记录的点击行为改为弹出详情弹窗，而非直接编辑
3. **仅创建人可编辑/删除**：编辑和删除按钮只在详情弹窗中对创建人显示

## 受影响的页面

| 页面 | 记录类型 | 当前点击行为 | 需要改造 |
|------|---------|-------------|---------|
| KidsPage | KidEvent / GrowthRecord | ✅ 已有详情弹窗 | 仅需加可见性过滤 |
| ReminderPage | Reminder | 点击标记完成，长按编辑 | 加详情弹窗 + 可见性过滤 |
| HealthPage | Medication / HealthMetric | 点击进编辑 | 加详情弹窗 + 可见性过滤 |
| AccountingPage | AccountingRecord | 点击进编辑 | 加详情弹窗 + 可见性过滤 |
| MemoPage | Memo | 点击进编辑 | 加详情弹窗 + 可见性过滤 |
| AlbumPage | Photo | 点击进编辑 | 加详情弹窗 + 可见性过滤 |
| Index.ets | TodoItem | 点击跳转页面 | 不变（这是导航聚合页） |
| PeriodPage | PeriodRecord | 直接按钮操作 | 记录类型特殊，按钮操作保留 |
| LocationPage | LocationPlace | 直接编辑/删除按钮 | 加创建者检查 |

## 阶段划分

### Phase 1: 创建可见性过滤工具 ✅
- 在 `Utils.ets` 或新建 `VisibilityFilter.ets` 中添加 `filterByVisibility()` 函数
- 逻辑：PRIVATE → 仅创建者 / SELECTED → 创建者+指定成员 / FAMILY → 全员

### Phase 2: 在 LocalDbService 加过滤方法
- 添加 `getVisibleRecords<T>()` 通用方法
- 或者在各 getter 中内联过滤

### Phase 3: 各页面加详情弹窗 + 可见性过滤
- 3a: KidsPage — 加可见性过滤
- 3b: HealthPage — 加详情弹窗 + 过滤
- 3c: MemoPage — 加详情弹窗 + 过滤
- 3d: AccountingPage — 加详情弹窗 + 过滤
- 3e: AlbumPage — 加详情弹窗 + 过滤
- 3f: ReminderPage — 加详情弹窗 + 过滤
- 3g: LocationPage — 加创建者检查

### Phase 4: 验证
- 检查 lint 错误
- 确认所有改动一致性
