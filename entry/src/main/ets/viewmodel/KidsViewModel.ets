/**
 * 孩子事项ViewModel
 */
import { LocalDbService } from '../service/LocalDbService';
import { KidEvent, GrowthRecord } from '../model/KidEvent';
import { FamilyMember } from '../model/FamilyMember';
import { MemberRole } from '../common/Constants';

export class KidsViewModel {
  private db: LocalDbService = LocalDbService.getInstance();

  getKidMembers(): FamilyMember[] {
    const family = this.db.getCurrentFamily();
    if (!family) return [];
    return this.db.getMembersByFamilyId(family.id)
      .filter(m => m.role === MemberRole.CHILD);
  }

  getEventsByMember(memberId: string): KidEvent[] {
    return this.db.getKidEventsByMember(memberId);
  }

  getAllEvents(): KidEvent[] {
    return this.db.getKidEvents();
  }

  async addEvent(event: KidEvent): Promise<void> {
    await this.db.saveKidEvent(event);
  }

  async updateEvent(event: KidEvent): Promise<void> {
    await this.db.updateKidEvent(event);
  }

  getGrowthRecords(memberId: string): GrowthRecord[] {
    return this.db.getGrowthRecordsByMember(memberId);
  }

  async addGrowthRecord(record: GrowthRecord): Promise<void> {
    await this.db.saveGrowthRecord(record);
  }

  async deleteEvent(id: string): Promise<void> {
    await this.db.deleteKidEvent(id);
  }

  async deleteGrowthRecord(id: string): Promise<void> {
    await this.db.deleteGrowthRecord(id);
  }

  getUpcomingEvents(): KidEvent[] {
    const now = new Date().toISOString();
    return this.getAllEvents()
      .filter(e => e.eventTime > now)
      .sort((a, b) => a.eventTime.localeCompare(b.eventTime));
  }

  getEventTypeLabel(type: string): string {
    const map: Record<string, string> = {
      'school': '🏫 学校',
      'activity': '🎨 课外',
      'medical': '🏥 医疗',
      'other': '📌 其他'
    };
    return map[type] ?? type;
  }

  getEventTypeColor(type: string): string {
    const map: Record<string, string> = {
      'school': '#4E6884',       // 雾蓝
      'activity': '#876117',     // 深琥珀
      'medical': '#B8402A',      // 朱红
      'other': '#3D6B5C'         // 墨绿
    };
    return map[type] ?? '#5C5C5C';
  }
}
