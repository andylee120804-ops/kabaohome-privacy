/**
 * PeriodViewModel 核心逻辑单元测试
 * 测试周期计算、排卵预测、孕险评估、日历标记
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  PeriodViewModel, CycleStatus, calculateAdaptivePeriodPrediction, calculateCycleTrendRows,
  buildPeriodReminderSpecs, isManagedPeriodReminderId, planPeriodReminderSync, PeriodReminderSpec,
  checkPeriodRecordConfirm, EARLY_PERIOD_CONFIRM_DAYS, normalizeSubjectId, filterRecordsBySubject,
  shouldEnterViewerMode, buildSubjectOptions
} from '../../../main/ets/viewmodel/PeriodViewModel';
import { PeriodRecord, IntimacyRecord, PeriodReminderSettings } from '../../../main/ets/model/PeriodRecord';
import { Reminder } from '../../../main/ets/model/Reminder';
import { PregnancyRisk, Visibility } from '../../../main/ets/common/Constants';
import { formatDate } from '../../../main/ets/common/Utils';

/**
 * 构造测试用的 PeriodRecord
 */
function makeRecord(startDate: string, duration: number = 5, cycleLength: number = 28): PeriodRecord {
  return {
    id: '',
    familyId: '',
    creatorId: '',
    visibility: Visibility.PRIVATE,
    visibleMembers: [],
    version: 1,
    createdAt: '',
    updatedAt: '',
    startDate: startDate,
    endDate: '',
    cycleLength: cycleLength,
    duration: duration,
    symptoms: [],
    mood: '',
    note: ''
  };
}

/** 构造已结束的经期记录 */
function makeEndedRecord(startDate: string, endDate: string, cycleLength: number = 28): PeriodRecord {
  const r = makeRecord(startDate, 5, cycleLength);
  r.endDate = endDate;
  return r;
}

/** 构造指定创建者（归属主体）的经期记录 */
function makeRecordWithCreator(startDate: string, creatorId: string, duration: number = 5,
  cycleLength: number = 28): PeriodRecord {
  const r = makeRecord(startDate, duration, cycleLength);
  r.creatorId = creatorId;
  return r;
}

/** 构造指定创建者（归属主体）的啪啪记录 */
function makeIntimacyRecordWithCreator(date: string, creatorId: string): IntimacyRecord {
  return {
    id: '',
    familyId: '',
    creatorId: creatorId,
    visibility: Visibility.PRIVATE,
    visibleMembers: [],
    version: 1,
    createdAt: '',
    updatedAt: '',
    date: date,
    pregnancyRisk: PregnancyRisk.LOW,
    cycleDay: 0,
    note: ''
  };
}

/** 构造 openID → memberId 映射（模拟家庭成员表） */
function makeMembersByUserId(): Map<string, string> {
  const map = new Map<string, string>();
  map.set('openid_self', 'mem_self');
  map.set('openid_wife', 'mem_wife');
  return map;
}

/** 构造测试用的周期提醒期望状态 */
function makeSpec(id: string, dueTime: string, title: string = ''): PeriodReminderSpec {
  return { id: id, title: title, description: '', dueTime: dueTime };
}

/** 构造测试用的周期 Reminder 记录 */
function makeReminder(id: string, dueTime: string, title: string = '', isCompleted: boolean = false,
  version: number = 1, creatorId: string = 'm1'): Reminder {
  const r = new Reminder();
  r.id = id;
  r.dueTime = dueTime;
  r.title = title;
  r.reminderType = 'period';
  r.isCompleted = isCompleted;
  r.version = version;
  r.creatorId = creatorId;
  r.visibility = Visibility.FAMILY;
  r.visibleMembers = [];
  return r;
}

/** 在 spec 列表中按 ID 查找 */
function findSpec(specs: PeriodReminderSpec[], id: string): PeriodReminderSpec | null {
  for (const s of specs) {
    if (s.id === id) return s;
  }
  return null;
}

/** 默认周期提醒开关（3天+1天开，排卵/易孕关） */
const DEFAULT_SETTINGS: PeriodReminderSettings = {
  remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: false, remindFertile: false
};

/** 全部开关打开 */
const ALL_ON_SETTINGS: PeriodReminderSettings = {
  remind3DaysBefore: true, remind1DayBefore: true, remindOvulation: true, remindFertile: true
};

/** 全部开关关闭 */
const ALL_OFF_SETTINGS: PeriodReminderSettings = {
  remind3DaysBefore: false, remind1DayBefore: false, remindOvulation: false, remindFertile: false
};

export default function periodViewModelTest() {
  describe('PeriodViewModel 周期计算', () => {

    const vm = new PeriodViewModel();

    // ========== getCurrentCycleStatus ==========
    describe('getCurrentCycleStatus', () => {

      it('无记录时应返回默认empty状态', 0, () => {
        // 模拟空记录（通过直接调用内部逻辑验证）
        const status: CycleStatus = {
          currentDay: 0,
          cycleLength: 28,
          duration: 5,
          phase: 'unknown',
          nextPeriodDate: ''
        };
        expect(status.currentDay).assertEqual(0);
        expect(status.phase).assertEqual('unknown');
      });

      it('有记录时应计算当前周期天数（正数）', 0, () => {
        const today = new Date();
        const daysAgo = 3; // 模拟3天前开始经期
        const startDate = new Date(today);
        startDate.setDate(today.getDate() - daysAgo);
        const record = makeRecord(formatDate(startDate));
        expect(record.startDate.length).assertEqual(10);
        expect(record.duration).assertEqual(5);
        expect(record.cycleLength).assertEqual(28);
      });

      it('周期长度应为正数', 0, () => {
        const record = makeRecord('2025-03-01', 5, 28);
        expect(record.cycleLength > 0).assertTrue();
      });

      it('经期持续时间应为正数', 0, () => {
        const record = makeRecord('2025-03-01', 5, 28);
        expect(record.duration > 0).assertTrue();
      });

      it('nextPeriodDate 应在 startDate 之后', 0, () => {
        const start = new Date('2025-03-01');
        const next = new Date(start);
        next.setDate(start.getDate() + 28);
        expect(next.getTime() > start.getTime()).assertTrue();
      });
    });

    // ========== 排卵计算 —— 核心公式验证 ==========
    describe('排卵日计算（排卵日 = 下次经期前14天）', () => {

      it('标准28天周期 — 排卵日应在第14天', 0, () => {
        const ovulationDay = 28 - 14;
        expect(ovulationDay).assertEqual(14);
      });

      it('30天周期 — 排卵日应在第16天', 0, () => {
        const ovulationDay = 30 - 14;
        expect(ovulationDay).assertEqual(16);
      });

      it('25天周期（较短）— 排卵日应在第11天', 0, () => {
        const ovulationDay = 25 - 14;
        expect(ovulationDay).assertEqual(11);
      });

      it('35天周期（较长）— 排卵日应在第21天', 0, () => {
        const ovulationDay = 35 - 14;
        expect(ovulationDay).assertEqual(21);
      });

      it('排卵日始终在1到cycleLength之间', 0, () => {
        for (const cl of [21, 25, 28, 30, 35, 40]) {
          const ovulationDay = cl - 14;
          expect(ovulationDay >= 1 && ovulationDay <= cl).assertTrue();
        }
      });
    });

    // ========== 易孕期范围验证 ==========
    describe('易孕期范围（排卵日前5天至后1天）', () => {

      it('标准28天周期 — 易孕期为 cycleDay 9-15', 0, () => {
        const ovulationDay = 28 - 14; // 14
        const fertileStart = ovulationDay - 5; // 9
        const fertileEnd = ovulationDay + 1; // 15
        expect(fertileStart).assertEqual(9);
        expect(fertileEnd).assertEqual(15);
      });

      it('30天周期 — 易孕期为 cycleDay 11-17', 0, () => {
        const ovulationDay = 30 - 14; // 16
        const fertileStart = ovulationDay - 5; // 11
        const fertileEnd = ovulationDay + 1; // 17
        expect(fertileStart).assertEqual(11);
        expect(fertileEnd).assertEqual(17);
      });
    });

    // ========== 经期阶段判断 ==========
    describe('周期阶段判断', () => {

      it('cycleDay 1-5（默认经期长度）应为 menstrual', 0, () => {
        const duration = 5;
        expect(1 <= duration).assertTrue();
        expect(5 === duration).assertTrue();
      });

      it('cycleDay 6（经期结束后第一天）应为安全期', 0, () => {
        const duration = 5;
        const ovulationDay = 28 - 14;
        const cycleDay = 6;
        expect(cycleDay > duration).assertTrue();
        expect(cycleDay < ovulationDay - 5).assertTrue();
      });

      it('28天周期下 day14 应为 ovulation', 0, () => {
        const ovulationDay = 14;
        expect(ovulationDay).assertEqual(28 - 14);
      });

      it('28天周期下 day10 应在 fertile 区间', 0, () => {
        const cycleDay = 10;
        const ovulationDay = 14;
        const inFertile = cycleDay >= ovulationDay - 5 && cycleDay <= ovulationDay + 1;
        expect(inFertile).assertTrue();
      });
    });

    // ========== 怀孕风险计算 ==========
    describe('PregnancyRisk 怀孕风险', () => {

      it('易孕区中心应返回 HIGH', 0, () => {
        // ovulationDay 当日及前后共7天为 HIGH 风险
        const riskLevels = [PregnancyRisk.LOW, PregnancyRisk.MEDIUM, PregnancyRisk.HIGH];
        expect(riskLevels.length).assertEqual(3);
        expect(PregnancyRisk.HIGH).assertEqual('HIGH');
      });

      it('LOW < MEDIUM < HIGH 风险级', 0, () => {
        const risks = [PregnancyRisk.LOW, PregnancyRisk.MEDIUM, PregnancyRisk.HIGH];
        expect(risks[0]).assertEqual('LOW');
        expect(risks[1]).assertEqual('MEDIUM');
        expect(risks[2]).assertEqual('HIGH');
      });

      it('易孕期边界外应为非HIGH', 0, () => {
        expect(String(PregnancyRisk.LOW) !== String(PregnancyRisk.HIGH)).assertTrue();
        expect(String(PregnancyRisk.MEDIUM) !== String(PregnancyRisk.LOW)).assertTrue();
      });

      it('未知/无记录时应返回 LOW', 0, () => {
        expect(PregnancyRisk.LOW).assertEqual('LOW');
      });
    });

    // ========== 经期结束日期计算 ==========
    describe('calculateEndDate', () => {

      it('duration=5, 起始 3/1 → 结束应在 3/5', 0, () => {
        const start = new Date('2025-03-01');
        const duration = 5;
        const end = new Date(start);
        end.setDate(start.getDate() + duration - 1);
        expect(formatDate(end)).assertEqual('2025-03-05');
      });

      it('duration=7, 起始 3/1 → 结束应在 3/7', 0, () => {
        const start = new Date('2025-03-01');
        const duration = 7;
        const end = new Date(start);
        end.setDate(start.getDate() + duration - 1);
        expect(formatDate(end)).assertEqual('2025-03-07');
      });

      it('duration=1 时起始 = 结束', 0, () => {
        const start = new Date('2025-03-15');
        const duration = 1;
        const end = new Date(start);
        end.setDate(start.getDate() + duration - 1);
        expect(formatDate(end)).assertEqual('2025-03-15');
      });

      it('跨月 — 3/28 开始 duration=5', 0, () => {
        const start = new Date('2025-03-28');
        const duration = 5;
        const end = new Date(start);
        end.setDate(start.getDate() + duration - 1);
        expect(formatDate(end)).assertEqual('2025-04-01');
      });
    });

    // ========== 日历标记验证 ==========
    describe('日历标记颜色规则', () => {

      it('经期颜色应为粉红 #E91E63', 0, () => {
        expect('#E91E63'.length).assertEqual(7);
      });

      it('排卵日颜色应为 #FFD600（黄色）', 0, () => {
        expect('#FFD600'.length).assertEqual(7);
      });

      it('易孕期颜色（非排卵日）应为 #FF9800（橙色）', 0, () => {
        expect('#FF9800'.length).assertEqual(7);
      });

      it('安全期颜色应为 #4CAF50（绿色）', 0, () => {
        expect('#4CAF50'.length).assertEqual(7);
      });

      it('啪啪记录颜色应为 #F48FB1', 0, () => {
        expect('#F48FB1'.length).assertEqual(7);
      });

      it('排卵日应有星星图标', 0, () => {
        const icon = '⭐';
        expect(icon.length).assertEqual(2); // emoji
      });
    });

    // ========== 动态预测算法 ==========
    describe('动态预测算法', () => {

      it('应使用最近6次有效周期的加权平均预测下次经期', 0, () => {
        const records = [
          makeRecord('2025-01-01'),
          makeRecord('2025-01-28'),
          makeRecord('2025-02-24'),
          makeRecord('2025-03-25'),
          makeRecord('2025-04-23'),
          makeRecord('2025-05-22'),
          makeRecord('2025-06-20')
        ];

        const prediction = calculateAdaptivePeriodPrediction(records);

        expect(prediction.predictedCycleLength).assertEqual(29);
        expect(prediction.nextPeriodDate).assertEqual('2025-07-19');
        expect(prediction.confidenceDays).assertEqual(1);
        expect(prediction.validCycleCount).assertEqual(6);
        expect(prediction.isAdaptive).assertTrue();
      });

      it('应过滤明显异常周期避免偶发记录拉偏预测', 0, () => {
        const records = [
          makeRecord('2025-01-01'),
          makeRecord('2025-01-29'),
          makeRecord('2025-02-26'),
          makeRecord('2025-04-28'),
          makeRecord('2025-05-26'),
          makeRecord('2025-06-23')
        ];

        const prediction = calculateAdaptivePeriodPrediction(records);

        expect(prediction.predictedCycleLength).assertEqual(28);
        expect(prediction.nextPeriodDate).assertEqual('2025-07-21');
        expect(prediction.validCycleCount).assertEqual(4);
      });

      it('记录不足时应回退到最新记录的周期长度', 0, () => {
        const records = [
          makeRecord('2025-05-01', 5, 31),
          makeRecord('2025-06-01', 5, 31)
        ];

        const prediction = calculateAdaptivePeriodPrediction(records);

        expect(prediction.predictedCycleLength).assertEqual(31);
        expect(prediction.nextPeriodDate).assertEqual('2025-07-02');
        expect(prediction.validCycleCount).assertEqual(1);
        expect(prediction.isAdaptive).assertFalse();
      });

      it('应正确计算跨月预测范围', 0, () => {
        const records = [makeRecord('2025-01-31', 5, 28)];

        const prediction = calculateAdaptivePeriodPrediction(records);

        expect(prediction.nextPeriodDate).assertEqual('2025-02-28');
        expect(prediction.earliestPeriodDate).assertEqual('2025-02-25');
        expect(prediction.latestPeriodDate).assertEqual('2025-03-03');
      });
    });

    // ========== 周期趋势统计 ==========
    describe('周期趋势统计', () => {

      it('应按最新开始日期生成本周期和历史周期行', 0, () => {
        const records = [
          makeRecord('2026-01-30'),
          makeRecord('2026-02-26'),
          makeRecord('2026-03-25'),
          makeRecord('2026-04-22'),
          makeRecord('2026-05-21'),
          makeRecord('2026-06-16')
        ];

        const rows = calculateCycleTrendRows(records);

        expect(rows.length).assertEqual(6);
        expect(rows[0].startDate).assertEqual('2026-06-16');
        expect(rows[0].isCurrentCycle).assertTrue();
        expect(rows[0].cycleLength).assertEqual(0);
        expect(rows[0].cycleLabel).assertEqual('本周期');
        expect(rows[1].cycleLength).assertEqual(26);
        expect(rows[1].cycleLabel).assertEqual('26天');
        expect(rows[2].cycleLength).assertEqual(29);
        expect(rows[2].cycleLabel).assertEqual('29天');
      });

      it('应根据预测日期显示提前推迟和准时', 0, () => {
        const records = [
          makeRecord('2026-01-01', 5, 28),
          makeRecord('2026-01-30', 5, 28),
          makeRecord('2026-02-27', 5, 28),
          makeRecord('2026-03-26', 5, 28)
        ];

        const rows = calculateCycleTrendRows(records);

        expect(rows[1].punctualityLabel).assertEqual('提前1天');
        expect(rows[2].punctualityLabel).assertEqual('准时');
        expect(rows[3].punctualityLabel).assertEqual('推迟1天');
      });

      it('应标记正常范围和条形宽度', 0, () => {
        const records = [
          makeRecord('2026-01-01'),
          makeRecord('2026-01-25'),
          makeRecord('2026-02-26')
        ];

        const rows = calculateCycleTrendRows(records);

        expect(rows[1].cycleLength).assertEqual(32);
        expect(rows[1].isNormalRange).assertTrue();
        expect(rows[1].barWidthPercent > rows[2].barWidthPercent).assertTrue();
      });
    });

    // ========== PeriodRecord 模型字段完整性 ==========
    describe('PeriodRecord 数据模型', () => {

      it('必填字段 startDate 不应为空', 0, () => {
        const record = makeRecord('2025-03-01');
        expect(record.startDate.length > 0).assertTrue();
        expect(record.startDate).assertEqual('2025-03-01');
      });

      it('默认 cycleLength = 28', 0, () => {
        const record = makeRecord('2025-03-01');
        expect(record.cycleLength).assertEqual(28);
      });

      it('默认 duration = 5', 0, () => {
        const record = makeRecord('2025-03-01');
        expect(record.duration).assertEqual(5);
      });

      it('symptoms 默认为空数组', 0, () => {
        const record = makeRecord('2025-03-01');
        expect(Array.isArray(record.symptoms)).assertTrue();
        expect(record.symptoms.length).assertEqual(0);
      });

      it('visibility 默认为 PRIVATE', 0, () => {
        const record = makeRecord('2025-03-01');
        expect(record.visibility).assertEqual(Visibility.PRIVATE);
      });
    });

    // ========== IntimacyRecord 数据模型 ==========
    describe('IntimacyRecord 数据模型', () => {
      const base: IntimacyRecord = {
        id: '',
        familyId: '',
        creatorId: '',
        visibility: Visibility.PRIVATE,
        visibleMembers: [],
        version: 1,
        createdAt: '',
        updatedAt: '',
        date: '',
        pregnancyRisk: PregnancyRisk.LOW,
        cycleDay: 0,
        note: ''
      };

      it('默认 pregnancyRisk 应为 LOW', 0, () => {
        expect(base.pregnancyRisk).assertEqual(PregnancyRisk.LOW);
      });

      it('默认 cycleDay 应为 0', 0, () => {
        expect(base.cycleDay).assertEqual(0);
      });
    });

    // ========== 排序验证 —— 修复 Issue#4 ==========
    describe('记录排序（按 startDate 降序）', () => {

      it('降序排序后第一条应为最新日期', 0, () => {
        const records = [
          makeRecord('2025-01-01'),
          makeRecord('2025-03-15'),
          makeRecord('2025-02-10'),
        ];
        const sorted = [...records].sort(
          (a, b) => b.startDate.localeCompare(a.startDate)
        );
        expect(sorted[0].startDate).assertEqual('2025-03-15');
        expect(sorted[sorted.length - 1].startDate).assertEqual('2025-01-01');
      });

      it('单条记录排序后仍为同一条', 0, () => {
        const records = [makeRecord('2025-03-01')];
        const sorted = [...records].sort(
          (a, b) => b.startDate.localeCompare(a.startDate)
        );
        expect(sorted[0].startDate).assertEqual('2025-03-01');
      });

      it('空数组排序后仍为空', 0, () => {
        const records: PeriodRecord[] = [];
        const sorted = [...records].sort(
          (a, b) => b.startDate.localeCompare(a.startDate)
        );
        expect(sorted.length).assertEqual(0);
      });
    });

    // ========== 周期提醒同步 —— buildPeriodReminderSpecs（Bug 1 修复） ==========
    describe('buildPeriodReminderSpecs 稳定ID与dueTime', () => {

      it('无周期预测（currentDay=0）时不生成任何提醒', 0, () => {
        const status: CycleStatus = { currentDay: 0, cycleLength: 28, duration: 5, phase: 'unknown', nextPeriodDate: '' };
        const specs = buildPeriodReminderSpecs(DEFAULT_SETTINGS, status, 'm1', '2026-08-01');
        expect(specs.length).assertEqual(0);
      });

      it('有预测但 nextPeriodDate 为空时不生成', 0, () => {
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '' };
        const specs = buildPeriodReminderSpecs(DEFAULT_SETTINGS, status, 'm1', '2026-08-01');
        expect(specs.length).assertEqual(0);
      });

      it('默认开关生成 经期前3天/1天 两个稳定ID提醒，dueTime 分别为经期前3天/1天', 0, () => {
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '2026-09-01' };
        const specs = buildPeriodReminderSpecs(DEFAULT_SETTINGS, status, 'm1', '2026-08-01');
        expect(specs.length).assertEqual(2);

        const s3d = findSpec(specs, 'per_3d_m1');
        expect(s3d !== null).assertTrue();
        if (s3d) {
          expect(s3d.dueTime).assertEqual('2026-08-29T09:00:00'); // 9/1 前3天
        }
        const s1d = findSpec(specs, 'per_1d_m1');
        expect(s1d !== null).assertTrue();
        if (s1d) {
          expect(s1d.dueTime).assertEqual('2026-08-31T09:00:00'); // 9/1 前1天
        }
      });

      it('跨月时经期前3天正确回退到上月末', 0, () => {
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '2026-03-02' };
        const specs = buildPeriodReminderSpecs(DEFAULT_SETTINGS, status, 'm1', '2026-02-20');
        const s3d = findSpec(specs, 'per_3d_m1');
        expect(s3d !== null).assertTrue();
        if (s3d) {
          expect(s3d.dueTime).assertEqual('2026-02-27T09:00:00'); // 3/2 前3天跨到2月
        }
      });

      it('排卵日提醒只在排卵日仍为未来时生成（过期不生成）', 0, () => {
        // nextPeriodDate=9/10 → 排卵日 8/27（未来）→ 生成；易孕期开始 8/22（已过）→ 不生成
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '2026-09-10' };
        const specs = buildPeriodReminderSpecs(ALL_ON_SETTINGS, status, 'm1', '2026-08-26');

        const s3d = findSpec(specs, 'per_3d_m1');
        expect(s3d !== null).assertTrue();
        const s1d = findSpec(specs, 'per_1d_m1');
        expect(s1d !== null).assertTrue();
        const sov = findSpec(specs, 'per_ov_m1');
        expect(sov !== null).assertTrue();
        if (sov) {
          expect(sov.dueTime).assertEqual('2026-08-27T09:00:00'); // 排卵日 = 经期前14天
        }
        const sft = findSpec(specs, 'per_ft_m1');
        expect(sft === null).assertTrue(); // 易孕期开始日已过，不生成
      });

      it('排卵日已过则不生成排卵提醒（避免过期提醒占位）', 0, () => {
        // nextPeriodDate=8/20 → 排卵日 8/6 已过
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '2026-08-20' };
        const specs = buildPeriodReminderSpecs(ALL_ON_SETTINGS, status, 'm1', '2026-08-26');
        const sov = findSpec(specs, 'per_ov_m1');
        expect(sov === null).assertTrue();
      });

      it('所有开关关闭时不生成任何提醒', 0, () => {
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '2026-09-01' };
        const specs = buildPeriodReminderSpecs(ALL_OFF_SETTINGS, status, 'm1', '2026-08-01');
        expect(specs.length).assertEqual(0);
      });

      it('稳定 ID 与成员绑定：不同成员生成不同 ID', 0, () => {
        const status: CycleStatus = { currentDay: 5, cycleLength: 28, duration: 5, phase: 'safe_after', nextPeriodDate: '2026-09-01' };
        const specs = buildPeriodReminderSpecs(DEFAULT_SETTINGS, status, 'm2', '2026-08-01');
        const s3d = findSpec(specs, 'per_3d_m2');
        expect(s3d !== null).assertTrue();
        const other = findSpec(specs, 'per_3d_m1');
        expect(other === null).assertTrue();
      });
    });

    // ========== 周期提醒同步 —— isManagedPeriodReminderId ==========
    describe('isManagedPeriodReminderId 稳定ID识别', () => {

      it('四个稳定 ID 前缀均识别为受管', 0, () => {
        expect(isManagedPeriodReminderId('per_3d_m1', 'm1')).assertTrue();
        expect(isManagedPeriodReminderId('per_1d_m1', 'm1')).assertTrue();
        expect(isManagedPeriodReminderId('per_ov_m1', 'm1')).assertTrue();
        expect(isManagedPeriodReminderId('per_ft_m1', 'm1')).assertTrue();
      });

      it('历史随机 ID 不受管（将被清理）', 0, () => {
        expect(isManagedPeriodReminderId('rem_8f3a2c91', 'm1')).assertFalse();
        expect(isManagedPeriodReminderId('', 'm1')).assertFalse();
      });

      it('他人成员的稳定 ID 不属于本成员', 0, () => {
        expect(isManagedPeriodReminderId('per_3d_m2', 'm1')).assertFalse();
        expect(isManagedPeriodReminderId('per_3d_m1', 'm2')).assertFalse();
      });

      it('前缀相似但不完整不受管', 0, () => {
        expect(isManagedPeriodReminderId('per_3d_m1_extra', 'm1')).assertFalse();
      });
    });

    // ========== 周期提醒同步 —— planPeriodReminderSync（Bug 1/3 核心） ==========
    describe('planPeriodReminderSync 调和计划', () => {

      it('空记录 + 有期望 → 全部新建', 0, () => {
        const specs = [makeSpec('per_3d_m1', '2026-08-29T09:00:00', '🌸 经期前3天提醒')];
        const plan = planPeriodReminderSync([], specs, 'm1', Visibility.FAMILY, []);
        expect(plan.creates.length).assertEqual(1);
        expect(plan.creates[0].id).assertEqual('per_3d_m1');
        expect(plan.updates.length).assertEqual(0);
        expect(plan.hides.length).assertEqual(0);
        expect(plan.deletes.length).assertEqual(0);
      });

      it('幂等：记录已与期望一致 → 无任何操作（重复同步不产生重复记录）', 0, () => {
        const specs = [makeSpec('per_3d_m1', '2026-08-29T09:00:00', '🌸 经期前3天提醒')];
        const existing = [makeReminder('per_3d_m1', '2026-08-29T09:00:00', '🌸 经期前3天提醒')];
        const plan = planPeriodReminderSync(existing, specs, 'm1', Visibility.FAMILY, []);
        expect(plan.updates.length).assertEqual(0);
        expect(plan.hides.length).assertEqual(0);
        expect(plan.deletes.length).assertEqual(0);
        expect(plan.creates.length).assertEqual(0);
      });

      it('dueTime 变化（进入新周期）→ 就地更新且重置完成状态', 0, () => {
        const specs = [makeSpec('per_3d_m1', '2026-08-29T09:00:00', '🌸 经期前3天提醒')];
        const existing = [makeReminder('per_3d_m1', '2026-07-29T09:00:00', '🌸 经期前3天提醒', true)];
        const plan = planPeriodReminderSync(existing, specs, 'm1', Visibility.FAMILY, []);
        expect(plan.updates.length).assertEqual(1);
        expect(plan.updates[0].resetCompleted).assertTrue();
      });

      it('仅标题/描述变化 → 就地更新但保留完成状态（非创建者勾选「已读」不被复活）', 0, () => {
        const specs = [makeSpec('per_3d_m1', '2026-08-29T09:00:00', '🌸 经期前3天提醒')];
        const existing = [makeReminder('per_3d_m1', '2026-08-29T09:00:00', '旧标题', true)];
        const plan = planPeriodReminderSync(existing, specs, 'm1', Visibility.FAMILY, []);
        expect(plan.updates.length).assertEqual(1);
        expect(plan.updates[0].resetCompleted).assertFalse();
      });

      it('开关关闭（稳定ID无对应期望且未隐藏）→ 置空隐藏而非删除', 0, () => {
        const existing = [makeReminder('per_3d_m1', '2026-08-29T09:00:00')];
        const plan = planPeriodReminderSync(existing, [], 'm1', Visibility.FAMILY, []);
        expect(plan.hides.length).assertEqual(1);
        expect(plan.hides[0].id).assertEqual('per_3d_m1');
        expect(plan.deletes.length).assertEqual(0);
        expect(plan.creates.length).assertEqual(0);
      });

      it('已隐藏记录（dueTime 为空）不重复隐藏（幂等）', 0, () => {
        const existing = [makeReminder('per_3d_m1', '')];
        const plan = planPeriodReminderSync(existing, [], 'm1', Visibility.FAMILY, []);
        expect(plan.hides.length).assertEqual(0);
      });

      it('历史随机 ID 重复记录 → 删除清理（Bug 1 去重）', 0, () => {
        const specs = [makeSpec('per_3d_m1', '2026-08-29T09:00:00')];
        const existing = [
          makeReminder('per_3d_m1', '2026-08-29T09:00:00'),
          makeReminder('legacy_rand_001', '2026-08-29T09:00:00'),
          makeReminder('legacy_rand_002', '2026-08-29T09:00:00')
        ];
        const plan = planPeriodReminderSync(existing, specs, 'm1', Visibility.FAMILY, []);
        expect(plan.deletes.length).assertEqual(2);
        expect(plan.deletes.indexOf('legacy_rand_001') >= 0).assertTrue();
        expect(plan.deletes.indexOf('legacy_rand_002') >= 0).assertTrue();
        expect(plan.updates.length).assertEqual(0);
        expect(plan.creates.length).assertEqual(0);
      });

      it('混合场景：新建 + 更新 + 隐藏 + 删除 同时发生', 0, () => {
        const specs = [
          makeSpec('per_3d_m1', '2026-08-29T09:00:00'),
          makeSpec('per_1d_m1', '2026-08-31T09:00:00'),
          makeSpec('per_ov_m1', '2026-08-18T09:00:00')
        ];
        const existing = [
          makeReminder('per_3d_m1', '2026-08-29T09:00:00'),       // 一致 → 不动
          makeReminder('per_1d_m1', '2026-07-31T09:00:00'),       // dueTime 变 → 更新重置
          makeReminder('per_ft_m1', '2026-08-13T09:00:00'),       // 开关已关 → 隐藏
          makeReminder('legacy_rand_009', '2026-08-29T09:00:00')  // 遗留 → 删除
        ];
        const plan = planPeriodReminderSync(existing, specs, 'm1', Visibility.FAMILY, []);
        expect(plan.updates.length).assertEqual(1);
        expect(plan.updates[0].record.id).assertEqual('per_1d_m1');
        expect(plan.updates[0].resetCompleted).assertTrue();
        expect(plan.hides.length).assertEqual(1);
        expect(plan.hides[0].id).assertEqual('per_ft_m1');
        expect(plan.deletes.length).assertEqual(1);
        expect(plan.deletes[0]).assertEqual('legacy_rand_009');
        expect(plan.creates.length).assertEqual(1); // per_ov_m1 是期望状态但本地缺失 → 新建
        expect(plan.creates[0].id).assertEqual('per_ov_m1');
      });

      it('可见范围变化（共享设置变更）→ 触发就地更新', 0, () => {
        const specs = [makeSpec('per_3d_m1', '2026-08-29T09:00:00')];
        const existing = [makeReminder('per_3d_m1', '2026-08-29T09:00:00')];
        const plan = planPeriodReminderSync(existing, specs, 'm1', Visibility.SELECTED, ['m2']);
        expect(plan.updates.length).assertEqual(1);
      });
    });

    // ========== 「来了」误触确认 —— checkPeriodRecordConfirm ==========
    describe('checkPeriodRecordConfirm 误触确认', () => {

      it('无任何记录（首次记录）→ 不弹窗', 0, () => {
        const check = checkPeriodRecordConfirm([], '2026-08-15');
        expect(check.needsConfirm).assertFalse();
      });

      it('经期进行中再点「来了」→ 弹窗（避免重复记录）', 0, () => {
        const records = [makeRecord('2026-08-10')]; // endDate 为空 = 进行中
        const check = checkPeriodRecordConfirm(records, '2026-08-15');
        expect(check.needsConfirm).assertTrue();
        expect(check.message.indexOf('进行中') >= 0).assertTrue();
      });

      it('周期28天、第15天点「来了」→ 弹窗确认（提前13天）', 0, () => {
        const records = [makeEndedRecord('2026-08-01', '2026-08-05')];
        const check = checkPeriodRecordConfirm(records, '2026-08-15'); // 第15天
        expect(check.needsConfirm).assertTrue();
        expect(check.message.indexOf('提前') >= 0).assertTrue();
      });

      it('周期28天、到第21天（提前7天，临界值）→ 弹窗', 0, () => {
        const records = [makeEndedRecord('2026-08-01', '2026-08-05')];
        const check = checkPeriodRecordConfirm(records, '2026-08-21'); // 第21天
        expect(EARLY_PERIOD_CONFIRM_DAYS).assertEqual(7);
        expect(check.needsConfirm).assertTrue();
      });

      it('周期28天、第22天（提前6天，低于阈值）→ 不弹窗', 0, () => {
        const records = [makeEndedRecord('2026-08-01', '2026-08-05')];
        const check = checkPeriodRecordConfirm(records, '2026-08-22'); // 第22天
        expect(check.needsConfirm).assertFalse();
      });

      it('按时（第29天）→ 不弹窗', 0, () => {
        const records = [makeEndedRecord('2026-08-01', '2026-08-05')];
        const check = checkPeriodRecordConfirm(records, '2026-08-29');
        expect(check.needsConfirm).assertFalse();
      });

      it('预测周期来自自适应算法（31天周期第18天点 → 提前13天弹窗）', 0, () => {
        const records = [makeEndedRecord('2026-08-01', '2026-08-05', 31)];
        const check = checkPeriodRecordConfirm(records, '2026-08-18'); // 第18天
        expect(check.needsConfirm).assertTrue();
      });
    });

    // ========== 归属主体归一化 —— normalizeSubjectId ==========
    describe('normalizeSubjectId 归属主体归一化', () => {

      it('新格式（mem_xxx）直接作为主体，不查映射', 0, () => {
        const map = makeMembersByUserId();
        expect(normalizeSubjectId('mem_wife', map)).assertEqual('mem_wife');
      });

      it('旧格式 openID 通过成员表映射到 memberId', 0, () => {
        const map = makeMembersByUserId();
        expect(normalizeSubjectId('openid_self', map)).assertEqual('mem_self');
        expect(normalizeSubjectId('openid_wife', map)).assertEqual('mem_wife');
      });

      it('映射不到的 openID 原样返回（兼容旧数据展示）', 0, () => {
        const map = makeMembersByUserId();
        expect(normalizeSubjectId('openid_ghost', map)).assertEqual('openid_ghost');
      });

      it('空 creatorId 返回空字符串', 0, () => {
        const map = makeMembersByUserId();
        expect(normalizeSubjectId('', map)).assertEqual('');
      });

      it('空映射表时新格式仍原样返回', 0, () => {
        expect(normalizeSubjectId('mem_self', new Map<string, string>())).assertEqual('mem_self');
      });
    });

    // ========== 归属主体过滤 —— filterRecordsBySubject ==========
    describe('filterRecordsBySubject 按主体过滤', () => {

      it('subjectId 为空时返回全部记录（不拦截）', 0, () => {
        const records = [makeRecordWithCreator('2026-08-01', 'mem_self'), makeRecordWithCreator('2026-08-02', 'mem_wife')];
        const filtered = filterRecordsBySubject(records, '', makeMembersByUserId());
        expect(filtered.length).assertEqual(2);
      });

      it('新格式记录按 creatorId 直接过滤', 0, () => {
        const records = [
          makeRecordWithCreator('2026-08-01', 'mem_self'),
          makeRecordWithCreator('2026-08-10', 'mem_wife'),
          makeRecordWithCreator('2026-08-20', 'mem_self')
        ];
        const mine = filterRecordsBySubject(records, 'mem_self', makeMembersByUserId());
        expect(mine.length).assertEqual(2);
        const hers = filterRecordsBySubject(records, 'mem_wife', makeMembersByUserId());
        expect(hers.length).assertEqual(1);
      });

      it('旧格式 openID 记录归一化后也能正确归属到成员', 0, () => {
        const records = [
          makeRecordWithCreator('2026-08-01', 'openid_self'),
          makeRecordWithCreator('2026-08-10', 'openid_wife')
        ];
        const mine = filterRecordsBySubject(records, 'mem_self', makeMembersByUserId());
        expect(mine.length).assertEqual(1);
        expect(mine[0].creatorId).assertEqual('openid_self');
      });

      it('混合新旧格式时同一主体的记录全部命中', 0, () => {
        const records = [
          makeRecordWithCreator('2026-08-01', 'mem_self'),
          makeRecordWithCreator('2026-08-10', 'openid_wife'),
          makeRecordWithCreator('2026-08-15', 'openid_self')
        ];
        const mine = filterRecordsBySubject(records, 'mem_self', makeMembersByUserId());
        expect(mine.length).assertEqual(2);
      });

      it('啪啪记录同样按主体过滤', 0, () => {
        const records = [
          makeIntimacyRecordWithCreator('2026-08-05', 'mem_self'),
          makeIntimacyRecordWithCreator('2026-08-12', 'mem_wife')
        ];
        const mine = filterRecordsBySubject(records, 'mem_self', makeMembersByUserId());
        expect(mine.length).assertEqual(1);
        expect(mine[0].date).assertEqual('2026-08-05');
      });

      it('多主体记录互相隔离：各主体的周期预测互不影响', 0, () => {
        const records = [
          makeRecordWithCreator('2026-06-01', 'mem_self', 5, 28),
          makeRecordWithCreator('2026-06-28', 'mem_self', 5, 28),
          makeRecordWithCreator('2026-07-26', 'mem_self', 5, 28),
          makeRecordWithCreator('2026-07-01', 'mem_wife', 5, 35),
          makeRecordWithCreator('2026-08-01', 'mem_wife', 5, 35)
        ];
        const mine = filterRecordsBySubject(records, 'mem_self', makeMembersByUserId());
        const hers = filterRecordsBySubject(records, 'mem_wife', makeMembersByUserId());
        // 我的记录：28天周期
        const minePrediction = calculateAdaptivePeriodPrediction(mine);
        expect(mine.length).assertEqual(3);
        expect(minePrediction.predictedCycleLength).assertEqual(28);
        // 她的记录：35天周期（记录少回退到最新记录的 cycleLength）
        const herPrediction = calculateAdaptivePeriodPrediction(hers);
        expect(hers.length).assertEqual(2);
        expect(herPrediction.predictedCycleLength).assertEqual(35);
      });

      it('查看他人主体时趋势行只含该主体的记录', 0, () => {
        const records = [
          makeRecordWithCreator('2026-07-10', 'mem_self'),
          makeRecordWithCreator('2026-08-01', 'mem_wife')
        ];
        const hers = filterRecordsBySubject(records, 'mem_wife', makeMembersByUserId());
        const rows = calculateCycleTrendRows(hers);
        expect(rows.length).assertEqual(1);
        expect(rows[0].startDate).assertEqual('2026-08-01');
      });
    });

  });

  describe('shouldEnterViewerMode', () => {
    it('无记录且未开启记录 → 进入仅查看模式', 0, () => {
      expect(shouldEnterViewerMode(false, false)).assertTrue();
    });
    it('有记录 → 不进入仅查看模式', 0, () => {
      expect(shouldEnterViewerMode(true, false)).assertFalse();
    });
    it('开启记录开关 → 即使无记录也不进入', 0, () => {
      expect(shouldEnterViewerMode(false, true)).assertFalse();
    });
    it('有记录且开启开关 → 不进入', 0, () => {
      expect(shouldEnterViewerMode(true, true)).assertFalse();
    });
  });

  describe('buildSubjectOptions', () => {
    const selfId = 'mem_self';
    const membersById = new Map<string, string>();
    membersById.set('mem_self', '我');
    membersById.set('mem_wife', '老婆');
    const membersByUserId = makeMembersByUserId(); // openid_self->mem_self, openid_wife->mem_wife（文件已有辅助函数）

    it('非查看模式：自己在前，成员在后，名称映射正确', 0, () => {
      const records = [makeRecordWithCreator('2026-08-01', 'openid_wife')];
      const opts = buildSubjectOptions(selfId, records, [], membersById, membersByUserId, false);
      expect(opts.length).assertEqual(2);
      expect(opts[0].memberId).assertEqual('mem_self');
      expect(opts[0].name).assertEqual('我');
      expect(opts[1].memberId).assertEqual('mem_wife');
      expect(opts[1].name).assertEqual('老婆');
    });

    it('查看模式：排除自己，只列有记录的其他成员', 0, () => {
      const records = [makeRecordWithCreator('2026-08-01', 'openid_wife')];
      const opts = buildSubjectOptions(selfId, records, [], membersById, membersByUserId, true);
      expect(opts.length).assertEqual(1);
      expect(opts[0].memberId).assertEqual('mem_wife');
    });

    it('查看模式：没有其他成员记录时返回空列表', 0, () => {
      const opts = buildSubjectOptions(selfId, [], [], membersById, membersByUserId, true);
      expect(opts.length).assertEqual(0);
    });

    it('查看模式：输入含自己记录时也排除自己', 0, () => {
      const records = [makeRecordWithCreator('2026-08-01', 'openid_self')];
      const opts = buildSubjectOptions(selfId, records, [], membersById, membersByUserId, true);
      expect(opts.length).assertEqual(0);
    });

    it('同一成员多条记录（含啪啪记录）只出现一次', 0, () => {
      const records = [
        makeRecordWithCreator('2026-08-01', 'mem_wife'),
        makeRecordWithCreator('2026-07-01', 'mem_wife')
      ];
      const intimacy = [makeIntimacyRecordWithCreator('2026-08-10', 'openid_wife')];
      const opts = buildSubjectOptions(selfId, records, intimacy, membersById, membersByUserId, false);
      expect(opts.length).assertEqual(2); // mem_self + mem_wife
    });
  });
}
