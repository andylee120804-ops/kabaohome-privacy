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
  exponentialBackoff,
  isAbnormal
} from '../../main/ets/common/Utils';

export default function utilsTest() {
  describe('Utils 工具函数', () => {

    // ---------- generateId ----------
    describe('generateId', () => {

      it('应生成带前缀的ID', () => {
        const id = generateId('u');
        expect(id.startsWith('u_')).assertTrue();
      });

      it('不同前缀应产生以不同前缀开头的ID', () => {
        const uid = generateId('u');
        const fid = generateId('f');
        expect(uid.startsWith('u_')).assertTrue();
        expect(fid.startsWith('f_')).assertTrue();
      });

      it('连续生成应产生不同的ID', () => {
        const ids = new Set<string>();
        for (let i = 0; i < 100; i++) {
          ids.add(generateId('t'));
        }
        expect(ids.size).assertEqual(100);
      });

      it('ID应包含时间戳和随机串三部分', () => {
        const id = generateId('pr');
        const parts = id.split('_');
        expect(parts.length).assertEqual(3);
        expect(parts[0]).assertEqual('pr');
        expect(Number.isNaN(Number(parts[1]))).assertFalse();
        expect(parts[2].length).assertEqual(9);
      });

      it('边界—空字符串前缀', () => {
        const id = generateId('');
        expect(id.startsWith('_')).assertTrue();
      });
    });

    // ---------- generateInviteCode ----------
    describe('generateInviteCode', () => {

      it('应生成6位数字字符串', () => {
        const code = generateInviteCode();
        expect(code.length).assertEqual(6);
        expect(/^\d{6}$/.test(code)).assertTrue();
      });

      it('生成的值应在100000-999999之间', () => {
        for (let i = 0; i < 100; i++) {
          const code = generateInviteCode();
          const num = parseInt(code);
          expect(num >= 100000 && num <= 999999).assertTrue();
        }
      });

      it('不应以0开头', () => {
        for (let i = 0; i < 50; i++) {
          expect(generateInviteCode().startsWith('0')).assertFalse();
        }
      });
    });

    // ---------- formatDate ----------
    describe('formatDate', () => {

      it('应格式化为 YYYY-MM-DD', () => {
        expect(formatDate(new Date('2025-03-15'))).assertEqual('2025-03-15');
      });

      it('应正确处理单数月和单数日（前导零）', () => {
        expect(formatDate(new Date('2025-01-05'))).assertEqual('2025-01-05');
      });

      it('应正确处理年末日期', () => {
        expect(formatDate(new Date('2025-12-31'))).assertEqual('2025-12-31');
      });

      it('应正确处理闰年', () => {
        expect(formatDate(new Date('2024-02-29'))).assertEqual('2024-02-29');
      });
    });

    // ---------- formatTime ----------
    describe('formatTime', () => {

      it('应格式化为 HH:mm', () => {
        const d = new Date('2025-03-15T08:05:00');
        expect(formatTime(d)).assertEqual('08:05');
      });

      it('午间时间应有前导零', () => {
        const d = new Date('2025-03-15T03:07:00');
        expect(formatTime(d)).assertEqual('03:07');
      });

      it('午夜应为 00:00', () => {
        const d = new Date('2025-03-15T00:00:00');
        expect(formatTime(d)).assertEqual('00:00');
      });
    });

    // ---------- daysBetween ----------
    describe('daysBetween', () => {

      it('同一天应返回0', () => {
        const a = new Date('2025-03-15');
        const b = new Date('2025-03-15');
        expect(daysBetween(a, b)).assertEqual(0);
      });

      it('相差一天的日期应返回1', () => {
        expect(daysBetween(new Date('2025-03-15'), new Date('2025-03-16')))
          .assertEqual(1);
      });

      it('参数顺序不应影响结果', () => {
        const r1 = daysBetween(new Date('2025-01-01'), new Date('2025-01-10'));
        const r2 = daysBetween(new Date('2025-01-10'), new Date('2025-01-01'));
        expect(r1).assertEqual(r2);
      });

      it('跨月的日期计算', () => {
        expect(daysBetween(new Date('2025-01-31'), new Date('2025-02-02')))
          .assertEqual(2);
      });

      it('跨年的日期计算', () => {
        expect(daysBetween(new Date('2024-12-31'), new Date('2025-01-02')))
          .assertEqual(2);
      });

      it('闰年2月29日', () => {
        expect(daysBetween(new Date('2024-02-28'), new Date('2024-03-01')))
          .assertEqual(2);
      });
    });

    // ---------- exponentialBackoff ----------
    describe('exponentialBackoff', () => {

      it('第0次应为初始延迟', () => {
        expect(exponentialBackoff(0, 1000, 30000)).assertEqual(1000);
      });

      it('指数增长: 2^1 = 2000', () => {
        expect(exponentialBackoff(1, 1000, 30000)).assertEqual(2000);
      });

      it('指数增长: 2^3 = 8000', () => {
        expect(exponentialBackoff(3, 1000, 30000)).assertEqual(8000);
      });

      it('应受 maxDelay 上限约束', () => {
        expect(exponentialBackoff(10, 1000, 30000)).assertEqual(30000);
      });

      it('maxDelay为0时不应返回负值', () => {
        const result = exponentialBackoff(5, 100, 0);
        expect(result >= 0).assertTrue();
      });
    });

    // ---------- isAbnormal ----------
    describe('isAbnormal', () => {

      it('在范围内的值应返回 false', () => {
        expect(isAbnormal(36.5, 36.0, 37.3)).assertFalse();
      });

      it('低于最小值应返回 true', () => {
        expect(isAbnormal(35.5, 36.0, 37.3)).assertTrue();
      });

      it('高于最大值应返回 true', () => {
        expect(isAbnormal(37.5, 36.0, 37.3)).assertTrue();
      });

      it('边界—等于最小值应返回 false', () => {
        expect(isAbnormal(90, 90, 140)).assertFalse();
      });

      it('边界—等于最大值应返回 false', () => {
        expect(isAbnormal(140, 90, 140)).assertFalse();
      });

      it('边界—低于最小值1单位', () => {
        expect(isAbnormal(89, 90, 140)).assertTrue();
      });

      it('边界—高于最大值1单位', () => {
        expect(isAbnormal(141, 90, 140)).assertTrue();
      });
    });

  });
}
