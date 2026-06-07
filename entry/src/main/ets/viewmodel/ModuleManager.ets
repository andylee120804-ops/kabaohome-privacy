/**
 * 模块管理器 - 管理用户开启的功能模块
 */
import { ModuleId, Visibility, MAX_CUSTOM_TABS } from '../common/Constants';

/**
 * 模块定义
 */
export interface ModuleDef {
  id: ModuleId;
  name: string;
  icon: string;
  defaultVisibility: Visibility;
  isAvailable: boolean;
  description: string;
}

/**
 * 所有可用模块
 */
export const ALL_MODULES: ModuleDef[] = [
  {
    id: ModuleId.PERIOD,
    name: '我的姨妈',
    icon: '🌸',
    defaultVisibility: Visibility.PRIVATE,
    isAvailable: true,
    description: '周期记录·预测·提醒·怀孕几率'
  },
  {
    id: ModuleId.HEALTH,
    name: '健康用药',
    icon: '💊',
    defaultVisibility: Visibility.FAMILY,
    isAvailable: true,
    description: '吃药提醒·健康指标·复诊'
  },
  {
    id: ModuleId.KIDS,
    name: '孩子事项',
    icon: '📚',
    defaultVisibility: Visibility.SELECTED,
    isAvailable: true,
    description: '上学·活动·家长会·成长记录'
  },
  {
    id: ModuleId.REMINDER,
    name: '家庭提醒',
    icon: '📋',
    defaultVisibility: Visibility.FAMILY,
    isAvailable: true,
    description: '生日·纪念日·家庭活动·购物·缴费'
  },
  {
    id: ModuleId.LOCATION,
    name: '位置共享',
    icon: '📍',
    defaultVisibility: Visibility.FAMILY,
    isAvailable: true,
    description: '家人位置·到校通知'
  },
  {
    id: ModuleId.ALBUM,
    name: '家庭相册',
    icon: '📷',
    defaultVisibility: Visibility.FAMILY,
    isAvailable: true,
    description: '照片·重要时刻'
  },
  {
    id: ModuleId.SHOPPING,
    name: '购物清单',
    icon: '🛒',
    defaultVisibility: Visibility.FAMILY,
    isAvailable: false,
    description: '已合并到提醒中心'
  },
  {
    id: ModuleId.MEMO,
    name: '家庭备忘',
    icon: '📝',
    defaultVisibility: Visibility.SELECTED,
    isAvailable: true,
    description: '密码·证件·常用信息'
  },
  {
    id: ModuleId.ACCOUNTING,
    name: '家庭记账',
    icon: '💰',
    defaultVisibility: Visibility.FAMILY,
    isAvailable: true,
    description: '收支记录·分类统计·月度报表'
  }
];

/**
 * 模块管理器
 */
export class ModuleManager {
  private static instance: ModuleManager | null = null;
  private enabledModules: ModuleId[] = [];

  private constructor() {}

  static getInstance(): ModuleManager {
    if (!ModuleManager.instance) {
      ModuleManager.instance = new ModuleManager();
    }
    return ModuleManager.instance;
  }

  /**
   * 启用模块
   */
  enableModule(moduleId: ModuleId): boolean {
    if (this.enabledModules.length >= MAX_CUSTOM_TABS) {
      return false;
    }
    if (this.enabledModules.includes(moduleId)) {
      return true;
    }
    this.enabledModules.push(moduleId);
    return true;
  }

  /**
   * 禁用模块
   */
  disableModule(moduleId: ModuleId): void {
    this.enabledModules = this.enabledModules.filter(id => id !== moduleId);
  }

  /**
   * 获取已启用的模块
   */
  getEnabledModules(): ModuleId[] {
    return [...this.enabledModules];
  }

  /**
   * 模块是否已启用
   */
  isEnabled(moduleId: ModuleId): boolean {
    return this.enabledModules.includes(moduleId);
  }

  /**
   * 是否还能启用更多模块
   */
  canEnableMore(): boolean {
    return this.enabledModules.length < MAX_CUSTOM_TABS;
  }

  /**
   * 获取模块定义
   */
  static getModuleDef(moduleId: ModuleId): ModuleDef | undefined {
    return ALL_MODULES.find(m => m.id === moduleId);
  }
}
