/**
 * Utils 工具函数单元测试
 * 测试日期格式化、ID生成、邀请码、指数退避、健康判断
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  generateId,
  generateInviteCode,
  formatDate,
  formatTime,
  daysBetween,
  toDateAtLocalMidnight,
  toDateTime,
  addDaysToDateStr,
  daysBetweenDateStrings,
  exponentialBackoff,
  isAbnormal
} from '../../../main/ets/common/Utils';

export default function utilsTest() {
  describe('Utils 工具函数', () => {

    // ---------- generateId ----------
    describe('generateId', () => {

      it('应生成带前缀的ID', 0, () => {
        const id = generateId('u');
        expect(id.startsWith('u_')).assertTrue();
      });

      it('不同前缀应产生以不同前缀开头的ID', 0, () => {
        const uid = generateId('u');
        const fid = generateId('f');
        expect(uid.startsWith('u_')).assertTrue();
        expect(fid.startsWith('f_')).assertTrue();
      });

      it('连续生成应产生不同的ID', 0, () => {
        const ids = new Set<string>();
        for (let i = 0; i < 100; i++) {
          ids.add(generateId('t'));
        }
        expect(ids.size).assertEqual(100);
      });

      it('ID应包含时间戳和随机串三部分', 0, () => {
        const id = generateId('pr');
        const parts = id.split('_');
        expect(parts.length).assertEqual(3);
        expect(parts[0]).assertEqual('pr');
        expect(Number.isNaN(Number(parts[1]))).assertFalse();
        expect(parts[2].length).assertEqual(9);
      });

      it('边界—空字符串前缀', 0, () => {
        const id = generateId('');
        expect(id.startsWith('_')).assertTrue();
      });
    });

    // ---------- generateInviteCode ----------
    describe('generateInviteCode', () => {

      it('应生成6位数字字符串', 0, () => {
        const code = generateInviteCode();
        expect(code.length).assertEqual(6);
        expect(/^\d{6}$/.test(code)).assertTrue();
      });

      it('生成的值应在100000-999999之间', 0, () => {
        for (let i = 0; i < 100; i++) {
          const code = generateInviteCode();
          const num = parseInt(code);
          expect(num >= 100000 && num <= 999999).assertTrue();
        }
      });

      it('不应以0开头', 0, () => {
        for (let i = 0; i < 50; i++) {
          expect(generateInviteCode().startsWith('0')).assertFalse();
        }
      });
    });

    // ---------- formatDate ----------
    describe('formatDate', () => {

      it('应格式化为 YYYY-MM-DD', 0, () => {
        expect(formatDate(new Date('2025-03-15'))).assertEqual('2025-03-15');
      });

      it('应正确处理单数月和单数日（前导零）', 0, () => {
        expect(formatDate(new Date('2025-01-05'))).assertEqual('2025-01-05');
      });

      it('应正确处理年末日期', 0, () => {
        expect(formatDate(new Date('2025-12-31'))).assertEqual('2025-12-31');
      });

      it('应正确处理闰年', 0, () => {
        expect(formatDate(new Date('2024-02-29'))).assertEqual('2024-02-29');
      });
    });

    // ---------- formatTime ----------
    describe('formatTime', () => {

      it('应格式化为 HH:mm', 0, () => {
        const d = new Date('2025-03-15T08:05:00');
        expect(formatTime(d)).assertEqual('08:05');
      });

      it('午间时间应有前导零', 0, () => {
        const d = new Date('2025-03-15T03:07:00');
        expect(formatTime(d)).assertEqual('03:07');
      });

      it('午夜应为 00:00', 0, () => {
        const d = new Date('2025-03-15T00:00:00');
        expect(formatTime(d)).assertEqual('00:00');
      });
    });

    // ---------- daysBetween ----------
    describe('daysBetween', () => {

      it('同一天应返回0', 0, () => {
        const a = new Date('2025-03-15');
        const b = new Date('2025-03-15');
        expect(daysBetween(a, b)).assertEqual(0);
      });

      it('相差一天的日期应返回1', 0, () => {
        expect(daysBetween(new Date('2025-03-15'), new Date('2025-03-16')))
          .assertEqual(1);
      });

      it('参数顺序不应影响结果', 0, () => {
        const r1 = daysBetween(new Date('2025-01-01'), new Date('2025-01-10'));
        const r2 = daysBetween(new Date('2025-01-10'), new Date('2025-01-01'));
        expect(r1).assertEqual(r2);
      });

      it('跨月的日期计算', 0, () => {
        expect(daysBetween(new Date('2025-01-31'), new Date('2025-02-02')))
          .assertEqual(2);
      });

      it('跨年的日期计算', 0, () => {
        expect(daysBetween(new Date('2024-12-31'), new Date('2025-01-02')))
          .assertEqual(2);
      });

      it('闰年2月29日', 0, () => {
        expect(daysBetween(new Date('2024-02-28'), new Date('2024-03-01')))
          .assertEqual(2);
      });
    });

    // ---------- date string helpers ----------
    describe('日期字符串工具', () => {

      it('toDateAtLocalMidnight 应按本地年月日解析 YYYY-MM-DD', 0, () => {
        const date = toDateAtLocalMidnight('2026-06-25');
        expect(date.getFullYear()).assertEqual(2026);
        expect(date.getMonth()).assertEqual(5);
        expect(date.getDate()).assertEqual(25);
      });

      it('toDateTime 应按日期时间字符串生成 Date', 0, () => {
        const date = toDateTime('2026-06-25T09:30:00');
        expect(date.getFullYear()).assertEqual(2026);
        expect(date.getMonth()).assertEqual(5);
        expect(date.getDate()).assertEqual(25);
        expect(date.getHours()).assertEqual(9);
        expect(date.getMinutes()).assertEqual(30);
      });

      it('toDateTime 遇到纯日期字符串应返回当天零点', 0, () => {
        const date = toDateTime('2026-06-25');
        expect(date.getFullYear()).assertEqual(2026);
        expect(date.getMonth()).assertEqual(5);
        expect(date.getDate()).assertEqual(25);
        expect(date.getHours()).assertEqual(0);
        expect(date.getMinutes()).assertEqual(0);
      });

      it('addDaysToDateStr 应正确跨月加天数', 0, () => {
        expect(addDaysToDateStr('2026-06-29', 3)).assertEqual('2026-07-02');
      });

      it('daysBetweenDateStrings 应保留日期差方向', 0, () => {
        expect(daysBetweenDateStrings('2026-06-25', '2026-06-28')).assertEqual(3);
        expect(daysBetweenDateStrings('2026-06-28', '2026-06-25')).assertEqual(-3);
      });
    });

    // ---------- exponentialBackoff ----------
    describe('exponentialBackoff', () => {

      it('第0次应为初始延迟', 0, () => {
        expect(exponentialBackoff(0, 1000, 30000)).assertEqual(1000);
      });

      it('指数增长: 2^1 = 2000', 0, () => {
        expect(exponentialBackoff(1, 1000, 30000)).assertEqual(2000);
      });

      it('指数增长: 2^3 = 8000', 0, () => {
        expect(exponentialBackoff(3, 1000, 30000)).assertEqual(8000);
      });

      it('应受 maxDelay 上限约束', 0, () => {
        expect(exponentialBackoff(10, 1000, 30000)).assertEqual(30000);
      });

      it('maxDelay为0时不应返回负值', 0, () => {
        const result = exponentialBackoff(5, 100, 0);
        expect(result >= 0).assertTrue();
      });
    });

    // ---------- isAbnormal ----------
    describe('isAbnormal', () => {

      it('在范围内的值应返回 false', 0, () => {
        expect(isAbnormal(36.5, 36.0, 37.3)).assertFalse();
      });

      it('低于最小值应返回 true', 0, () => {
        expect(isAbnormal(35.5, 36.0, 37.3)).assertTrue();
      });

      it('高于最大值应返回 true', 0, () => {
        expect(isAbnormal(37.5, 36.0, 37.3)).assertTrue();
      });

      it('边界—等于最小值应返回 false', 0, () => {
        expect(isAbnormal(90, 90, 140)).assertFalse();
      });

      it('边界—等于最大值应返回 false', 0, () => {
        expect(isAbnormal(140, 90, 140)).assertFalse();
      });

      it('边界—低于最小值1单位', 0, () => {
        expect(isAbnormal(89, 90, 140)).assertTrue();
      });

      it('边界—高于最大值1单位', 0, () => {
        expect(isAbnormal(141, 90, 140)).assertTrue();
      });
    });

  });
}
