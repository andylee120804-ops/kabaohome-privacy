/**
 * 健康用药ViewModel
 */
import { LocalDbService } from '../service/LocalDbService';
import { Medication, MedicationLog } from '../model/Medication';
import { HealthMetric } from '../model/HealthMetric';
import { FamilyMember } from '../model/FamilyMember';
import { Visibility, HEALTH_RANGES, ModuleId } from '../common/Constants';
import { isAbnormal, generateId } from '../common/Utils';

export class HealthViewModel {
  private db: LocalDbService = LocalDbService.getInstance();

  // ---- 用药 ----

  getMedicationsByMember(memberId: string): Medication[] {
    return this.db.getMedicationsByMember(memberId);
  }

  /**
   * 获取健康模块的共享成员列表（可被指派为服药人的候选）
   * 规则：
   * - PRIVATE 或未配置：仅当前用户对应成员
   * - SELECTED：当前用户对应成员 + visibleMemberIds 指定成员
   * - FAMILY：全部家庭成员
   */
  getHealthShareableMembers(): FamilyMember[] {
    const family = this.db.getCurrentFamily();
    if (!family) return [];
    const allMembers = this.db.getMembersByFamilyId(family.id);
    const cfg = this.db.getModuleVisibilityConfig(ModuleId.HEALTH);
    const currentUserId = this.db.getCurrentUserId();
    const me = allMembers.find(m => m.userId === currentUserId);

    if (!cfg || cfg.visibility === Visibility.PRIVATE) {
      return me ? [me] : [];
    }
    if (cfg.visibility === Visibility.FAMILY) {
      return allMembers;
    }
    // SELECTED：当前成员 + 指定成员
    const ids = new Set<string>(cfg.visibleMemberIds);
    if (me) ids.add(me.id);
    return allMembers.filter(m => ids.has(m.id));
  }

  /**
   * 根据健康模块共享配置，构造用药记录的可见性字段
   * visibleMembers 存的是 userId，需把成员ID转换为 userId
   */
  buildVisibilityForNewMedication(): MedVisibility {
    const cfg = this.db.getModuleVisibilityConfig(ModuleId.HEALTH);
    if (!cfg || cfg.visibility === Visibility.PRIVATE) {
      return { visibility: Visibility.PRIVATE, visibleMembers: [] };
    }
    if (cfg.visibility === Visibility.FAMILY) {
      return { visibility: Visibility.FAMILY, visibleMembers: [] };
    }
    // SELECTED：把成员ID转成userId
    const family = this.db.getCurrentFamily();
    const allMembers = family ? this.db.getMembersByFamilyId(family.id) : [];
    const userIds: string[] = [];
    for (const memberId of cfg.visibleMemberIds) {
      const m = allMembers.find(mm => mm.id === memberId);
      if (m && m.userId) userIds.push(m.userId);
    }
    return { visibility: Visibility.SELECTED, visibleMembers: userIds };
  }

  /** 当前用户是否是该药物的创建人 */
  isMedicationCreator(med: Medication): boolean {
    return med.creatorId === this.db.getCurrentUserId();
  }

  /** 当前用户是否是该药物的指派服药人 */
  isMedicationAssignee(med: Medication): boolean {
    const userId = this.db.getCurrentUserId();
    const family = this.db.getCurrentFamily();
    if (!family) return false;
    const members = this.db.getMembersByFamilyId(family.id);
    const me = members.find(m => m.userId === userId);
    return !!me && me.id === med.forMemberId;
  }

  /** 是否可以编辑/删除该用药计划（仅创建人） */
  canEditMedication(med: Medication): boolean {
    return this.isMedicationCreator(med);
  }

  /** 是否可以确认服药（创建人或被指派的服药人） */
  canConfirmMedication(med: Medication): boolean {
    return this.isMedicationCreator(med) || this.isMedicationAssignee(med);
  }

  getAllActiveMedications(): Medication[] {
    return this.db.getMedications().filter(m => m.isActive);
  }

  async addMedication(med: Medication): Promise<void> {
    await this.db.saveMedication(med);
  }

  async toggleMedicationActive(medId: string): Promise<void> {
    const meds = this.db.getMedications();
    const med = meds.find(m => m.id === medId);
    if (med) {
      const now = new Date().toISOString();
      const updated: Medication = {
        id: med.id, familyId: med.familyId, creatorId: med.creatorId,
        visibility: med.visibility, visibleMembers: [...med.visibleMembers],
        version: med.version + 1, createdAt: med.createdAt, updatedAt: now,
        forMemberId: med.forMemberId, medicineName: med.medicineName,
        dosage: med.dosage, frequency: med.frequency, timeSlots: [...med.timeSlots],
        startDate: med.startDate, endDate: med.endDate,
        isActive: !med.isActive, note: med.note
      };
      await this.db.updateMedication(updated);
    }
  }

  // ---- 服药记录 ----

  getTodayLogs(): MedicationLog[] {
    return this.db.getTodayLogs();
  }

  async confirmTaken(medicationId: string, timeSlot: string, takenByMemberId?: string): Promise<void> {
    // 防重复：已确认过则跳过
    if (this.isMedicationTaken(medicationId, timeSlot)) return;

    const userId = this.db.getCurrentUserId();
    const now = new Date().toISOString();
    // 判断是否补服（当前时间超过计划时间2小时以上视为补服）
    const currentHour = new Date().getHours();
    const currentMin = new Date().getMinutes();
    const slotParts = timeSlot.split(':');
    const slotHour = parseInt(slotParts[0]);
    const slotMin = slotParts.length > 1 ? parseInt(slotParts[1]) : 0;
    const currentMinutes = currentHour * 60 + currentMin;
    const slotMinutes = slotHour * 60 + slotMin;
    const isLate = currentMinutes > slotMinutes + 120;

    // 解析实际服药人成员ID：优先用显式传入的成员ID；
    // 其次用该用药的预设服药人（forMemberId）；最后兜底用当前用户对应的成员
    let memberId = takenByMemberId || '';
    if (!memberId) {
      const med = this.db.getMedications().find(m => m.id === medicationId);
      memberId = med?.forMemberId ?? '';
    }
    if (!memberId) {
      // 兜底：从当前 userId 解析出对应的家庭成员ID
      const family = this.db.getCurrentFamily();
      if (family) {
        const members = this.db.getMembersByFamilyId(family.id);
        const me = members.find(m => m.userId === userId);
        memberId = me?.id ?? '';
      }
    }

    const log: MedicationLog = {
      id: generateId('ml'),
      familyId: this.db.getCurrentFamily()?.id ?? '',
      creatorId: userId,
      visibility: Visibility.FAMILY,
      visibleMembers: [],
      version: 1,
      createdAt: now,
      updatedAt: now,
      medicationId,
      timeSlot,
      takenBy: memberId,
      takenAt: now,
      status: isLate ? 'late' : 'taken',
      note: isLate ? '补服' : ''
    };
    await this.db.saveMedicationLog(log);
  }

  isMedicationTaken(medicationId: string, timeSlot: string): boolean {
    const todayLogs = this.getTodayLogs();
    return todayLogs.some(l => l.medicationId === medicationId &&
      l.timeSlot === timeSlot &&
      (l.status === 'taken' || l.status === 'late'));
  }

  isMedicationLate(medicationId: string, timeSlot: string): boolean {
    const todayLogs = this.getTodayLogs();
    return todayLogs.some(l => l.medicationId === medicationId &&
      l.timeSlot === timeSlot && l.status === 'late');
  }

  // ---- 健康指标 ----

  getMetricsByMember(memberId: string): HealthMetric[] {
    return this.db.getHealthMetricsByMember(memberId);
  }

  async addMetric(metric: HealthMetric): Promise<void> {
    await this.db.saveHealthMetric(metric);
  }

  checkAbnormal(metricType: string, value: number): boolean {
    const ranges = HEALTH_RANGES;
    switch (metricType) {
      case 'blood_pressure_systolic':
        return isAbnormal(value, ranges.BLOOD_PRESSURE_SYSTOLIC.min, ranges.BLOOD_PRESSURE_SYSTOLIC.max);
      case 'blood_pressure_diastolic':
        return isAbnormal(value, ranges.BLOOD_PRESSURE_DIASTOLIC.min, ranges.BLOOD_PRESSURE_DIASTOLIC.max);
      case 'blood_sugar':
        return isAbnormal(value, ranges.BLOOD_SUGAR_FASTING.min, ranges.BLOOD_SUGAR_FASTING.max);
      case 'body_temp':
        return isAbnormal(value, ranges.BODY_TEMP.min, ranges.BODY_TEMP.max);
      case 'heart_rate':
        return isAbnormal(value, ranges.HEART_RATE.min, ranges.HEART_RATE.max);
      default:
        return false;
    }
  }

  // ---- 成员相关 ----

  getMembersWithMedication(): FamilyMember[] {
    const meds = this.db.getMedications();
    const memberIds = Array.from(new Set(meds.map(m => m.forMemberId)));
    const family = this.db.getCurrentFamily();
    if (!family) return [];
    const members = this.db.getMembersByFamilyId(family.id);
    return members.filter(m => memberIds.includes(m.id));
  }
}

/** 新建用药记录时的共享可见性字段 */
export interface MedVisibility {
  visibility: Visibility;
  visibleMembers: string[];
}
