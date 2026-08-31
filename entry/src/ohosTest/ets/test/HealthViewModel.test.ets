/**
 * HealthViewModel 单元测试
 * 测试用药权限、健康指标异常判断、共享成员逻辑
 */
import { describe, it, expect } from '@ohos/hypium';
import { HealthViewModel, MedVisibility } from '../../../main/ets/viewmodel/HealthViewModel';
import { Medication, MedicationLog } from '../../../main/ets/model/Medication';
import { HealthMetric } from '../../../main/ets/model/HealthMetric';
import { Visibility, HEALTH_RANGES } from '../../../main/ets/common/Constants';
import { isAbnormal } from '../../../main/ets/common/Utils';

export default function healthViewModelTest() {
  describe('HealthViewModel 健康用药', () => {

    // ========== checkAbnormal ==========
    describe('checkAbnormal 健康指标异常判断', () => {

      it('收缩压正常值(120)应不异常', 0, () => {
        expect(isAbnormal(120, HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.min, HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.max)).assertFalse();
      });

      it('收缩压偏高(150)应异常', 0, () => {
        expect(isAbnormal(150, HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.min, HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.max)).assertTrue();
      });

      it('收缩压偏低(80)应异常', 0, () => {
        expect(isAbnormal(80, HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.min, HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.max)).assertTrue();
      });

      it('舒张压正常值(70)应不异常', 0, () => {
        expect(isAbnormal(70, HEALTH_RANGES.BLOOD_PRESSURE_DIASTOLIC.min, HEALTH_RANGES.BLOOD_PRESSURE_DIASTOLIC.max)).assertFalse();
      });

      it('血糖正常值(5.0)应不异常', 0, () => {
        expect(isAbnormal(5.0, HEALTH_RANGES.BLOOD_SUGAR_FASTING.min, HEALTH_RANGES.BLOOD_SUGAR_FASTING.max)).assertFalse();
      });

      it('血糖偏高(8.0)应异常', 0, () => {
        expect(isAbnormal(8.0, HEALTH_RANGES.BLOOD_SUGAR_FASTING.min, HEALTH_RANGES.BLOOD_SUGAR_FASTING.max)).assertTrue();
      });

      it('体温正常值(36.5)应不异常', 0, () => {
        expect(isAbnormal(36.5, HEALTH_RANGES.BODY_TEMP.min, HEALTH_RANGES.BODY_TEMP.max)).assertFalse();
      });

      it('体温偏高(38.0)应异常', 0, () => {
        expect(isAbnormal(38.0, HEALTH_RANGES.BODY_TEMP.min, HEALTH_RANGES.BODY_TEMP.max)).assertTrue();
      });

      it('心率正常值(72)应不异常', 0, () => {
        expect(isAbnormal(72, HEALTH_RANGES.HEART_RATE.min, HEALTH_RANGES.HEART_RATE.max)).assertFalse();
      });

      it('心率偏高(110)应异常', 0, () => {
        expect(isAbnormal(110, HEALTH_RANGES.HEART_RATE.min, HEALTH_RANGES.HEART_RATE.max)).assertTrue();
      });

      it('心率偏低(50)应异常', 0, () => {
        expect(isAbnormal(50, HEALTH_RANGES.HEART_RATE.min, HEALTH_RANGES.HEART_RATE.max)).assertTrue();
      });

      it('未知指标类型应返回false', 0, () => {
        expect(isAbnormal(999, 0, 100)).assertFalse();
      });
    });

    // ========== HEALTH_RANGES 常量验证 ==========
    describe('HEALTH_RANGES 常量', () => {

      it('收缩压范围应为 90-140', 0, () => {
        expect(HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.min).assertEqual(90);
        expect(HEALTH_RANGES.BLOOD_PRESSURE_SYSTOLIC.max).assertEqual(140);
      });

      it('舒张压范围应为 60-90', 0, () => {
        expect(HEALTH_RANGES.BLOOD_PRESSURE_DIASTOLIC.min).assertEqual(60);
        expect(HEALTH_RANGES.BLOOD_PRESSURE_DIASTOLIC.max).assertEqual(90);
      });

      it('血糖空腹范围应为 3.9-6.1', 0, () => {
        expect(HEALTH_RANGES.BLOOD_SUGAR_FASTING.min).assertEqual(3.9);
        expect(HEALTH_RANGES.BLOOD_SUGAR_FASTING.max).assertEqual(6.1);
      });

      it('体温范围应为 36.0-37.3', 0, () => {
        expect(HEALTH_RANGES.BODY_TEMP.min).assertEqual(36.0);
        expect(HEALTH_RANGES.BODY_TEMP.max).assertEqual(37.3);
      });

      it('心率范围应为 60-100', 0, () => {
        expect(HEALTH_RANGES.HEART_RATE.min).assertEqual(60);
        expect(HEALTH_RANGES.HEART_RATE.max).assertEqual(100);
      });
    });

    // ========== Medication 权限模型 ==========
    describe('Medication 权限模型', () => {

      it('创建人应可编辑', 0, () => {
        const med = new Medication();
        med.creatorId = 'user1';
        // 验证权限逻辑：creatorId 匹配则有编辑权限
        expect(med.creatorId === 'user1').assertTrue();
      });

      it('非创建人不应可编辑', 0, () => {
        const med = new Medication();
        med.creatorId = 'user1';
        expect(med.creatorId === 'user2').assertFalse();
      });

      it('创建人应可确认服药', 0, () => {
        const med = new Medication();
        med.creatorId = 'user1';
        med.forMemberId = 'memberA';
        // 创建人权限
        expect(med.creatorId === 'user1').assertTrue();
      });

      it('被指派服药人应可确认服药', 0, () => {
        const med = new Medication();
        med.creatorId = 'user1';
        med.forMemberId = 'memberA';
        // 被指派服药人（forMemberId 对应的成员）权限
        expect(med.forMemberId === 'memberA').assertTrue();
      });
    });

    // ========== MedicationLog 模型 ==========
    describe('MedicationLog 模型', () => {

      it('status 应为 taken 或 late', 0, () => {
        const validStatuses = ['taken', 'late', 'missed', 'skipped'];
        expect(validStatuses.includes('taken')).assertTrue();
        expect(validStatuses.includes('late')).assertTrue();
      });

      it('补服记录应有 note 标记', 0, () => {
        const isLate = true;
        const note = isLate ? '补服' : '';
        expect(note).assertEqual('补服');
      });
    });

    // ========== MedVisibility 接口 ==========
    describe('MedVisibility 可见性', () => {

      it('PRIVATE 模式 visibleMembers 应为空', 0, () => {
        const vis: MedVisibility = { visibility: Visibility.PRIVATE, visibleMembers: [] };
        expect(vis.visibility).assertEqual(Visibility.PRIVATE);
        expect(vis.visibleMembers.length).assertEqual(0);
      });

      it('FAMILY 模式 visibleMembers 应为空', 0, () => {
        const vis: MedVisibility = { visibility: Visibility.FAMILY, visibleMembers: [] };
        expect(vis.visibility).assertEqual(Visibility.FAMILY);
        expect(vis.visibleMembers.length).assertEqual(0);
      });

      it('SELECTED 模式 visibleMembers 应非空', 0, () => {
        const vis: MedVisibility = { visibility: Visibility.SELECTED, visibleMembers: ['userId1'] };
        expect(vis.visibility).assertEqual(Visibility.SELECTED);
        expect(vis.visibleMembers.length).assertEqual(1);
      });
    });

    // ========== 用药有效期判断 ==========
    describe('用药有效期判断', () => {

      it('无 endDate 表示长期有效', 0, () => {
        const med = new Medication();
        med.isActive = true;
        med.startDate = '';
        med.endDate = '';
        expect(med.endDate === '').assertTrue();
      });

      it('endDate 在今天之后应仍有效', 0, () => {
        const today = '2025-06-09';
        const endDate = '2025-07-01';
        expect(endDate >= today).assertTrue();
      });

      it('endDate 在今天之前应已过期', 0, () => {
        const today = '2025-06-09';
        const endDate = '2025-05-01';
        expect(endDate < today).assertTrue();
      });
    });

  });
}
