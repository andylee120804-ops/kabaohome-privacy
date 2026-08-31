/**
 * Constants 常量与枚举单元测试
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  APP_NAME,
  APP_BUNDLE_NAME,
  MAX_CUSTOM_TABS,
  Visibility,
  MemberRole,
  FontSizeMode,
  ModuleId,
  PregnancyRisk,
  MEMBER_COLORS,
  HEALTH_RANGES,
  SYNC_CONFIG
} from '../../../main/ets/common/Constants';

export default function constantsTest() {
  describe('Constants 常量验证', () => {

    it('APP_NAME 应在不为空', 0, () => {
      expect(APP_NAME.length > 0).assertTrue();
    });

    it('APP_BUNDLE_NAME 应符合包名格式', 0, () => {
      expect(APP_BUNDLE_NAME).assertEqual('com.family.kabaohome');
    });

    it('MAX_CUSTOM_TABS 应为 3', 0, () => {
      expect(MAX_CUSTOM_TABS).assertEqual(3);
    });

    // ---------- 枚举值唯一性 ----------
    it('Visibility 枚举值应唯一', 0, () => {
      const vals = Object.values(Visibility);
      expect(new Set(vals).size).assertEqual(vals.length);
    });

    it('MemberRole 应包含4种角色', 0, () => {
      expect(Object.values(MemberRole).length).assertEqual(4);
    });

    it('FontSizeMode 应包含 NORMAL 和 LARGE', 0, () => {
      expect(FontSizeMode.NORMAL).assertEqual('NORMAL');
      expect(FontSizeMode.LARGE).assertEqual('LARGE');
    });

    it('ModuleId 应包含10个模块', 0, () => {
      expect(Object.values(ModuleId).length).assertEqual(10);
    });

    it('PregnancyRisk 值应递增', 0, () => {
      expect(PregnancyRisk.LOW).assertEqual('LOW');
      expect(PregnancyRisk.MEDIUM).assertEqual('MEDIUM');
      expect(PregnancyRisk.HIGH).assertEqual('HIGH');
    });

    // ---------- MEMBER_COLORS ----------
    it('MEMBER_COLORS 应有8种颜色', 0, () => {
      expect(MEMBER_COLORS.length).assertEqual(8);
    });

    it('MEMBER_COLORS 均为有效十六进制颜色', 0, () => {
      for (const c of MEMBER_COLORS) {
        expect(/^#[0-9A-Fa-f]{6}$/.test(c)).assertTrue();
      }
    });

    it('MEMBER_COLORS 颜色应无重复', 0, () => {
      expect(new Set(MEMBER_COLORS).size).assertEqual(MEMBER_COLORS.length);
    });

    // ---------- HEALTH_RANGES ----------
    it('HEALTH_RANGES 血压收缩压 min < max', 0, () => {
      const r = HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC;
      expect(r.min < r.max).assertTrue();
    });

    it('HEALTH_RANGES 体温范围应在生理合理区间', 0, () => {
      const r = HEALTH_RANGES.BODY_TEMP;
      expect(r.min >= 30 && r.max <= 45).assertTrue();
    });

    it('HEALTH_RANGES 心率范围 min < max', 0, () => {
      const r = HEALTH_RANGES.HEART_RATE;
      expect(r.min < r.max).assertTrue();
    });

    // ---------- SYNC_CONFIG ----------
    it('SYNC_CONFIG 重试次数应大于0', 0, () => {
      expect(SYNC_CONFIG.MAX_RETRIES > 0).assertTrue();
    });

    it('SYNC_CONFIG 最大延迟应 >= 初始延迟', 0, () => {
      expect(SYNC_CONFIG.MAX_DELAY_MS >= SYNC_CONFIG.INITIAL_DELAY_MS).assertTrue();
    });
  });
}
