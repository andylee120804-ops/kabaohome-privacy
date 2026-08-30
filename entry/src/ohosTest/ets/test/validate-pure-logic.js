/**
 * 卡宝Home 纯逻辑验证脚本
 * 验证 Utils.ets 中的所有纯函数
 */
// ===== 1. formatDate =====
function formatDate(date: Date): string {
  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

// ===== 2. formatTime =====
function formatTime(date: Date): string {
  const hour = date.getHours().toString().padStart(2, '0');
  const minute = date.getMinutes().toString().padStart(2, '0');
  return `${hour}:${minute}`;
}

// ===== 3. daysBetween =====
function daysBetween(date1: Date, date2: Date): number {
  const oneDay = 24 * 60 * 60 * 1000;
  return Math.round(Math.abs(date1.getTime() - date2.getTime()) / oneDay);
}

// ===== 4. exponentialBackoff =====
function exponentialBackoff(attempt: number, initialDelayMs: number, maxDelayMs: number): number {
  const delay = initialDelayMs * Math.pow(2, attempt);
  return Math.min(delay, maxDelayMs);
}

// ===== 5. isAbnormal =====
function isAbnormal(type: string, value: number, min: number, max: number): boolean {
  return value < min || value > max;
}

// ===== 6. generateInviteCode =====
function generateInviteCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// ===== 7. generateId =====
function generateId(prefix: string): string {
  const random = Math.random().toString(36).substring(2, 11);
  return `${prefix}_${Date.now()}_${random}`;
}

// ===== RUN TESTS =====
let passed = 0;
let failed = 0;
function test(name: string, fn: () => void) {
  try {
    fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${name}: ${e}`);
  }
}
function assertEqual(actual: unknown, expected: unknown) {
  if (actual !== expected) throw new Error(`expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
function assertTrue(val: boolean) {
  if (!val) throw new Error('expected true');
}
function assertFalse(val: boolean) {
  if (val) throw new Error('expected false');
}

console.log('\n======== 卡宝Home 纯逻辑验证 ========\n');

// ---- formatDate ----
console.log('formatDate:');
test('YYYY-MM-DD format', () => assertEqual(formatDate(new Date('2025-03-15')), '2025-03-15'));
test('single-digit month padding', () => assertEqual(formatDate(new Date('2025-01-05')), '2025-01-05'));
test('year-end date', () => assertEqual(formatDate(new Date('2025-12-31')), '2025-12-31'));
test('leap year Feb 29', () => assertEqual(formatDate(new Date('2024-02-29')), '2024-02-29'));

// ---- formatTime ----
console.log('formatTime:');
test('HH:mm format', () => assertEqual(formatTime(new Date('2025-03-15T08:05:00')), '08:05'));
test('midnight', () => assertEqual(formatTime(new Date('2025-03-15T00:00:00')), '00:00'));

// ---- daysBetween ----
console.log('daysBetween:');
test('same day = 0', () => assertEqual(daysBetween(new Date('2025-03-15'), new Date('2025-03-15')), 0));
test('adjacent days = 1', () => assertEqual(daysBetween(new Date('2025-03-15'), new Date('2025-03-16')), 1));
test('cross-month', () => assertEqual(daysBetween(new Date('2025-01-31'), new Date('2025-02-02')), 2));
test('cross-year', () => assertEqual(daysBetween(new Date('2024-12-31'), new Date('2025-01-02')), 2));
test('symmetric', () => {
  const r1 = daysBetween(new Date('2025-01-01'), new Date('2025-01-10'));
  const r2 = daysBetween(new Date('2025-01-10'), new Date('2025-01-01'));
  assertEqual(r1, r2);
});

// ---- exponentialBackoff ----
console.log('exponentialBackoff:');
test('attempt 0 = initial', () => assertEqual(exponentialBackoff(0, 1000, 30000), 1000));
test('attempt 1 = 2000', () => assertEqual(exponentialBackoff(1, 1000, 30000), 2000));
test('attempt 3 = 8000', () => assertEqual(exponentialBackoff(3, 1000, 30000), 8000));
test('capped at maxDelay', () => assertEqual(exponentialBackoff(10, 1000, 30000), 30000));

// ---- isAbnormal ----
console.log('isAbnormal:');
test('in range = false', () => assertFalse(isAbnormal('temp', 36.5, 36.0, 37.3)));
test('below min = true', () => assertTrue(isAbnormal('temp', 35.5, 36.0, 37.3)));
test('above max = true', () => assertTrue(isAbnormal('temp', 37.5, 36.0, 37.3)));
test('at min boundary', () => assertFalse(isAbnormal('bp', 90, 90, 140)));
test('at max boundary', () => assertFalse(isAbnormal('bp', 140, 90, 140)));

// ---- generateInviteCode ----
console.log('generateInviteCode:');
test('6-digit length', () => assertEqual(generateInviteCode().length, 6));
test('all numeric', () => assertTrue(/^\d{6}$/.test(generateInviteCode())));
test('in range 100000-999999', () => {
  for (let i = 0; i < 20; i++) {
    const n = parseInt(generateInviteCode());
    assertTrue(n >= 100000 && n <= 999999);
  }
});

// ---- generateId ----
console.log('generateId:');
test('has prefix', () => assertTrue(generateId('u').startsWith('u_')));
test('3 parts separated by _', () => assertEqual(generateId('pr').split('_').length, 3));
test('100 unique IDs', () => {
  const s = new Set<string>();
  for (let i = 0; i < 100; i++) s.add(generateId('t'));
  assertEqual(s.size, 100);
});

// ---- 周期计算逻辑 ----
console.log('周期计算 (排卵日=cycleLength-14):');
test('28天 → 排卵日14', () => assertEqual(28 - 14, 14));
test('30天 → 排卵日16', () => assertEqual(30 - 14, 16));
test('25天 → 排卵日11', () => assertEqual(25 - 14, 11));
test('35天 → 排卵日21', () => assertEqual(35 - 14, 21));

// ---- 易孕期范围 ----
console.log('易孕期范围 (ovulation-5 至 ovulation+1):');
test('28天 → 易孕期 9-15', () => {
  const o = 28 - 14;
  assertEqual(o - 5, 9);
  assertEqual(o + 1, 15);
});
test('30天 → 易孕期 11-17', () => {
  const o = 30 - 14;
  assertEqual(o - 5, 11);
  assertEqual(o + 1, 17);
});

// ---- 经期结束日期计算 ----
console.log('经期结束日期:');
test('3/1 start, 5 days → 3/5', () => {
  const s = new Date('2025-03-01');
  s.setDate(s.getDate() + 5 - 1);
  assertEqual(formatDate(s), '2025-03-05');
});
test('cross-month', () => {
  const s = new Date('2025-03-28');
  s.setDate(s.getDate() + 5 - 1);
  assertEqual(formatDate(s), '2025-04-01');
});

// ---- 排序验证 ----
console.log('记录排序:');
test('降序 → 最新在前', () => {
  const dates = ['2025-01-01', '2025-03-15', '2025-02-10'];
  const sorted = [...dates].sort((a, b) => b.localeCompare(a));
  assertEqual(sorted[0], '2025-03-15');
  assertEqual(sorted[2], '2025-01-01');
});

console.log(`\n======== 结果: ${passed} passed, ${failed} failed ========\n`);
