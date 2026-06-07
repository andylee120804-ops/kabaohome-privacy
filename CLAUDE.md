# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 工作原则
参考学些的华为鸿蒙开发文档
发现有bug,直接修复。
多思考，充分思考方案，再行动，
交付的项目要自己先验证，而不是说功能完成了，但是都是错误和bug

## 项目信息

**名称**: 卡宝Home
**平台**: 华为鸿蒙 HarmonyOS NEXT
**语言**: ArkTS (基于TypeScript)
**框架**: ArkUI (声明式UI) + Stage模型
**后端**: 华为云 Serverless (AGC)
**IDE**: DevEco Studio (已安装在 /c/Program Files/Huawei/DevEco Studio/)

## 构建 & 运行

```bash
# 使用DevEco Studio打开项目后构建运行
# 命令行构建：
hvigorw assembleHap
# 依赖安装：
ohpm install
```

## 项目结构

```
entry/src/main/ets/
├── entryability/    # 应用入口 (EntryAbility.ets - 初始化DB + 路由判断)
├── pages/           # 16个页面
│   ├── Index.ets           # 首页(家庭总览 + 动态Tab导航)
│   ├── LoginPage.ets       # 登录(华为账号 + 家庭路由)
│   ├── PeriodPage.ets      # 姨妈周期(日历+排卵计算+啪啪记录)
│   ├── HealthPage.ets      # 健康用药(服药确认+指标记录+异常标记)
│   ├── KidsPage.ets        # 孩子事项(事件管理+成长记录)
│   ├── ReminderPage.ets    # 提醒事项(列表+月视图日历)
│   ├── NotificationCenterPage.ets # 通知中心
│   ├── LocationPage.ets    # 位置共享(地图+通知)
│   ├── AlbumPage.ets       # 家庭相册
│   ├── ShoppingPage.ets    # 购物清单(已合并到提醒中心)
│   ├── MemoPage.ets        # 家庭备忘(搜索+加密)
│   ├── AccountingPage.ets  # 家庭记账
│   ├── FamilySetupPage.ets # 创建/加入家庭(邀请码+手机号)
│   ├── SettingsPage.ets    # 我的(模块管理+成员管理)
│   ├── PreviewPage.ets     # 预览页
│   └── MapPickerPage.ets   # 地点选择
├── components/      # 6个通用UI组件
│   ├── CalendarView.ets    # 月视图日历(带标记)
│   ├── VisibilityPicker.ets # 共享范围选择器
│   ├── MemberTag.ets       # 成员标签(颜色标识)
│   ├── CardItem.ets        # 事项卡片
│   ├── EmptyState.ets      # 空状态提示
│   └── TabBar.ets          # 动态底部导航
├── model/           # 12个数据模型
│   ├── BaseRecord.ets      # 基础记录(含共享字段)
│   ├── Family.ets          # 家庭
│   ├── FamilyMember.ets    # 家庭成员
│   ├── FamilyInvitation.ets # 家庭邀请
│   ├── PeriodRecord.ets    # 周期+啪啪记录
│   ├── Medication.ets      # 用药+服药记录
│   ├── HealthMetric.ets    # 健康指标
│   ├── KidEvent.ets        # 孩子事项+成长记录
│   ├── Reminder.ets        # 提醒事项
│   ├── ShoppingItem.ets    # 购物清单
│   ├── Photo.ets           # 照片
│   └── Memo.ets            # 备忘
├── viewmodel/       # 6个业务逻辑
│   ├── ModuleManager.ets   # 模块管理
│   ├── FamilyViewModel.ets # 家庭数据
│   ├── PeriodViewModel.ets # 周期计算+排卵预测
│   ├── HealthViewModel.ets # 健康用药
│   └── KidsViewModel.ets   # 孩子事项
├── service/         # 4个数据服务
│   ├── LocalDbService.ets  # 本地存储(Preferences)
│   ├── AuthService.ets     # 认证+家庭管理
│   ├── ReminderService.ets # 系统提醒
│   └── CloudService.ets    # 云端同步(V1桩实现)
└── common/          # 常量 & 工具
    ├── Constants.ets       # 枚举+配置
    └── Utils.ets           # 工具函数
```

## 关键设计决策

1. **一体化模块架构** - 所有功能在一个App内，内部保持解耦
2. **10个功能模块** - 每位成员自选开启，最多5个Tab
3. **数据共享3条规则** - 选择权在创建者、家庭清单双向确认、无强制限制
4. **模块合并** - 日历合并到提醒事项、健康指标合并到健康用药、成长记录合并到孩子事项
5. **冲突解决** - 字段级合并 + 版本号校验 + 用户选择
6. **所有表统一 family_id + version 字段**
7. **V1本地优先** - 使用Preferences存储，CloudService为桩实现
8. **科学排卵计算** - Ogino-Knaus日历法，排卵日=下次经期前14天

## 设计文档

完整设计方案见: `C:\Users\Andy\.claude\plans\app-sorted-quilt.md`
