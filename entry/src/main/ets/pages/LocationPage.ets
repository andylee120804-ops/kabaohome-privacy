/**
 * 卡宝Home - 位置共享页面（V2 真实共享版）
 *
 * 核心理念：
 *   - **共享范围在 SettingsPage 开启模块时设置**（和所有其他模块统一逻辑）
 *   - **页面内主开关只是「暂停/恢复共享」**——不影响 SettingsPage 里的可见范围权限
 *   - **单向共享**：对方共享给我 ≠ 我也共享给对方
 *   - **真实数据**：位置经 update-location 云函数上报 Cloud DB（LocationShare），
 *     服务端做可见性过滤 + 到达检测 + 通知推送；家人位置每 30s 主动拉取
 *   - **隐私合规**：首次开启前弹说明框（用途/数据范围/撤回方式），同意后才定位上报
 *
 * 页面结构：
 *   1) 我的位置共享 -- 开关 + 范围(只读) + 到达通知开关（变更即时上云）
 *   2) 地图 -- 我的位置 + 在线家人的真实位置 + 图例
 *   3) 家人位置列表 -- 在线/离线/已暂停/未共享 状态
 *   4) 常用地点 -- 添加只需填名称 + 地图选点（类型自动推断，半径200m；到达检测在服务端）
 */

import { FamilyMember } from '../model/FamilyMember';
import { BG_PAPER, BG_SUBTLE, BORDER_CORAL, BORDER_SUBTLE, BRAND_CORAL, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, SEMANTIC_ERROR, SEMANTIC_SUCCESS, SEMANTIC_WARNING, SUCCESS_BG } from '../common/DesignTokens';
import { LocationPlace, PlaceType } from '../model/LocationPlace';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { LocalDbService, LocationConsent, LocationShareSettings } from '../service/LocalDbService';
import { CloudService, ClientLocationShareRow } from '../service/CloudService';
import { LocationReporter } from '../service/LocationReporter';
import { FontSizeMode, THEME_PALETTES, Visibility, ModuleId , PAGE_TRANSITION_DURATION } from '../common/Constants';
import { generateId, calculateDistance, formatDistance } from '../common/Utils';
import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { curves, router } from '@kit.ArkUI';
import { map, mapCommon, MapComponent } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';

/** 家人位置行（V2：真实数据来自云端 LocationShare，服务端已按可见性过滤） */
interface MemberLocationRow {
  member: FamilyMember;
  /** 云端有该成员的行（= 对方共享给我了位置）；无行 = 未共享 */
  hasRow: boolean;
  /** 对方页内共享开关状态 */
  shareEnabled: boolean;
  /** 对方最新坐标（hasRow 且有值才有效） */
  lat: number;
  lon: number;
  /** 对方最近一次上报时间（ISO） */
  updatedAt: string;
}

/** 在线判定窗口：超过该时长无上报视为离线 */
const ONLINE_WINDOW_MS = 10 * 60 * 1000;
/** 页面可见时的家人位置拉取周期 */
const PULL_INTERVAL_MS = 30 * 1000;

@Entry
@Component
struct LocationPage {
  /** 当前登录用户的账号 ID（用于权限/共享配置） */
  @State currentUserId: string = '';
  @State isSavingPlace: boolean = false;
  /** 当前用户在家庭里的成员 ID（FamilyMember.id；用于把"自己"从家人列表中剔除） */
  @State currentMemberId: string = '';
  @State familyMembers: FamilyMember[] = [];
  @State otherMembers: FamilyMember[] = [];
  @State visibleMemberRows: MemberLocationRow[] = [];
  /** 已共享给我、在线且有坐标的家人（地图图例/标记用——避免在 ForEach 里现 filter） */
  @State mappedMembers: MemberLocationRow[] = [];
  /** 云端原始 LocationShare 行（服务端已按可见性过滤） */
  @State shareRows: ClientLocationShareRow[] = [];

  /** 我的模块共享范围（只读——在 SettingsPage 设置） */
  @State myScopeLabel: string = '尚未设置';
  @State myScopeIsValid: boolean = false;

  /** 运行时暂停/恢复 */
  @State sharingEnabled: boolean = true;
  /** 到达通知 */
  @State notifyOnArrival: boolean = false;

  /** 隐私合规：是否已同意位置共享说明（本机，按当前用户） */
  @State consentGiven: boolean = false;
  @State showConsentDialog: boolean = false;

  /** 主题 */
  @State isLargeFont: boolean = false;
  @State titleFontSize: number = 18;
  @State themeLightBg: string = BG_PAPER;
  @State themePrimary: string = BRAND_CORAL;
  @State themeBorder: string = BORDER_CORAL;

  /** 当前位置 */
  @State currentLat: number = 0;
  @State currentLon: number = 0;
  @State locationText: string = '获取中...';
  /** loading | success | denied | unavailable | noconsent */
  @State locationStatus: string = 'loading';

  /** 常用地点 */
  @State locationPlaces: LocationPlace[] = [];

  /** 添加/编辑地点弹窗 */
  @State showAddPlaceDialog: boolean = false;
  /** 编辑中的地点 */
  @State editingPlace: LocationPlace | null = null;
  @State newPlaceName: string = '';
  @State newPlaceAddress: string = '';
  @State newPlaceLat: string = '';
  @State newPlaceLon: string = '';
  @State newPlaceRadius: string = '200';

  /** 地图 */
  @State mapInitError: string = '';
  @State mapInitialized: boolean = false;

  private familyVm: FamilyViewModel = new FamilyViewModel();
  private db: LocalDbService = LocalDbService.getInstance();
  private cloud: CloudService = CloudService.getInstance();
  private mapPickToken: string = '';
  private pullTimerId: number = -1;
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

    // 隐私同意状态（本机按用户；未同意不定位不上报，开关开启时弹说明框）
    const consent = this.db.getLocationConsent();
    this.consentGiven = !!consent && consent.userId === this.currentUserId;

    // 读取我的模块共享范围（在 SettingsPage 已设置）
    this.refreshMyScopeLabel();

    // 读取运行时设置
    const rt = this.db.getLocationShareSettings(this.currentUserId);
    this.sharingEnabled = rt.shareEnabled;
    this.notifyOnArrival = rt.notifyOnArrival;
    // 上次会话遗留「开着共享但从未同意」：强制回落关闭态，等待用户走同意流程
    if (!this.consentGiven && this.sharingEnabled) {
      this.sharingEnabled = false;
      this.persistRuntimeSettings().catch(() => {});
    }

    // 主题
    this.isLargeFont = me?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themeLightBg = palette.lightBg;
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    if (this.isLargeFont) this.titleFontSize = 22;

    // 常用地点
    this.locationPlaces = this.db.getLocationPlaces();

    // 地图 + 家人位置（真实数据来自云端）
    this.setupMainMap();
    this.startPullTimer();
    this.pullFamilyLocations().catch(() => {});
    if (this.consentGiven) {
      this.requestLocation().catch(() => {});
    } else {
      this.locationStatus = 'noconsent';
    }
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

  // ------------------------------------------------------------------
  // 家人位置（云端真实数据）
  // ------------------------------------------------------------------

  /**
   * 把云端行与家庭成员合并成展示行
   * 服务端已做可见性过滤：拿到的行 = 对方共享给我的人；无行的成员显示「未共享」
   */
  private rebuildMemberRows(): void {
    const rows: MemberLocationRow[] = [];
    for (const m of this.familyMembers) {
      if (this.isSelf(m)) continue;
      let row: ClientLocationShareRow | undefined = undefined;
      for (const sr of this.shareRows) {
        if (sr.memberId === m.id) {
          row = sr;
          break;
        }
      }
      const item: MemberLocationRow = {
        member: m,
        hasRow: row !== undefined,
        shareEnabled: row ? row.shareEnabled : false,
        lat: row ? row.latitude : 0,
        lon: row ? row.longitude : 0,
        updatedAt: row ? row.updatedAt : ''
      };
      rows.push(item);
    }
    this.visibleMemberRows = rows;
    this.mappedMembers = rows.filter(r => this.isRowFreshAndMappable(r));
  }

  /** 地图可标记：有行 + 共享中 + 有有效坐标 + 10 分钟内上报 */
  private isRowFreshAndMappable(row: MemberLocationRow): boolean {
    if (!row.hasRow || !row.shareEnabled) return false;
    if (row.lat === 0 && row.lon === 0) return false;
    if (!row.updatedAt) return false;
    const ts = Date.parse(row.updatedAt);
    if (isNaN(ts)) return false;
    return Date.now() - ts <= ONLINE_WINDOW_MS;
  }

  private async pullFamilyLocations(): Promise<void> {
    const familyId = this.db.getCurrentFamilyId();
    if (!this.cloud.isCloudAvailable() || !familyId) return;
    const rows = await this.cloud.pullLocationShares(familyId);
    this.shareRows = rows;
    this.rebuildMemberRows();
    this.refreshMemberMarkers();
  }

  private startPullTimer(): void {
    if (this.pullTimerId >= 0) return;
    this.pullTimerId = setInterval(() => {
      this.pullFamilyLocations().catch(() => {});
    }, PULL_INTERVAL_MS);
  }

  private stopPullTimer(): void {
    if (this.pullTimerId >= 0) {
      clearInterval(this.pullTimerId);
      this.pullTimerId = -1;
    }
  }

  /** 该行是「在线（有新鲜坐标）」还是「离线」文案 */
  private rowStatusText(row: MemberLocationRow): string {
    if (!row.hasRow) return '未共享位置给你';
    if (!row.shareEnabled) return '已暂停共享';
    if (!row.updatedAt) return '等待位置同步…';
    const ts = Date.parse(row.updatedAt);
    if (isNaN(ts)) return '等待位置同步…';
    const mins = Math.floor((Date.now() - ts) / 60000);
    if (mins < 1) return '刚刚在线';
    if (mins <= 10) return `在线 · ${mins} 分钟前更新`;
    return `${mins} 分钟前在线`;
  }

  /** 最近上报相对时间（供「最后在线」提示） */
  private rowUpdatedText(row: MemberLocationRow): string {
    if (!row.updatedAt) return '';
    const ts = Date.parse(row.updatedAt);
    if (isNaN(ts)) return '';
    const mins = Math.floor((Date.now() - ts) / 60000);
    if (mins < 1) return '刚刚';
    if (mins < 60) return `${mins} 分钟前`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours} 小时前`;
    return `${Math.floor(hours / 24)} 天前`;
  }

  // ------------------------------------------------------------------
  // 隐私同意 + 运行时设置
  // ------------------------------------------------------------------

  /** 页内开关开启：未同意先弹说明框；共享范围无效（未开模块/仅自己）不给开启 */
  private async handleShareToggle(isOn: boolean): Promise<void> {
    if (!isOn) {
      this.sharingEnabled = false;
      await this.persistRuntimeSettings();
      // 暂停共享：先落盘 pending 再冲刷上云（家人马上看到「已暂停」；失败跨重启也会重试）
      LocationReporter.getInstance().scheduleFlush().catch(() => {});
      return;
    }
    if (!this.myScopeIsValid) {
      this.sharingEnabled = false;
      await this.persistRuntimeSettings();
      return;
    }
    if (!this.consentGiven) {
      this.showConsentDialog = true;
      return;
    }
    this.sharingEnabled = true;
    await this.persistRuntimeSettings();
    await this.requestLocationAndReport().catch(() => {});
  }

  private async handleArrivalToggle(isOn: boolean): Promise<void> {
    this.notifyOnArrival = isOn;
    await this.persistRuntimeSettings();
    // 立即把新开关状态推上云（服务端到达检测按 arrivalNotifyEnabled 生效）
    LocationReporter.getInstance().reportNow().catch(() => {});
  }

  private async acceptConsent(): Promise<void> {
    const consent: LocationConsent = { userId: this.currentUserId, grantedAt: Date.now() };
    await this.db.saveLocationConsent(consent);
    this.consentGiven = true;
    this.showConsentDialog = false;
    if (!this.myScopeIsValid) {
      this.sharingEnabled = false;
      await this.persistRuntimeSettings();
      return;
    }
    this.sharingEnabled = true;
    await this.persistRuntimeSettings();
    await this.requestLocationAndReport().catch(() => {});
  }

  private async refuseConsent(): Promise<void> {
    this.showConsentDialog = false;
    this.sharingEnabled = false;
    await this.persistRuntimeSettings();
  }

  /** 定位成功或开关开启后：定位（内部含立即上报 + 拉家人位置） */
  private async requestLocationAndReport(): Promise<void> {
    if (!this.consentGiven) {
      this.locationStatus = 'noconsent';
      return;
    }
    await this.requestLocation();
  }

  /**
   * 持久化运行时设置（保留式合并：不覆盖共享范围与 LocationReporter 记住的
   * 上次坐标；调用方 await 保证写入完成后上报器读到新值）
   */
  private async persistRuntimeSettings(): Promise<void> {
    const cur = this.db.getLocationShareSettings(this.currentUserId);
    const s: LocationShareSettings = {
      shareEnabled: this.sharingEnabled,
      visibility: cur.visibility,
      visibleMembers: cur.visibleMembers,
      notifyOnArrival: this.notifyOnArrival,
      lastNotifiedAt: cur.lastNotifiedAt,
      lastLat: cur.lastLat,
      lastLon: cur.lastLon,
      lastReportAt: cur.lastReportAt,
      cloudSharePending: cur.cloudSharePending
    };
    await this.db.saveLocationShareSettings(this.currentUserId, s);
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
      if (!this.isRowFreshAndMappable(row)) continue;
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
    this.startPullTimer();
    this.pullFamilyLocations().catch(() => {});

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

  onPageHide(): void {
    // 页面不可见（跳转/退后台）时停止家人位置轮询
    this.stopPullTimer();
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
    const inferredType = this.inferPlaceType(this.newPlaceName);
    const title = inferredType === PlaceType.HOME ? '选择家的位置'
      : inferredType === PlaceType.SCHOOL ? '选择学校位置' : '选择地点';
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
    // 合规：未同意位置共享说明前不发起定位（同意后才弹系统权限框）
    if (!this.consentGiven) {
      this.locationStatus = 'noconsent';
      this.locationText = '开启共享并同意说明后开始定位';
      return;
    }
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
      // 定位成功：立即上报一次（云端覆盖写 + 服务端到达检测），再拉家人最新位置
      LocationReporter.getInstance().reportNow(this.currentLat, this.currentLon,
        loc.accuracy ?? 0).catch(() => {});
      await this.pullFamilyLocations().catch(() => {});
    } catch (_) {
      this.locationStatus = 'unavailable';
      this.locationText = '位置获取失败';
    }
  }

  // ------------------------------------------------------------------
  // 常用地点
  // ------------------------------------------------------------------

  private getPlaceTypeName(type: PlaceType): string {
    switch (type) {
      case PlaceType.HOME: return '家';
      case PlaceType.SCHOOL: return '学校';
      default: return '其他';
    }
  }

  private getPlaceTypeIcon(type: PlaceType): string {
    switch (type) {
      case PlaceType.HOME: return '🏠';
      case PlaceType.SCHOOL: return '🏫';
      default: return '📍';
    }
  }

  /** 根据名称推断地点类型（简化表单：去掉类型选择器后自动推断） */
  private inferPlaceType(name: string): PlaceType {
    if (name.includes('家')) return PlaceType.HOME;
    if (name.includes('校')) return PlaceType.SCHOOL;
    return PlaceType.OTHER;
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
    return this.db.isRecordCreator(creatorId);
  }

  private resetAddPlaceForm(): void {
    this.newPlaceName = '';
    this.newPlaceAddress = '';
    this.newPlaceLat = '';
    this.newPlaceLon = '';
    this.newPlaceRadius = '200';
    this.editingPlace = null;
  }

  private openAddPlaceDialog(): void {
    this.resetAddPlaceForm();
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
    this.newPlaceLat = place.latitude.toFixed(6);
    this.newPlaceLon = place.longitude.toFixed(6);
    this.newPlaceRadius = place.radius.toString();
    this.showAddPlaceDialog = true;
  }

  private async savePlace(): Promise<void> {
    const lat = parseFloat(this.newPlaceLat);
    const lon = parseFloat(this.newPlaceLon);
    if (isNaN(lat) || isNaN(lon) || lat === 0 || lon === 0) {
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
        name: this.newPlaceName || this.getPlaceTypeName(this.inferPlaceType(this.newPlaceName)),
        address: address,
        placeType: this.inferPlaceType(this.newPlaceName),
        forMemberId: this.editingPlace.forMemberId,
        latitude: lat,
        longitude: lon,
        radius: radius,
        updatedAt: now
      };
      await this.db.updateLocationPlace(updated);
    } else {
      const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.LOCATION);
      const inferredType = this.inferPlaceType(this.newPlaceName);
      const newPlace: LocationPlace = {
        id: generateId('place'),
        familyId: familyId,
        creatorId: this.db.getCurrentMemberId(),
        name: this.newPlaceName || this.getPlaceTypeName(inferredType),
        placeType: inferredType,
        address: address,
        forMemberId: this.currentUserId,
        latitude: lat,
        longitude: lon,
        radius: radius,
        visibility: vis.visibility,
        visibleMembers: vis.visibleMembers,
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

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
  }

  build() {
    Column() {
      this.TitleBar()

      Scroll() {
        Column({ space: 14 }) {
          // 1) 我的位置共享（开关 + 范围，直接操作，不再弹窗）
          this.MyShareSection()
          // 2) 家人在哪（地图 + 列表）
          this.MapCard()
          this.FamilyLocationsCard()
          // 3) 常用地点（到达通知）
          this.FrequentPlacesCard()
        }
        .padding(16).width('100%').alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1).align(Alignment.TopStart)

      if (this.showAddPlaceDialog) {
        this.AddPlaceDialog()
      }

      if (this.showConsentDialog) {
        this.ConsentDialog()
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
        .fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK)
        .layoutWeight(1).textAlign(TextAlign.Center)

      // 右上角显示「N 位家人共享中」
      Row({ space: 4 }) {
        Circle().width(8).height(8)
          .fill(this.mappedMembers.length > 0 ? SEMANTIC_SUCCESS : NEUTRAL_INK_SECONDARY)
        Text(`${this.mappedMembers.length}`).fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  /** 我的位置共享（内联开关 + 范围 + 到达通知，无需弹窗） */
  @Builder
  MyShareSection() {
    Column({ space: 12 }) {
      // 开关：共享 / 暂停我的位置
      Row() {
        Text(this.sharingEnabled ? '🟢' : '⚪').fontSize(18).margin({ right: 8 })
        Column() {
          Text('共享我的位置').fontSize(15).fontColor(NEUTRAL_INK)
          Text(this.sharingEnabled
            ? (this.myScopeIsValid ? '共享给：' + this.myScopeLabel : '范围未设置')
            : '已暂停，无人可见你的位置')
            .fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: $$this.sharingEnabled })
          .onChange((isOn: boolean) => {
            this.handleShareToggle(isOn).catch(() => {});
          })
      }.width('100%')

      Divider().color(BORDER_SUBTLE).strokeWidth(0.5)

      // 共享范围（只读，在「我的」修改）
      Row() {
        Column() {
          Text('共享范围').fontSize(14).fontColor(NEUTRAL_INK)
          Text('在「我的-模块管理」中修改').fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.myScopeLabel).fontSize(13)
          .fontColor(this.myScopeIsValid ? this.themePrimary : SEMANTIC_WARNING)
          .onClick(() => {
            router.pushUrl({ url: 'pages/SettingsPage' }).catch(() => {});
          })
      }.width('100%')

      // 到达通知（仅共享开启时可用）
      Row() {
        Column() {
          Text('到达自动通知').fontSize(14).fontColor(NEUTRAL_INK)
          Text('到达常用地点时提醒共享名单').fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: $$this.notifyOnArrival })
          .enabled(this.sharingEnabled)
          .onChange((isOn: boolean) => {
            this.handleArrivalToggle(isOn).catch(() => {});
          })
      }.width('100%')
    }
    .width('100%').padding(14).borderRadius(12).backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  /** 区块 1：地图 + 家人位置 + 图例（自己的位置只用蓝点定位，不单独显示坐标） */
  @Builder
  MapCard() {
    Column({ space: 8 }) {
      Row() {
        Text('🗺️ 家人位置').fontSize(16).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).layoutWeight(1)
        Text('刷新').fontSize(13).fontColor(this.themePrimary)
          .onClick(() => { this.requestLocation(); })
      }.width('100%')

      // 状态行（只在异常时显示）
      if (this.locationStatus === 'noconsent') {
        Row({ space: 6 }) {
          Text('开启位置共享前需先阅读并同意说明').fontSize(13).fontColor(SEMANTIC_WARNING).layoutWeight(1)
          Text('去开启').fontSize(12).fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12).backgroundColor(this.themePrimary)
            .onClick(() => {
              this.showConsentDialog = true;
            })
        }.width('100%')
      } else if (this.locationStatus === 'loading') {
        Text('正在获取位置...').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
      } else if (this.locationStatus !== 'success') {
        Row({ space: 6 }) {
          Text('⚠️ 位置权限未开启').fontSize(13).fontColor(SEMANTIC_WARNING).layoutWeight(1)
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
            Text('地图加载失败').fontSize(15).fontColor(SEMANTIC_ERROR).margin({ top: 8 })
            Text(this.mapInitError).fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(12)
        } else {
          MapComponent({
            mapOptions: this.mainMapOptions,
            mapCallback: this.mainMapCallback
          }).width('100%').height('100%')

          Column() {
            Row() { Text('🟢').fontSize(18) }
              .width(38).height(38).borderRadius(19).backgroundColor(Color.White)
              .shadow({ radius: 6, offsetY: 2 })
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
      .backgroundColor(SUCCESS_BG)

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
        Text('🟢 实时位置：').fontSize(11).fontColor(NEUTRAL_INK_SECONDARY)
        ForEach(this.mappedMembers, (row: MemberLocationRow) => {
          Text(`${row.member.avatar}${row.member.name} `).fontSize(11).fontColor(NEUTRAL_INK)
        }, (row: MemberLocationRow) => row.member.id + '_' + row.updatedAt)
      }
      .width('100%').padding({ top: 2 })
    } else if (this.visibleMemberRows.length > 0) {
      Text('家人暂无实时位置（打开页面后每 30 秒自动刷新）')
        .fontSize(11).fontColor(NEUTRAL_INK_SECONDARY)
        .width('100%').padding({ top: 2 })
    }
  }

  /** 区块 2：家人位置列表 */
  @Builder
  FamilyLocationsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('👥 家人').fontSize(16).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).layoutWeight(1)
        Text(`${this.mappedMembers.length} 位实时在线`).fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
      }.width('100%')

      ForEach(this.visibleMemberRows, (row: MemberLocationRow) => {
        this.MemberRowItem(row)
      }, (row: MemberLocationRow) => row.member.id + '_' + (row.updatedAt || 'no'))
    }
    .width('100%').padding(14).borderRadius(12).backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MemberRowItem(row: MemberLocationRow) {
    Row() {
      Text(row.member.avatar).fontSize(24).margin({ right: 10 })
      Column() {
        Text(row.member.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
        if (row.hasRow && row.shareEnabled && this.isRowFreshAndMappable(row)) {
          Text(`📍 ${row.lat.toFixed(4)}, ${row.lon.toFixed(4)}`)
            .fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        } else if (row.hasRow && !row.shareEnabled) {
          Text('已暂停共享，看不到位置').fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        } else if (row.hasRow && row.updatedAt) {
          Text(`最后在线：${this.rowUpdatedText(row)}`)
            .fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        } else {
          Text(this.rowStatusText(row)).fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (row.hasRow && row.shareEnabled) {
        if (this.isRowFreshAndMappable(row)) {
          Row() {
            Circle().width(8).height(8).fill(SEMANTIC_SUCCESS)
            Text('在线').fontSize(12).fontColor(SEMANTIC_SUCCESS).margin({ left: 4 })
          }
        } else {
          Text(this.rowUpdatedText(row) ? `离线(${this.rowUpdatedText(row)})` : '离线')
            .fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
        }
      } else if (!row.hasRow) {
        Text('未共享').fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
      } else {
        Text('已暂停').fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
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
          Text('📌 常用地点').fontSize(16).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK)
          Text('到达时自动通知共享名单').fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('+ 添加').fontSize(14).fontColor(this.themePrimary)
          .onClick(() => { this.openAddPlaceDialog(); })
      }.width('100%')

      if (this.locationPlaces.length === 0) {
        Text('暂无常用地点，点右上角「+ 添加」')
          .fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 14, bottom: 6 })
      } else {
        ForEach(this.locationPlaces, (place: LocationPlace) => {
          this.PlaceRowItem(place)
        }, (place: LocationPlace) => place.id + '_' + place.updatedAt)
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
          Text(place.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(NEUTRAL_INK)
          if (this.isPlaceInGeofence(place)) {
            Text('已到达').fontSize(11).fontColor(SEMANTIC_SUCCESS)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(8).backgroundColor(SUCCESS_BG)
          }
        }
        Text(place.address || `${place.latitude.toFixed(4)}, ${place.longitude.toFixed(4)}`)
          .fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`距我 ${this.getDistanceText(place)} · 围栏 ${place.radius}m`)
          .fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      if (this.isCreator(place.creatorId)) {
        Column({ space: 4 }) {
          Text('编辑').fontSize(12).fontColor(this.themePrimary)
            .onClick(() => { this.openEditPlaceDialog(place); })
          Text('删除').fontSize(12).fontColor(SEMANTIC_ERROR)
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
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK)
          .width('100%').textAlign(TextAlign.Center)

        // 名称（类型根据名称自动推断：含"家"=家，含"校"=学校，其余=其他）
        Column({ space: 4 }) {
          Text('名称').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
          TextInput({ text: this.newPlaceName })
            .fontSize(16)
            .onChange((v: string) => { this.newPlaceName = v; })
        }

        // 地图选点（核心步骤）
        Column({ space: 6 }) {
          Text('位置').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
          Row() {
            Column() {
              if (this.newPlaceLat && this.newPlaceLon) {
                Text(this.newPlaceAddress || this.newPlaceLat + ', ' + this.newPlaceLon)
                  .fontSize(14).fontColor(NEUTRAL_INK)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              } else {
                Text('点击右侧按钮在地图上选择').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY)
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
          .width('100%').padding(10).borderRadius(10).backgroundColor(BG_SUBTLE)
        }

        Row({ space: 12 }) {
          Row() {
            Text('取消').fontSize(16).fontColor(NEUTRAL_INK_SECONDARY)
          }
          .layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor(BG_SUBTLE).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.showAddPlaceDialog = false;
            this.resetAddPlaceForm();
          })

          Row() {
            Text(this.isSavingPlace ? '保存中...' : (this.editingPlace ? '保存' : '添加')).fontSize(16).fontColor(Color.White)
          }
          .layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor(this.themePrimary).justifyContent(FlexAlign.Center)
          .enabled(!this.isSavingPlace)
          .onClick(async () => {
            if (this.isSavingPlace) return; // 防重复提交
            this.isSavingPlace = true;
            try {
              await this.savePlace();
            } finally {
              this.isSavingPlace = false;
            }
          })
        }
      }
      .width('90%').padding(20).borderRadius(16).backgroundColor(Color.White)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
  }

  // ------------------------------------------------------------------
  // 隐私合规同意弹窗（华为要求：首次开启位置共享前须明确同意并说明用途）
  // ------------------------------------------------------------------
  @Builder
  ConsentDialog() {
    Column() {
      Column({ space: 14 }) {
        Text('开启位置共享前请确认')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK)
          .width('100%').textAlign(TextAlign.Center)

        Column({ space: 10 }) {
          Text('· 按你设置的共享范围，家人可实时看到你的位置')
            .fontSize(13).fontColor(NEUTRAL_INK).lineHeight(20)
          Text('· 你到达常用地点（围栏）时，会通知共享名单中的家人')
            .fontSize(13).fontColor(NEUTRAL_INK).lineHeight(20)
          Text('· 仅上报最新坐标，云端不保存轨迹；App 退到后台即停止上报')
            .fontSize(13).fontColor(NEUTRAL_INK).lineHeight(20)
          Text('· 可随时在本页关闭共享，或到系统设置中关闭定位权限')
            .fontSize(13).fontColor(NEUTRAL_INK).lineHeight(20)
        }
        .width('100%').alignItems(HorizontalAlign.Start)

        Row({ space: 12 }) {
          Row() {
            Text('不同意').fontSize(16).fontColor(NEUTRAL_INK_SECONDARY)
          }
          .layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor(BG_SUBTLE).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.refuseConsent().catch(() => {});
          })

          Row() {
            Text('同意并继续').fontSize(16).fontColor(Color.White)
          }
          .layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor(this.themePrimary).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.acceptConsent().catch(() => {});
          })
        }.width('100%')
      }
      .width('90%').padding(20).borderRadius(16).backgroundColor(Color.White)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
  }
}