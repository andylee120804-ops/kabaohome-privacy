# Findings

## 可见性模型现状
- `BaseRecord` 定义了 `visibility` (PRIVATE/SELECTED/FAMILY) 和 `visibleMembers[]`
- 写入时会设置这些字段（如 HealthViewModel 服药日志=FAMILY，PeriodViewModel=PRIVATE）
- 但 **LocalDbService 所有 getter 方法只按 familyId 过滤，完全不检查 visibility**
- 导致所有记录全员可见，visibility 设置形同虚设

## 详情视图现状
- 只有 KidsPage 有独立的详情弹窗（`EventDetailOverlay`/`GrowthDetailOverlay`）
- 所有其他页面：点击 = 编辑弹窗，长按 = 删除
- 非创建人点击无响应（不会看到任何内容）

## 关键文件
- `LocalDbService.ets` — 所有数据读取方法需要加 visibility 过滤
- `Utils.ets` — 可放 `filterByVisibility()` 工具函数
- `KidsPage.ets` — 详情弹窗的参考模板
- `BaseRecord.ets` — `creatorId`, `visibility`, `visibleMembers` 字段定义
