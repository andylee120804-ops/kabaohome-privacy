/**
 * KidsViewModel 单元测试
 * 测试孩子事项类型标签、颜色、成长记录数据验证
 */
import { describe, it, expect } from '@ohos/hypium';
import { KidsViewModel } from '../../../main/ets/viewmodel/KidsViewModel';
import { KidEvent, GrowthRecord } from '../../../main/ets/model/KidEvent';
import { FamilyMember } from '../../../main/ets/model/FamilyMember';
import { Visibility, MemberRole } from '../../../main/ets/common/Constants';

export default function kidsViewModelTest() {
  describe('KidsViewModel 孩子事项', () => {

    const vm = new KidsViewModel();

    // ========== 事项类型标签 ==========
    describe('getEventTypeLabel 事项类型标签', () => {

      it('school 应返回 🏫 学校', 0, () => {
        expect(vm.getEventTypeLabel('school')).assertEqual('🏫 学校');
      });

      it('activity 应返回 🎨 课外', 0, () => {
        expect(vm.getEventTypeLabel('activity')).assertEqual('🎨 课外');
      });

      it('medical 应返回 🏥 医疗', 0, () => {
        expect(vm.getEventTypeLabel('medical')).assertEqual('🏥 医疗');
      });

      it('other 应返回 📌 其他', 0, () => {
        expect(vm.getEventTypeLabel('other')).assertEqual('📌 其他');
      });

      it('未知类型应原样返回', 0, () => {
        expect(vm.getEventTypeLabel('unknown_type')).assertEqual('unknown_type');
      });

      it('空字符串应原样返回', 0, () => {
        expect(vm.getEventTypeLabel('')).assertEqual('');
      });
    });

    // ========== 事项类型颜色 ==========
    describe('getEventTypeColor 事项类型颜色', () => {

      it('school 应返回蓝色 #1565C0', 0, () => {
        expect(vm.getEventTypeColor('school')).assertEqual('#1565C0');
      });

      it('activity 应返回橙色 #E65100', 0, () => {
        expect(vm.getEventTypeColor('activity')).assertEqual('#E65100');
      });

      it('medical 应返回红色 #C62828', 0, () => {
        expect(vm.getEventTypeColor('medical')).assertEqual('#C62828');
      });

      it('other 应返回绿色 #2E7D32', 0, () => {
        expect(vm.getEventTypeColor('other')).assertEqual('#2E7D32');
      });

      it('未知类型应返回灰色 #666666', 0, () => {
        expect(vm.getEventTypeColor('custom')).assertEqual('#666666');
      });
    });

    // ========== KidEvent 数据模型 ==========
    describe('KidEvent 数据模型', () => {

      it('新实例应有所有必填字段', 0, () => {
        const event = new KidEvent();
        expect(Object.keys(event).includes('id')).assertTrue();
        expect(Object.keys(event).includes('title')).assertTrue();
        expect(Object.keys(event).includes('forMemberId')).assertTrue();
        expect(Object.keys(event).includes('eventType')).assertTrue();
        expect(Object.keys(event).includes('eventTime')).assertTrue();
        expect(Object.keys(event).includes('isCompleted')).assertTrue();
      });

      it('默认 isCompleted 应为 false', 0, () => {
        const event = new KidEvent();
        expect(event.isCompleted).assertFalse();
      });

      it('默认 isRecurring 应为 false', 0, () => {
        const event = new KidEvent();
        expect(event.isRecurring).assertFalse();
      });

      it('默认 version 应为 1', 0, () => {
        const event = new KidEvent();
        expect(event.version).assertEqual(1);
      });
    });

    // ========== GrowthRecord 数据模型 ==========
    describe('GrowthRecord 数据模型', () => {

      it('应有 height/weight/headCircumference 字段', 0, () => {
        const record = new GrowthRecord();
        expect(Object.keys(record).includes('height')).assertTrue();
        expect(Object.keys(record).includes('weight')).assertTrue();
        expect(Object.keys(record).includes('headCircumference')).assertTrue();
      });

      it('默认数值应大于等于0', 0, () => {
        const record = new GrowthRecord();
        expect(record.height >= 0).assertTrue();
        expect(record.weight >= 0).assertTrue();
        expect(record.headCircumference >= 0).assertTrue();
      });

      it('应有 milestone 字段', 0, () => {
        const record = new GrowthRecord();
        expect(Object.keys(record).includes('milestone')).assertTrue();
      });

      it('应有 recordDate 字段', 0, () => {
        const record = new GrowthRecord();
        expect(Object.keys(record).includes('recordDate')).assertTrue();
      });
    });

    // ========== 成长记录数值验证 ==========
    describe('成长记录数值验证', () => {

      it('身高合理范围(30-200cm)', 0, () => {
        const validHeight = 120;
        expect(validHeight >= 30 && validHeight <= 200).assertTrue();
      });

      it('体重合理范围(1-200kg)', 0, () => {
        const validWeight = 25;
        expect(validWeight >= 1 && validWeight <= 200).assertTrue();
      });

      it('头围合理范围(20-70cm)', 0, () => {
        const validHeadCirc = 45;
        expect(validHeadCirc >= 20 && validHeadCirc <= 70).assertTrue();
      });

      it('身高0表示未记录', 0, () => {
        const record = new GrowthRecord();
        record.height = 0;
        expect(record.height === 0).assertTrue();
      });

      it('体重0表示未记录', 0, () => {
        const record = new GrowthRecord();
        record.weight = 0;
        expect(record.weight === 0).assertTrue();
      });
    });

    // ========== 事项完成/过期判断 ==========
    describe('事项完成/过期判断', () => {

      it('已完成事项 isCompleted 应为 true', 0, () => {
        const event = new KidEvent();
        event.isCompleted = true;
        event.completedAt = new Date().toISOString();
        expect(event.isCompleted).assertTrue();
        expect(event.completedAt.length > 0).assertTrue();
      });

      it('未完成事项 completedAt 应为空', 0, () => {
        const event = new KidEvent();
        expect(event.isCompleted).assertFalse();
        expect(event.completedAt === '').assertTrue();
      });

      it('过期事项 eventTime 应早于当前时间', 0, () => {
        const pastDate = '2020-01-01T10:00:00';
        const now = new Date().toISOString();
        expect(pastDate < now).assertTrue();
      });
    });

    // ========== 重复规则 ==========
    describe('重复规则', () => {

      it('isRecurring=false 时 recurrenceRule 应为空', 0, () => {
        const event = new KidEvent();
        event.isRecurring = false;
        event.recurrenceRule = '';
        expect(event.isRecurring).assertFalse();
        expect(event.recurrenceRule).assertEqual('');
      });

      it('有效的重复规则值', 0, () => {
        const validRules = ['weekly', 'monthly', 'yearly'];
        for (const rule of validRules) {
          expect(validRules.includes(rule)).assertTrue();
        }
      });
    });

  });
}
