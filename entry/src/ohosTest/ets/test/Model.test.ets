/**
 * Model 数据模型单元测试
 * 验证 BaseRecord 及所有数据模型的默认值、继承关系
 */
import { describe, it, expect } from '@ohos/hypium';
import { BaseRecord } from '../../../main/ets/model/BaseRecord';
import { PeriodRecord, IntimacyRecord } from '../../../main/ets/model/PeriodRecord';
import { Medication, MedicationLog } from '../../../main/ets/model/Medication';
import { KidEvent, GrowthRecord } from '../../../main/ets/model/KidEvent';
import { FamilyMember } from '../../../main/ets/model/FamilyMember';
import { Family } from '../../../main/ets/model/Family';
import { FamilyInvitation } from '../../../main/ets/model/FamilyInvitation';
import { Reminder } from '../../../main/ets/model/Reminder';
import { ShoppingItem } from '../../../main/ets/model/ShoppingItem';
import { Photo } from '../../../main/ets/model/Photo';
import { Memo } from '../../../main/ets/model/Memo';
import { HealthMetric } from '../../../main/ets/model/HealthMetric';
import { AccountingRecord } from '../../../main/ets/model/AccountingRecord';
import { Visibility, MemberRole, FontSizeMode, PregnancyRisk } from '../../../main/ets/common/Constants';

export default function modelTest() {
  describe('Model 数据模型', () => {

    // ========== BaseRecord 基类 ==========
    describe('BaseRecord 基类默认值', () => {

      it('id 默认为空字符串', 0, () => {
        expect(new BaseRecord().id).assertEqual('');
      });

      it('version 默认为 1', 0, () => {
        expect(new BaseRecord().version).assertEqual(1);
      });

      it('visibility 默认为 PRIVATE', 0, () => {
        expect(new BaseRecord().visibility).assertEqual(Visibility.PRIVATE);
      });

      it('visibleMembers 默认为空数组', 0, () => {
        expect(new BaseRecord().visibleMembers.length).assertEqual(0);
      });

      it('familyId 默认为空字符串', 0, () => {
        expect(new BaseRecord().familyId).assertEqual('');
      });

      it('creatorId 默认为空字符串', 0, () => {
        expect(new BaseRecord().creatorId).assertEqual('');
      });

      it('createdAt 默认为空字符串', 0, () => {
        expect(new BaseRecord().createdAt).assertEqual('');
      });

      it('updatedAt 默认为空字符串', 0, () => {
        expect(new BaseRecord().updatedAt).assertEqual('');
      });
    });

    // ========== PeriodRecord ==========
    describe('PeriodRecord', () => {
      const r = new PeriodRecord();

      it('应继承 BaseRecord（有 id 字段）', 0, () => {
        expect(Object.keys(r).includes('id')).assertTrue();
        expect(r.version).assertEqual(1);
      });

      it('默认 cycleLength = 28', 0, () => {
        expect(r.cycleLength).assertEqual(28);
      });

      it('默认 duration = 5', 0, () => {
        expect(r.duration).assertEqual(5);
      });

      it('symptoms 默认为空数组', 0, () => {
        expect(r.symptoms.length).assertEqual(0);
      });

      it('mood 默认为空字符串', 0, () => {
        expect(r.mood).assertEqual('');
      });
    });

    // ========== IntimacyRecord ==========
    describe('IntimacyRecord', () => {
      const r = new IntimacyRecord();

      it('应继承 BaseRecord', 0, () => {
        expect(r.version).assertEqual(1);
      });

      it('默认 pregnancyRisk = LOW', 0, () => {
        expect(r.pregnancyRisk).assertEqual(PregnancyRisk.LOW);
      });
    });

    // ========== FamilyMember ==========
    describe('FamilyMember', () => {
      const m = new FamilyMember();

      it('默认 role = DAD', 0, () => {
        expect(m.role).assertEqual(MemberRole.DAD);
      });

      it('默认 isCustodial = false', 0, () => {
        expect(m.isCustodial).assertFalse();
      });

      it('默认 fontSizeMode = NORMAL', 0, () => {
        expect(m.fontSizeMode).assertEqual(FontSizeMode.NORMAL);
      });

      it('默认 color 不应为空', 0, () => {
        expect(m.color.length > 0).assertTrue();
      });
    });

    // ========== Family ==========
    describe('Family', () => {
      const f = new Family();

      it('应有基本字段', 0, () => {
        expect(Object.keys(f).includes('id')).assertTrue();
        expect(Object.keys(f).includes('name')).assertTrue();
        expect(Object.keys(f).includes('inviteCode')).assertTrue();
      });
    });

    // ========== FamilyInvitation ==========
    describe('FamilyInvitation', () => {
      const inv = new FamilyInvitation();

      it('应有 familyId 和 inviteCode 字段', 0, () => {
        expect(Object.keys(inv).includes('familyId')).assertTrue();
        expect(Object.keys(inv).includes('inviteCode')).assertTrue();
      });
    });

    // ========== Medication ==========
    describe('Medication', () => {
      const m = new Medication();

      it('默认 isActive 应为预期值', 0, () => {
        expect(typeof m.isActive).assertEqual('boolean');
      });

      it('timeSlots 默认为空数组', 0, () => {
        expect(m.timeSlots.length).assertEqual(0);
      });
    });

    // ========== MedicationLog ==========
    describe('MedicationLog', () => {
      const log = new MedicationLog();

      it('应有关联 medicationId', 0, () => {
        expect(Object.keys(log).includes('medicationId')).assertTrue();
      });

      it('应有 takenAt 时间字段', 0, () => {
        expect(Object.keys(log).includes('takenAt')).assertTrue();
      });
    });

    // ========== KidEvent ==========
    describe('KidEvent', () => {
      const e = new KidEvent();

      it('应有 title 字段', 0, () => {
        expect(Object.keys(e).includes('title')).assertTrue();
      });

      it('应有 forMemberId 关联字段', 0, () => {
        expect(Object.keys(e).includes('forMemberId')).assertTrue();
      });
    });

    // ========== GrowthRecord ==========
    describe('GrowthRecord', () => {
      const r = new GrowthRecord();

      it('应有 height / weight 字段', 0, () => {
        expect(Object.keys(r).includes('height')).assertTrue();
        expect(Object.keys(r).includes('weight')).assertTrue();
      });

      it('默认数值不应为负', 0, () => {
        expect(r.height >= 0).assertTrue();
        expect(r.weight >= 0).assertTrue();
      });
    });

    // ========== Reminder ==========
    describe('Reminder', () => {
      const r = new Reminder();

      it('默认 isCompleted = false', 0, () => {
        expect(r.isCompleted).assertFalse();
      });

      it('应有 dueTime 字段', 0, () => {
        expect(Object.keys(r).includes('dueTime')).assertTrue();
      });
    });

    // ========== ShoppingItem ==========
    describe('ShoppingItem', () => {
      const item = new ShoppingItem();

      it('应有 name 字段', 0, () => {
        expect(Object.keys(item).includes('name')).assertTrue();
      });

      it('默认 isPurchased 应为 false', 0, () => {
        expect(item.isPurchased).assertFalse();
      });
    });

    // ========== Photo ==========
    describe('Photo', () => {
      const p = new Photo();

      it('应有 url 字段', 0, () => {
        expect(Object.keys(p).includes('url')).assertTrue();
      });
    });

    // ========== Memo ==========
    describe('Memo', () => {
      const m = new Memo();

      it('应有 content 字段', 0, () => {
        expect(Object.keys(m).includes('content')).assertTrue();
      });
    });

    // ========== HealthMetric ==========
    describe('HealthMetric', () => {
      const h = new HealthMetric();

      it('应有 type 和 value 字段', 0, () => {
        expect(Object.keys(h).includes('type')).assertTrue();
        expect(Object.keys(h).includes('value')).assertTrue();
      });
    });

    // ========== AccountingRecord ==========
    describe('AccountingRecord', () => {
      const a = new AccountingRecord();

      it('应有 amount（金额）字段', 0, () => {
        expect(Object.keys(a).includes('amount')).assertTrue();
      });

      it('应有 type（收支类型）字段', 0, () => {
        expect(Object.keys(a).includes('type')).assertTrue();
      });

      it('默认 amount 不应为 NaN', 0, () => {
        expect(Number.isNaN(a.amount)).assertFalse();
      });
    });

    // ========== 跨模型一致性 ==========
    describe('跨模型版本字段', () => {

      it('所有继承 BaseRecord 的类都应有 version 字段', 0, () => {
        const records = [
          new PeriodRecord(),
          new IntimacyRecord(),
          new HealthMetric(),
          new KidEvent(),
          new GrowthRecord(),
          new Medication(),
          new MedicationLog(),
          new Reminder(),
          new ShoppingItem(),
          new Photo(),
          new Memo(),
          new AccountingRecord()
        ];
        for (const r of records) {
          expect(Object.keys(r).includes('version')).assertTrue();
          expect(Object.keys(r).includes('id')).assertTrue();
          expect(Object.keys(r).includes('familyId')).assertTrue();
        }
      });
    });

  });
}
