/**
 * 卡宝Home - 位置共享页面（V2 重设计）
 *
 * 核心理念：
 *   - **共享范围在 SettingsPage 开启模块时设置**（和所有其他模块统一逻辑）
 *   - **页面内主开关只是「暂停/恢复共享」**——不影响 SettingsPage 里的可见范围权限
 *   - **单向共享**：对方共享给我 ≠ 我也共享给对方
 *
 * 页面结构：
 *   1) 我的共享 —— 暂停/恢复开关 + 当前共享范围(只读) + 到达通知
 *   2) 地图 —— 我的位置 + 已共享给我的家人位置（带姓名标记）+ 图例
 *   3) 家人位置列表 —— 谁共享给我了，谁没共享
 *   4) 常用地点 —— 到达通知触发器
 */
import { FamilyMember } from '../model/FamilyMember';
import { LocationPlace, PlaceType } from '../model/LocationPlace';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { LocalDbService, defaultLocationShareSettings, ArrivalNotificationRecord } from '../service/LocalDbService';
import { EmptyState } from '../components/EmptyState';
import { FontSizeMode, THEME_PALETTES, Visibility, ModuleId } from '../common/Constants';
import { generateId, calculateDistance, formatDistance } from '../common/Utils';
import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { map, mapCommon, MapComponent } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';

/** ForEach 数据源常量（ArkTS strict 禁止内联字面量） */
const PLACE_TYPE_OPTIONS: PlaceType[] = [PlaceType.HOME, PlaceType.SCHOOL, PlaceType.OTHER];

/** 家人位置行 */
interface MemberLocationRow {
  member: FamilyMember;
  /** 我能否看到这位家人的位置（来自对方的 ModuleVisibility(LOCATION) ） */
  visibleToMe: boolean;
  /** 对方的最新坐标（V1 本地模拟为 undefined；V2 由云端推送） */
  lat?: number;
  lon?: number;
  updatedAt?: string;
}

@Entry
@Component
struct LocationPage {
  /** 当前登录用户的账号 ID（用于权限/共享配置） */
  @State currentUserId: string = '';
  /** 当前用户在家庭里的成员 ID（FamilyMember.id；用于把"自己"从家人列表中剔除） */
  @State currentMemberId: string = '';
  @State familyMembers: FamilyMember[] = [];
  @State otherMembers: FamilyMember[] = [];
  @State visibleMemberRows: MemberLocationRow[] = [];
  /** 已共享给我且有位置的家人（地图图例用——避免在 ForEach 里现 filter） */
  @State mappedMembers: MemberLocationRow[] = [];

  /** 我的模块共享范围（只读——在 SettingsPage 设置） */
  @State myScopeLabel: string = '尚未设置';
  @State myScopeIsValid: boolean = false;

  /** 运行时暂停/恢复 */
  @State sharingEnabled: boolean = true;
  /** 到达通知 */
  @State notifyOnArrival: boolean = false;
  /** 到达通知防抖记录 */
  @State lastNotifiedAt: ArrivalNotificationRecord[] = [];

  /** 主题 */
  @State isLargeFont: boolean = false;
  @State titleFontSize: number = 18;
  @State themeLightBg: string = '#FFF5F0';
  @State themePrimary: string = '#E8654A';
  @State themeBorder: string = '#FFD4C2';

  /** 当前位置 */
  @State currentLat: number = 0;
  @State currentLon: number = 0;
  @State locationText: string = '获取中...';
  @State locationStatus: string = 'loading';

  /** 常用地点 */
  @State locationPlaces: LocationPlace[] = [];

  /** 添加/编辑地点弹窗 */
  @State showAddPlaceDialog: boolean = false;
  /** 我的共享详情弹窗（点击底部 compact 卡片打开） */
  @State showMyShareDialog: boolean = false;
  @State editingPlace: LocationPlace | null = null;
  @State newPlaceName: string = '';
  @State newPlaceAddress: string = '';
  @State newPlaceType: PlaceType = PlaceType.HOME;
  @State newPlaceLat: string = '';
  @State newPlaceLon: string = '';
  @State newPlaceRadius: string = '200';

  /** 地图 */
  @State mapInitError: string = '';
  @State mapInitialized: boolean = false;

  private familyVm: FamilyViewModel = new FamilyViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private mapPickToken: string = '';
  private mainMapOptions?: mapCommon.MapOptions;
  private mainMapController?: map.MapComponentController;
  private mainMapCallback?: AsyncCallback<map.MapComponentController>;
  private placeMarkers: map.Marker[] = [];
  private memberMarkers: map.Marker[] = [];

  aboutToAppear(): void {
    this.currentUserId = this.db.getCurrentUserId();
    this.familyMembers = this.familyVm.getFamilyMembers();

    // 取当前成员（注意：FamilyMember.id ≠ userId；只有通过 currentMember.id 才能正确剔除自己）
    const me = this.familyVm.getCurrentMember();
    this.currentMemberId = me?.id ?? '';
    this.otherMembers = this.familyMembers.filter(m => !this.isSelf(m));

    // 读取我的模块共享范围（在 SettingsPage 已设置）
    this.refreshMyScopeLabel();

    // 读取运行时设置
    const rt = this.db.getLocationShareSettings(this.currentUserId);
    this.sharingEnabled = rt.shareEnabled;
    this.notifyOnArrival = rt.notifyOnArrival;
    this.lastNotifiedAt = rt.lastNotifiedAt ?? [];

    // 主题
    this.isLargeFont = me?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themeLightBg = palette.lightBg;
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    if (this.isLargeFont) this.titleFontSize = 22;

    // 常用地点
    this.locationPlaces = this.db.getLocationPlaces();

    // 计算可见家人 + 注入 mock 位置
    this.recomputeVisibleMemberRows();

    // 地图 + 定位
    this.setupMainMap();
    this.requestLocation().catch(() => {});
  }

  // ------------------------------------------------------------------
  // 共享逻辑
  // ------------------------------------------------------------------

  /** 判断某成员是否是当前登录用户本人——优先匹配成员 id，回退匹配 userId */
  private isSelf(member: FamilyMember): boolean {
    if (this.currentMemberId && member.id === this.currentMemberId) return true;
    if (this.currentUserId && member.userId === this.currentUserId) return true;
    return false;
  }

  private refreshMyScopeLabel(): void {
    const cfg = this.db.getModuleVisibilityConfig(ModuleId.LOCATION);
    if (!cfg) {
      this.myScopeLabel = '尚未设置（请到「我的」开启模块）';
      this.myScopeIsValid = false;
      return;
    }
    switch (cfg.visibility) {
      case Visibility.PRIVATE:
        this.myScopeLabel = '仅自己';
        this.myScopeIsValid = false;
        break;
      case Visibility.FAMILY:
        this.myScopeLabel = '家庭所有人';
        this.myScopeIsValid = true;
        break;
      case Visibility.SELECTED: {
        const names = this.familyMembers
          .filter(m => cfg.visibleMemberIds.includes(m.id))
          .map(m => m.name);
        if (names.length === 0) {
          this.myScopeLabel = '指定成员（未选）';
          this.myScopeIsValid = false;
        } else if (names.length <= 2) {
          this.myScopeLabel = names.join('、');
          this.myScopeIsValid = true;
        } else {
          this.myScopeLabel = `${names.slice(0, 2).join('、')} 等 ${names.length} 人`;
          this.myScopeIsValid = true;
        }
        break;
      }
      default:
        this.myScopeLabel = '仅自己';
        this.myScopeIsValid = false;
    }
  }

  /**
   * 判断成员 owner 是否把 LOCATION 模块共享给了 meId
   *
   * V1 实现：本地只能读取当前用户的 ModuleVisibility 配置，无法读到其他家人的配置。
   * 因此 V1 采用「默认 FAMILY 可见」策略：所有家庭成员相互可见，方便演示。
   * V2 接入云端后，应通过云端拉取每个成员的 ModuleVisibility 做真实过滤。
   *
   * 自己始终不出现在「家人位置」列表里。
   */
  private isMemberSharingTo(owner: FamilyMember, meId: string): boolean {
    if (this.isSelf(owner)) return false;
    // V1 mock：演示阶段假设所有家庭成员相互可见
    return true;
  }

  private recomputeVisibleMemberRows(): void {
    const rows: MemberLocationRow[] = [];
    for (const m of this.familyMembers) {
      if (this.isSelf(m)) continue;
      const visible = this.isMemberSharingTo(m, this.currentUserId);
      const row: MemberLocationRow = {
        member: m,
        visibleToMe: visible
      };
      // V1 mock：给可见成员注入一个围绕当前位置的随机偏移坐标，方便看到效果
      if (visible && this.locationStatus === 'success') {
        const seed = this.stringHash(m.id);
        const dLat = ((seed % 100) - 50) / 5000; // ±0.01 度（约 ±1km）
        const dLon = (((seed >> 7) % 100) - 50) / 5000;
        row.lat = this.currentLat + dLat;
        row.lon = this.currentLon + dLon;
        row.updatedAt = new Date().toISOString();
      }
      rows.push(row);
    }
    this.visibleMemberRows = rows;
    this.mappedMembers = rows.filter(r => r.visibleToMe && typeof r.lat === 'number' && typeof r.lon === 'number');
  }

  /** 简单字符串 hash（无随机性，保证同 id 同位置） */
  private stringHash(s: string): number {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h) + s.charCodeAt(i);
      h |= 0;
    }
    return Math.abs(h);
  }

  // ------------------------------------------------------------------
  // 运行时设置持久化
  // ------------------------------------------------------------------

  private persistRuntimeSettings(): void {
    const s = defaultLocationShareSettings();
    s.shareEnabled = this.sharingEnabled;
    s.notifyOnArrival = this.notifyOnArrival;
    s.lastNotifiedAt = this.lastNotifiedAt;
    this.db.saveLocationShareSettings(this.currentUserId, s).catch((e: Error) => {
      console.warn(`[LocationPage] persist failed: ${e?.message}`);
    });
  }

  // ------------------------------------------------------------------
  // 到达通知
  // ------------------------------------------------------------------

  private async checkArrivalNotification(): Promise<void> {
    if (!this.sharingEnabled || !this.notifyOnArrival) return;
    if (this.locationStatus !== 'success') return;
    const now = Date.now();
    const COOLDOWN_MS = 30 * 60 * 1000;
    const records = this.lastNotifiedAt.slice();
    let changed = false;
    for (const p of this.locationPlaces) {
      if (!p.latitude || !p.longitude) continue;
      const dist = calculateDistance(this.currentLat, this.currentLon, p.latitude, p.longitude);
      if (dist > p.radius) continue;
      const idx = records.findIndex(item => item.placeId === p.id);
      const last = idx >= 0 ? records[idx].notifiedAt : 0;
      if (now - last < COOLDOWN_MS) continue;
      const item: ArrivalNotificationRecord = { placeId: p.id, notifiedAt: now };
      if (idx >= 0) {
        records[idx] = item;
      } else {
        records.push(item);
      }
      changed = true;
      promptAction.showToast({
        message: `已到达「${p.name}」，将通知 ${this.myScopeLabel}`,
        duration: 2000
      });
    }
    if (changed) {
      this.lastNotifiedAt = records;
      this.persistRuntimeSettings();
    }
  }

  // ------------------------------------------------------------------
  // 地图
  // ------------------------------------------------------------------

  private setupMainMap(): void {
    const defaultTarget: mapCommon.LatLng = { latitude: 39.908823, longitude: 116.397470 };
    const defaultPos: mapCommon.CameraPosition = { target: defaultTarget, zoom: 12 };
    this.mainMapOptions = {
      position: defaultPos,
      myLocationControlsEnabled: false,
      zoomControlsEnabled: false,
      scaleControlsEnabled: false,
      compassControlsEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false
    };
    this.mainMapCallback = async (err: BusinessError, controller: map.MapComponentController) => {
      if (err) {
        this.mapInitError = `地图加载失败 (code=${err.code})`;
        return;
      }
      this.mainMapController = controller;
      this.mapInitialized = true;
      try { controller.setMyLocationEnabled(true); } catch (_) {}
      if (this.locationStatus === 'success') this.flyToCurrentLocation();
      this.refreshPlaceMarkers();
      this.refreshMemberMarkers();
    };
  }

  private flyToCurrentLocation(): void {
    if (!this.mainMapController || this.locationStatus !== 'success') return;
    const target: mapCommon.LatLng = { latitude: this.currentLat, longitude: this.currentLon };
    this.mainMapController.animateCamera(map.newLatLng(target, 14), 600);
  }

  private async refreshPlaceMarkers(): Promise<void> {
    if (!this.mainMapController) return;
    for (const m of this.placeMarkers) { try { m.remove(); } catch (_) {} }
    this.placeMarkers = [];
    for (const p of this.locationPlaces) {
      if (!p.latitude || !p.longitude) continue;
      try {
        const opt: mapCommon.MarkerOptions = {
          position: { latitude: p.latitude, longitude: p.longitude },
          title: `${this.getPlaceTypeIcon(p.placeType)} ${p.name}`,
          clickable: true
        };
        const marker = await this.mainMapController.addMarker(opt);
        this.placeMarkers.push(marker);
      } catch (_) {}
    }
  }

  private async refreshMemberMarkers(): Promise<void> {
    if (!this.mainMapController) return;
    for (const m of this.memberMarkers) { try { m.remove(); } catch (_) {} }
    this.memberMarkers = [];
    for (const row of this.visibleMemberRows) {
      if (!row.visibleToMe) continue;
      if (typeof row.lat !== 'number' || typeof row.lon !== 'number') continue;
      try {
        const opt: mapCommon.MarkerOptions = {
          position: { latitude: row.lat, longitude: row.lon },
          title: `${row.member.avatar} ${row.member.name}`,
          clickable: true
        };
        const marker = await this.mainMapController.addMarker(opt);
        this.memberMarkers.push(marker);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------
  // 权限 + 定位
  // ------------------------------------------------------------------

  onPageShow(): void {
    // 设置页可能修改了共享范围，每次显示都刷新一下
    this.refreshMyScopeLabel();
    this.recomputeVisibleMemberRows();

    if (!this.mapPickToken) return;
    const returnedToken = AppStorage.get<string>('kabao_picked_token');
    if (returnedToken !== this.mapPickToken) return;
    const lat = AppStorage.get<number>('kabao_picked_lat');
    const lon = AppStorage.get<number>('kabao_picked_lon');
    const address = AppStorage.get<string>('kabao_picked_address');
    if (typeof lat === 'number' && typeof lon === 'number') {
      this.newPlaceLat = lat.toFixed(6);
      this.newPlaceLon = lon.toFixed(6);
      if (address && !this.newPlaceAddress) this.newPlaceAddress = address;
    }
    AppStorage.setOrCreate<string>('kabao_picked_token', '');
    this.mapPickToken = '';
  }

  private openMapPicker(): void {
    this.mapPickToken = generateId('pick');
    let initLat = 0;
    let initLon = 0;
    if (this.newPlaceLat && this.newPlaceLon) {
      initLat = parseFloat(this.newPlaceLat);
      initLon = parseFloat(this.newPlaceLon);
    } else if (this.locationStatus === 'success') {
      initLat = this.currentLat;
      initLon = this.currentLon;
    }
    const title = this.newPlaceType === PlaceType.HOME ? '选择家的位置'
      : this.newPlaceType === PlaceType.SCHOOL ? '选择学校位置' : '选择地点';
    const params: Record<string, Object> = {
      'initLat': initLat, 'initLon': initLon,
      'token': this.mapPickToken, 'title': title
    };
    router.pushUrl({ url: 'pages/MapPickerPage', params: params });
  }

  private async requestLocationPermission(): Promise<boolean> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      return result.authResults.every((r: number) => r === 0);
    } catch (_) {
      return false;
    }
  }

  private async requestLocation(): Promise<void> {
    const granted = await this.requestLocationPermission();
    if (!granted) {
      this.locationStatus = 'denied';
      this.locationText = '位置权限未开启';
      return;
    }
    try {
      const loc = await geoLocationManager.getCurrentLocation();
      this.currentLat = loc.latitude;
      this.currentLon = loc.longitude;
      this.locationText = `${loc.latitude.toFixed(4)}, ${loc.longitude.toFixed(4)}`;
      this.locationStatus = 'success';
      if (this.mapInitialized) this.flyToCurrentLocation();
      // 重新计算家人 mock 坐标（因为依赖当前位置）
      this.recomputeVisibleMemberRows();
      this.refreshMemberMarkers();
      this.checkArrivalNotification().catch(() => {});
    } catch (_) {
      this.locationStatus = 'unavailable';
      this.locationText = '位置获取失败';
    }
  }

  // ------------------------------------------------------------------
  // 常用地点
  // ------------------------------------------------------------------

  private getPlaceTypeIcon(type: PlaceType): string {
    switch (type) {
      case PlaceType.HOME: return '🏠';
      case PlaceType.SCHOOL: return '🏫';
      default: return '📍';
    }
  }

  private getPlaceTypeName(type: PlaceType): string {
    switch (type) {
      case PlaceType.HOME: return '家';
      case PlaceType.SCHOOL: return '学校';
      default: return '其他';
    }
  }

  private getDistanceText(place: LocationPlace): string {
    if (this.locationStatus !== 'success' || place.latitude === 0) return '--';
    return formatDistance(calculateDistance(this.currentLat, this.currentLon, place.latitude, place.longitude));
  }

  private isPlaceInGeofence(place: LocationPlace): boolean {
    if (this.locationStatus !== 'success' || place.latitude === 0) return false;
    return calculateDistance(this.currentLat, this.currentLon, place.latitude, place.longitude) <= place.radius;
  }

  private isCreator(creatorId: string): boolean {
    return creatorId === this.currentUserId;
  }

  private resetAddPlaceForm(): void {
    this.newPlaceName = '';
    this.newPlaceAddress = '';
    this.newPlaceType = PlaceType.HOME;
    this.newPlaceLat = '';
    this.newPlaceLon = '';
    this.newPlaceRadius = '200';
    this.editingPlace = null;
  }

  private openAddPlaceDialog(preType?: PlaceType): void {
    this.resetAddPlaceForm();
    if (preType) {
      this.newPlaceType = preType;
      this.newPlaceName = preType === PlaceType.HOME ? '家'
        : preType === PlaceType.SCHOOL ? '学校' : '';
    }
    if (this.locationStatus === 'success') {
      this.newPlaceLat = this.currentLat.toFixed(6);
      this.newPlaceLon = this.currentLon.toFixed(6);
    }
    this.showAddPlaceDialog = true;
  }

  private openEditPlaceDialog(place: LocationPlace): void {
    this.editingPlace = place;
    this.newPlaceName = place.name;
    this.newPlaceAddress = place.address;
    this.newPlaceType = place.placeType;
    this.newPlaceLat = place.latitude.toFixed(6);
    this.newPlaceLon = place.longitude.toFixed(6);
    this.newPlaceRadius = place.radius.toString();
    this.showAddPlaceDialog = true;
  }

  private async savePlace(): Promise<void> {
    const lat = parseFloat(this.newPlaceLat);
    const lon = parseFloat(this.newPlaceLon);
    if (isNaN(lat) || isNaN(lon) || lat === 0 || lon === 0) {
      promptAction.showToast({ message: '请先在地图上选择位置', duration: 1500 });
      return;
    }
    const radius = parseInt(this.newPlaceRadius) || 200;
    const address = this.newPlaceAddress;
    const familyId = this.db.getCurrentFamilyId();
    const now = new Date().toISOString();

    if (this.editingPlace) {
      const updated: LocationPlace = {
        id: this.editingPlace.id,
        familyId: this.editingPlace.familyId,
        creatorId: this.editingPlace.creatorId,
        visibility: this.editingPlace.visibility,
        visibleMembers: this.editingPlace.visibleMembers,
        version: this.editingPlace.version,
        createdAt: this.editingPlace.createdAt,
        name: this.newPlaceName || this.getPlaceTypeName(this.newPlaceType),
        address: address,
        placeType: this.newPlaceType,
        forMemberId: this.editingPlace.forMemberId,
        latitude: lat,
        longitude: lon,
        radius: radius,
        updatedAt: now
      };
      await this.db.updateLocationPlace(updated);
    } else {
      const newPlace: LocationPlace = {
        id: generateId('place'),
        familyId: familyId,
        creatorId: this.currentUserId,
        name: this.newPlaceName || this.getPlaceTypeName(this.newPlaceType),
        placeType: this.newPlaceType,
        address: address,
        forMemberId: this.currentUserId,
        latitude: lat,
        longitude: lon,
        radius: radius,
        visibility: Visibility.FAMILY,
        visibleMembers: [],
        version: 1,
        createdAt: now,
        updatedAt: now
      };
      await this.db.saveLocationPlace(newPlace);
    }
    this.locationPlaces = this.db.getLocationPlaces();
    this.showAddPlaceDialog = false;
    this.resetAddPlaceForm();
    this.refreshPlaceMarkers();
  }

  private async deletePlace(place: LocationPlace): Promise<void> {
    await this.db.deleteLocationPlace(place.id);
    this.locationPlaces = this.db.getLocationPlaces();
    this.refreshPlaceMarkers();
  }

  // ==================================================================
  // UI
  // ==================================================================

  build() {
    Column() {
      this.TitleBar()

      Scroll() {
        Column({ space: 14 }) {
          // 主要：家人在哪
          this.MapCard()
          this.FamilyLocationsCard()
          this.FrequentPlacesCard()
          // 次要：我自己的共享状态（折叠成一张精简卡）
          this.MyShareCompactCard()

          Text('提示：共享范围在「我的」页面设置位置模块时确定。分享是单向的——对方共享给你 ≠ 你共享给对方')
            .fontSize(12).fontColor('#999999').textAlign(TextAlign.Center)
            .margin({ top: 4, bottom: 8 }).width('100%')
        }
        .padding(16).width('100%').alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1).align(Alignment.TopStart)

      if (this.showAddPlaceDialog) {
        this.AddPlaceDialog()
      }
      if (this.showMyShareDialog) {
        this.MyShareDialog()
      }
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
    .backgroundColor(this.themeLightBg)
  }

  @Builder
  TitleBar() {
    Row() {
      Row() {
        Text('<').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
      }
      .width(34).height(34).borderRadius(17)
      .backgroundColor(this.themeBorder)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { router.back(); })

      Text('📍 位置共享')
        .fontSize(this.titleFontSize).fontWeight(FontWeight.Bold)
        .layoutWeight(1).textAlign(TextAlign.Center)

      // 右上角显示「N 位家人共享中」
      Row({ space: 4 }) {
        Circle().width(8).height(8)
          .fill(this.mappedMembers.length > 0 ? '#4CAF50' : '#CCCCCC')
        Text(`${this.mappedMembers.length}`).fontSize(13).fontColor('#666666')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  /** 我的共享 —— 底部精简卡片，单行展示状态，点击查看详情/调整 */
  @Builder
  MyShareCompactCard() {
    Row({ space: 10 }) {
      Text(this.sharingEnabled ? '🟢' : '⚪').fontSize(16)
      Column() {
        Text('我的位置共享').fontSize(14).fontColor('#333333')
        Text(this.sharingEnabled
          ? (this.myScopeIsValid
            ? `共享给 ${this.myScopeLabel}${this.notifyOnArrival ? ' · 到达自动通知' : ''}`
            : '未设置共享范围')
          : '已暂停')
          .fontSize(12).fontColor('#999999').margin({ top: 2 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      Text('管理 >').fontSize(13).fontColor(this.themePrimary)
    }
    .width('100%').padding(14).borderRadius(12).backgroundColor(Color.White)
    .onClick(() => { this.showMyShareDialog = true; })
  }

  /** 我的共享详情弹窗（暂停/恢复 + 范围跳转 + 到达通知开关） */
  @Builder
  MyShareDialog() {
    Column() {
      Column({ space: 12 }) {
        Text('我的位置共享')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
          .width('100%').textAlign(TextAlign.Center)

        // 暂停/恢复
        Row() {
          Column() {
            Text('共享我的位置').fontSize(15).fontColor('#333333')
            Text(this.sharingEnabled
              ? (this.myScopeIsValid ? `已共享给：${this.myScopeLabel}` : '范围未设置——暂无共享对象')
              : '已暂停——无人可见你的位置')
              .fontSize(12).fontColor('#999999').margin({ top: 2 })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.sharingEnabled })
            .onChange((isOn: boolean) => {
              this.sharingEnabled = isOn;
              this.persistRuntimeSettings();
            })
        }.width('100%')

        Divider().color('#F0F0F0').strokeWidth(0.5)

        // 共享范围（只读 + 去设置）
        Row() {
          Column() {
            Text('共享范围').fontSize(15).fontColor('#333333')
            Text(this.myScopeLabel).fontSize(12)
              .fontColor(this.myScopeIsValid ? this.themePrimary : '#FF9800')
              .margin({ top: 2 })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('去设置 >').fontSize(13).fontColor(this.themePrimary)
            .onClick(() => {
              this.showMyShareDialog = false;
              router.pushUrl({ url: 'pages/SettingsPage' }).catch(() => {
                promptAction.showToast({ message: '请前往「我的」页面调整', duration: 1500 });
              });
            })
        }.width('100%')

        Divider().color('#F0F0F0').strokeWidth(0.5)

        // 到达通知
        Row() {
          Column() {
            Text('到达自动通知').fontSize(15).fontColor('#333333')
            Text('到达常用地点时通知共享名单').fontSize(12).fontColor('#999999').margin({ top: 2 })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.notifyOnArrival })
            .enabled(this.sharingEnabled)
            .onChange((isOn: boolean) => {
              this.notifyOnArrival = isOn;
              this.persistRuntimeSettings();
            })
        }.width('100%')

        Row() {
          Text('完成').fontSize(16).fontColor(Color.White)
        }
        .width('100%').height(44).borderRadius(22)
        .backgroundColor(this.themePrimary).justifyContent(FlexAlign.Center)
        .onClick(() => { this.showMyShareDialog = false; })
      }
      .width('88%').padding(20).borderRadius(16).backgroundColor(Color.White)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
  }

  /** 区块 1：地图 + 家人位置 + 图例（自己的位置只用蓝点定位，不单独显示坐标） */
  @Builder
  MapCard() {
    Column({ space: 8 }) {
      Row() {
        Text('🗺️ 家人位置').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        Text('刷新').fontSize(13).fontColor(this.themePrimary)
          .onClick(() => { this.requestLocation(); })
      }.width('100%')

      // 状态行（只在异常时显示）
      if (this.locationStatus === 'loading') {
        Text('正在获取位置...').fontSize(13).fontColor('#999999')
      } else if (this.locationStatus !== 'success') {
        Row({ space: 6 }) {
          Text('⚠️ 位置权限未开启').fontSize(13).fontColor('#FF9800').layoutWeight(1)
          Text('重新获取').fontSize(12).fontColor(this.themePrimary)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12).border({ width: 1, color: this.themePrimary })
            .onClick(() => { this.requestLocation(); })
        }.width('100%')
      }

      // 地图
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.mapInitError) {
          Column() {
            Text('🗺️').fontSize(40)
            Text('地图加载失败').fontSize(15).fontColor('#FF5252').margin({ top: 8 })
            Text(this.mapInitError).fontSize(12).fontColor('#999999')
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(12)
        } else {
          MapComponent({
            mapOptions: this.mainMapOptions,
            mapCallback: this.mainMapCallback
          }).width('100%').height('100%')

          Column() {
            Row() { Text('📍').fontSize(18) }
              .width(38).height(38).borderRadius(19).backgroundColor(Color.White)
              .shadow({ radius: 6, color: 'rgba(0,0,0,0.15)', offsetY: 2 })
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.flyToCurrentLocation(); })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.End)
          .padding({ right: 10, bottom: 10 })
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%').height(220).borderRadius(10).clip(true)
      .backgroundColor('#E8F5E9')

      // 地图图例：哪些人的位置已标记
      this.MapLegend()
    }
    .width('100%').padding(14).borderRadius(12).backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  /** 地图图例：列出当前地图上标注的家人（不含我自己） */
  @Builder
  MapLegend() {
    if (this.mappedMembers.length > 0) {
      Row() {
        Text('🟢 已共享给你：').fontSize(11).fontColor('#666666')
        ForEach(this.mappedMembers, (row: MemberLocationRow) => {
          Text(`${row.member.avatar}${row.member.name} `).fontSize(11).fontColor('#333333')
        }, (row: MemberLocationRow) => row.member.id)
      }
      .width('100%').padding({ top: 2 })
    } else if (this.visibleMemberRows.length > 0) {
      Text('暂无家人共享位置给你').fontSize(11).fontColor('#999999')
        .width('100%').padding({ top: 2 })
    }
  }

  /** 区块 2：家人位置列表 */
  @Builder
  FamilyLocationsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('👥 家人').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
        Text(`${this.mappedMembers.length} 位已共享`).fontSize(12).fontColor('#999999')
      }.width('100%')

      if (this.visibleMemberRows.length === 0) {
        EmptyState({ icon: '👨‍👩‍👧', title: '暂无其他家庭成员', subtitle: '邀请家人加入家庭吧' })
      } else {
        ForEach(this.visibleMemberRows, (row: MemberLocationRow) => {
          this.MemberRowItem(row)
        }, (row: MemberLocationRow) => row.member.id)
      }
    }
    .width('100%').padding(14).borderRadius(12).backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MemberRowItem(row: MemberLocationRow) {
    Row() {
      Text(row.member.avatar).fontSize(24).margin({ right: 10 })
      Column() {
        Text(row.member.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
        if (row.visibleToMe) {
          if (typeof row.lat === 'number' && typeof row.lon === 'number') {
            Text(`📍 ${row.lat.toFixed(4)}, ${row.lon.toFixed(4)}`)
              .fontSize(12).fontColor('#666666').margin({ top: 2 })
          } else {
            Text('等待位置同步…').fontSize(12).fontColor('#999999').margin({ top: 2 })
          }
        } else {
          Text('未共享位置给你').fontSize(12).fontColor('#BBBBBB').margin({ top: 2 })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (row.visibleToMe) {
        Row() {
          Circle().width(8).height(8).fill('#4CAF50')
          Text('在线').fontSize(12).fontColor('#4CAF50').margin({ left: 4 })
        }
      } else {
        Text('—').fontSize(14).fontColor('#CCCCCC')
      }
    }
    .width('100%').padding({ top: 10, bottom: 10 })
  }

  /** 区块 4：常用地点 */
  @Builder
  FrequentPlacesCard() {
    Column({ space: 10 }) {
      Row() {
        Column() {
          Text('📌 常用地点').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#333333')
          Text('到达时自动通知共享名单').fontSize(12).fontColor('#999999').margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('+ 添加').fontSize(14).fontColor(this.themePrimary)
          .onClick(() => { this.openAddPlaceDialog(); })
      }.width('100%')

      if (this.locationPlaces.length === 0) {
        Row({ space: 8 }) {
          Row() {
            Text('🏠 添加家').fontSize(13).fontColor(this.themePrimary)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(18).border({ width: 1, color: this.themePrimary })
          .onClick(() => { this.openAddPlaceDialog(PlaceType.HOME); })

          Row() {
            Text('🏫 添加学校').fontSize(13).fontColor(this.themePrimary)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(18).border({ width: 1, color: this.themePrimary })
          .onClick(() => { this.openAddPlaceDialog(PlaceType.SCHOOL); })
        }.margin({ top: 4 })
      } else {
        ForEach(this.locationPlaces, (place: LocationPlace) => {
          this.PlaceRowItem(place)
        }, (place: LocationPlace) => place.id)
      }
    }
    .width('100%').padding(14).borderRadius(12).backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PlaceRowItem(place: LocationPlace) {
    Row() {
      Text(this.getPlaceTypeIcon(place.placeType)).fontSize(24).margin({ right: 10 })
      Column() {
        Row({ space: 6 }) {
          Text(place.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
          if (this.isPlaceInGeofence(place)) {
            Text('已到达').fontSize(11).fontColor('#4CAF50')
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(8).backgroundColor('#E8F5E9')
          }
        }
        Text(place.address || `${place.latitude.toFixed(4)}, ${place.longitude.toFixed(4)}`)
          .fontSize(12).fontColor('#999999').margin({ top: 2 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`距我 ${this.getDistanceText(place)} · 围栏 ${place.radius}m`)
          .fontSize(11).fontColor('#BBBBBB').margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (this.isCreator(place.creatorId)) {
        Column({ space: 4 }) {
          Text('编辑').fontSize(12).fontColor(this.themePrimary)
            .onClick(() => { this.openEditPlaceDialog(place); })
          Text('删除').fontSize(12).fontColor('#FF5252')
            .onClick(() => { this.deletePlace(place); })
        }
      }
    }
    .width('100%').padding({ top: 10, bottom: 10 })
  }

  // ------------------------------------------------------------------
  // 弹窗：添加/编辑地点
  // ------------------------------------------------------------------
  @Builder
  AddPlaceDialog() {
    Column() {
      Column({ space: 14 }) {
        Text(this.editingPlace ? '编辑地点' : '添加常用地点')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
          .width('100%').textAlign(TextAlign.Center)

        // 类型
        Column({ space: 6 }) {
          Text('类型').fontSize(13).fontColor('#666666')
          Row({ space: 8 }) {
            ForEach(PLACE_TYPE_OPTIONS, (type: PlaceType) => {
              Row() {
                Text(`${this.getPlaceTypeIcon(type)} ${this.getPlaceTypeName(type)}`)
                  .fontSize(14)
                  .fontColor(this.newPlaceType === type ? Color.White : '#333333')
              }
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(20)
              .backgroundColor(this.newPlaceType === type ? this.themePrimary : '#F5F5F5')
              .onClick(() => {
                this.newPlaceType = type;
                if (!this.newPlaceName
                  || this.newPlaceName === '家'
                  || this.newPlaceName === '学校'
                  || this.newPlaceName === '其他') {
                  this.newPlaceName = this.getPlaceTypeName(type);
                }
              })
            }, (type: PlaceType) => `${type}`)
          }
        }

        // 名称
        Column({ space: 4 }) {
          Text('名称').fontSize(13).fontColor('#666666')
          TextInput({ text: this.newPlaceName, placeholder: '如：家、学校' })
            .fontSize(16)
            .onChange((v: string) => { this.newPlaceName = v; })
        }

        // 地图选点
        Column({ space: 6 }) {
          Text('位置').fontSize(13).fontColor('#666666')
          Row() {
            Column() {
              if (this.newPlaceLat && this.newPlaceLon) {
                Text(this.newPlaceAddress || `${this.newPlaceLat}, ${this.newPlaceLon}`)
                  .fontSize(14).fontColor('#333333')
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`📍 ${this.newPlaceLat}, ${this.newPlaceLon}`)
                  .fontSize(11).fontColor('#999999').margin({ top: 2 })
              } else {
                Text('尚未选择位置').fontSize(14).fontColor('#999999')
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Row() {
              Text(this.newPlaceLat ? '重新选点' : '🗺️ 地图选点')
                .fontSize(13).fontColor(Color.White)
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(18).backgroundColor(this.themePrimary)
            .onClick(() => { this.openMapPicker(); })
          }
          .width('100%').padding(10).borderRadius(10).backgroundColor('#F8F8F8')
        }

        // 围栏半径
        Column({ space: 4 }) {
          Text('围栏半径（米）').fontSize(13).fontColor('#666666')
          TextInput({ text: this.newPlaceRadius, placeholder: '200' })
            .fontSize(16).type(InputType.Number)
            .onChange((v: string) => { this.newPlaceRadius = v; })
          Text('建议 100~500 米').fontSize(11).fontColor('#BBBBBB')
        }

        Row({ space: 12 }) {
          Row() {
            Text('取消').fontSize(16).fontColor('#666666')
          }
          .layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor('#F5F5F5').justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showAddPlaceDialog = false;
            this.resetAddPlaceForm();
          })

          Row() {
            Text(this.editingPlace ? '保存' : '添加').fontSize(16).fontColor(Color.White)
          }
          .layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor(this.themePrimary).justifyContent(FlexAlign.Center)
          .onClick(() => { this.savePlace(); })
        }
      }
      .width('90%').padding(20).borderRadius(16).backgroundColor(Color.White)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
  }
}
