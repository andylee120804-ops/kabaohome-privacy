/**
 * 常用地点模型 - 用于地理围栏通知
 * 存储学校、家等常用地点的经纬度和地址
 */
import { BaseRecord } from './BaseRecord';
import { Visibility } from '../common/Constants';

export enum PlaceType {
  HOME = 'HOME',
  SCHOOL = 'SCHOOL',
  OTHER = 'OTHER'
}

export class LocationPlace extends BaseRecord {
  /** 地点名称 */
  name: string = '';
  /** 地点类型 */
  placeType: PlaceType = PlaceType.HOME;
  /** 纬度 */
  latitude: number = 0;
  /** 经度 */
  longitude: number = 0;
  /** 文字地址（逆地理编码或手动输入） */
  address: string = '';
  /** 关联的家庭成员ID（为谁设置的地点，如孩子的学校） */
  forMemberId: string = '';
  /** 围栏半径（米），默认200米 */
  radius: number = 200;
}
