/**
 * 卡宝Home - 地图选点页面
 *
 * 使用华为 Map Kit 的 MapComponent 让用户在地图上点击选取位置，
 * 同时支持关键字搜索（site.searchByText）跳转到目标地点。
 *
 * 选点结果通过 AppStorage 回传给调用方：
 *   - kabao_picked_lat (number)
 *   - kabao_picked_lon (number)
 *   - kabao_picked_address (string)
 *   - kabao_picked_token (string)  // 调用方在打开前生成 token，回来后校验，避免读到旧值
 *
 * 调用方使用示例：
 *   const token = generateId('pick');
 *   AppStorage.SetOrCreate('kabao_picked_token_request', token);
 *   router.pushUrl({
 *     url: 'pages/MapPickerPage',
 *     params: { initLat: 31.984, initLon: 118.766, token } as Record<string, Object>
 *   });
 *   // 在 onPageShow 中读取 AppStorage 中 kabao_picked_token 是否等于 token
 */
import { map, mapCommon, MapComponent, site } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { THEME_PALETTES } from '../common/Constants';
import { LocalDbService } from '../service/LocalDbService';

interface SearchHit {
  name: string;
  address: string;
  latitude: number;
  longitude: number;
}

@Entry
@Component
struct MapPickerPage {
  @State pickedLat: number = 0;
  @State pickedLon: number = 0;
  @State pickedAddress: string = '正在定位...';
  @State searchKeyword: string = '';
  @State searchResults: SearchHit[] = [];
  @State showSearchResults: boolean = false;
  @State isSearching: boolean = false;
  @State mapReady: boolean = false;
  @State mapErrorMessage: string = '';
  @State titleText: string = '选择地点';
  @State themePrimary: string = '#E8654A';
  @State themeLightBg: string = '#FFF5F0';
  @State themeBorder: string = '#FFD4C2';

  private token: string = '';
  private mapOptions?: mapCommon.MapOptions;
  private mapController?: map.MapComponentController;
  private mapEventManager?: map.MapEventManager;
  private mapCallback?: AsyncCallback<map.MapComponentController>;
  private db: LocalDbService = LocalDbService.getInstance();

  aboutToAppear(): void {
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themePrimary = palette.primary;
    this.themeLightBg = palette.lightBg;
    this.themeBorder = palette.border;

    const params = router.getParams() as Record<string, Object> | undefined;
    let initLat: number = 39.908823; // 默认天安门
    let initLon: number = 116.397470;
    if (params) {
      const pLat = params['initLat'];
      const pLon = params['initLon'];
      const pToken = params['token'];
      const pTitle = params['title'];
      if (typeof pLat === 'number' && pLat !== 0) {
        initLat = pLat;
      }
      if (typeof pLon === 'number' && pLon !== 0) {
        initLon = pLon;
      }
      if (typeof pToken === 'string') {
        this.token = pToken;
      }
      if (typeof pTitle === 'string') {
        this.titleText = pTitle;
      }
    }
    this.pickedLat = initLat;
    this.pickedLon = initLon;

    const initTarget: mapCommon.LatLng = { latitude: initLat, longitude: initLon };
    const initPos: mapCommon.CameraPosition = { target: initTarget, zoom: 16 };
    this.mapOptions = {
      position: initPos,
      myLocationControlsEnabled: true,
      zoomControlsEnabled: true,
      scaleControlsEnabled: true,
      compassControlsEnabled: false,
      rotateGesturesEnabled: false
    };

    this.mapCallback = async (err: BusinessError, controller: map.MapComponentController) => {
      if (err) {
        this.mapErrorMessage = `地图初始化失败 (code=${err.code})。\n请确认已在 AppGallery Connect 启用 Map Kit 服务，并在 module.json5 配置 client_id。`;
        console.error(`[MapPicker] map init failed: code=${err.code}, msg=${err.message}`);
        return;
      }
      this.mapController = controller;
      this.mapEventManager = controller.getEventManager();
      this.mapReady = true;
      try {
        // 显示我的位置图层（如果有权限）
        controller.setMyLocationEnabled(true);
      } catch (e) {
        // 忽略，权限未给时不显示
      }
      // 监听地图点击 → 更新选中点
      this.mapEventManager?.on('mapClick', (position: mapCommon.LatLng) => {
        this.updatePickedLocation(position.latitude, position.longitude, true);
      });
      // 监听相机移动结束 → 把"中心点"作为选中点（拖动方式选点）
      this.mapEventManager?.on('cameraIdle', () => {
        const cam: mapCommon.CameraPosition | undefined = this.mapController?.getCameraPosition();
        if (cam && cam.target) {
          this.updatePickedLocation(cam.target.latitude, cam.target.longitude, false);
        }
      });
      // 触发一次逆地理编码显示初始地址
      this.reverseGeocodeAndShow(initLat, initLon);
    };
  }

  aboutToDisappear(): void {
    try {
      this.mapEventManager?.off('mapClick');
      this.mapEventManager?.off('cameraIdle');
    } catch (e) {
      // ignore
    }
  }

  /** 更新选中点：反查地址。moveCamera=true 时同步移动相机（点击/搜索场景） */
  private updatePickedLocation(lat: number, lon: number, moveCamera: boolean): void {
    this.pickedLat = lat;
    this.pickedLon = lon;
    if (moveCamera && this.mapController) {
      const target: mapCommon.LatLng = { latitude: lat, longitude: lon };
      const cu = map.newLatLng(target, 16);
      this.mapController.animateCamera(cu, 400);
    }
    this.reverseGeocodeAndShow(lat, lon);
  }

  private async reverseGeocodeAndShow(lat: number, lon: number): Promise<void> {
    try {
      const request: geoLocationManager.ReverseGeoCodeRequest = {
        latitude: lat,
        longitude: lon,
        maxItems: 1
      };
      const results = await geoLocationManager.getAddressesFromLocation(request);
      if (results && results.length > 0) {
        const addr = results[0];
        const parts: string[] = [];
        if (addr.administrativeArea) parts.push(addr.administrativeArea);
        if (addr.locality) parts.push(addr.locality);
        if (addr.subLocality) parts.push(addr.subLocality);
        if (addr.roadName) parts.push(addr.roadName);
        if (addr.placeName) parts.push(addr.placeName);
        this.pickedAddress = parts.length > 0 ? parts.join('') : `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
        return;
      }
    } catch (e) {
      console.warn(`[MapPicker] reverseGeocode failed: ${(e as BusinessError).message}`);
    }
    this.pickedAddress = `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
  }

  /** 关键字搜索（Map Kit Site Search） */
  private async runSearch(): Promise<void> {
    const q = this.searchKeyword.trim();
    if (!q) {
      this.searchResults = [];
      this.showSearchResults = false;
      return;
    }
    this.isSearching = true;
    this.showSearchResults = true;
    try {
      const searchLoc: mapCommon.LatLng = { latitude: this.pickedLat, longitude: this.pickedLon };
      const params: site.SearchByTextParams = {
        query: q,
        location: searchLoc,
        radius: 20000,
        language: 'zh'
      };
      const result: site.SearchByTextResult = await site.searchByText(params);
      const hits: SearchHit[] = [];
      const sites: site.Site[] | undefined = result.sites;
      if (sites && sites.length > 0) {
        for (let i = 0; i < sites.length; i++) {
          const s: site.Site = sites[i];
          const loc: mapCommon.LatLng | undefined = s.location;
          if (!loc) continue;
          const lat: number = loc.latitude;
          const lon: number = loc.longitude;
          if (typeof lat !== 'number' || typeof lon !== 'number') continue;
          const name: string = s.name ?? q;
          const formatAddress: string = s.formatAddress ?? '';
          hits.push({
            name: name,
            address: formatAddress,
            latitude: lat,
            longitude: lon
          });
        }
      }
      this.searchResults = hits;
      if (hits.length === 0) {
        promptAction.showToast({ message: '未找到相关地点', duration: 1500 });
      }
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[MapPicker] searchByText failed code=${err.code}, msg=${err.message}`);
      promptAction.showToast({
        message: `搜索失败：${err.message ?? '请检查网络/Map Kit 配置'}`,
        duration: 2200
      });
      this.searchResults = [];
    } finally {
      this.isSearching = false;
    }
  }

  private pickSearchResult(hit: SearchHit): void {
    this.searchKeyword = hit.name;
    this.showSearchResults = false;
    this.updatePickedLocation(hit.latitude, hit.longitude, true);
    this.pickedAddress = hit.address || hit.name;
  }

  private async moveToMyLocation(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const atManager = abilityAccessCtrl.createAtManager();
      const r = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      const granted = r.authResults.every((x: number) => x === 0);
      if (!granted) {
        promptAction.showToast({ message: '位置权限未开启', duration: 1500 });
        return;
      }
      const loc = await geoLocationManager.getCurrentLocation();
      this.updatePickedLocation(loc.latitude, loc.longitude, true);
    } catch (e) {
      promptAction.showToast({ message: '获取位置失败', duration: 1500 });
    }
  }

  private confirmPick(): void {
    if (!this.pickedLat || !this.pickedLon) {
      promptAction.showToast({ message: '请先选取一个位置', duration: 1200 });
      return;
    }
    AppStorage.setOrCreate<number>('kabao_picked_lat', this.pickedLat);
    AppStorage.setOrCreate<number>('kabao_picked_lon', this.pickedLon);
    AppStorage.setOrCreate<string>('kabao_picked_address', this.pickedAddress);
    AppStorage.setOrCreate<string>('kabao_picked_token', this.token);
    router.back();
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Row() {
            Text('<').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
          }
          .width(34).height(34).borderRadius(17).backgroundColor(this.themeBorder)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { router.back(); })

          Text(this.titleText)
            .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)

          Row() {
            Text('确定').fontSize(14).fontColor(Color.White)
          }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(this.themePrimary)
          .onClick(() => { this.confirmPick(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
        .backgroundColor(Color.White)

        // 搜索栏
        Row({ space: 8 }) {
          TextInput({ text: this.searchKeyword, placeholder: '搜索学校、小区、地标...' })
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .backgroundColor('#F5F5F5')
            .borderRadius(20)
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => { this.searchKeyword = v; })
            .onSubmit(() => { this.runSearch(); })
          Row() {
            Text(this.isSearching ? '搜索中' : '搜索')
              .fontSize(14).fontColor(Color.White)
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(20)
          .backgroundColor(this.themePrimary)
          .onClick(() => { this.runSearch(); })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(Color.White)

        // 地图区域
        Stack({ alignContent: Alignment.Center }) {
          if (this.mapErrorMessage) {
            // 降级提示
            Column({ space: 10 }) {
              Text('🗺️').fontSize(48)
              Text('地图加载失败').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FF5252')
              Text(this.mapErrorMessage)
                .fontSize(13).fontColor('#666666')
                .textAlign(TextAlign.Center)
                .padding({ left: 24, right: 24 })
              Text('您仍可使用「搜索」功能或下方的「我的位置」选点')
                .fontSize(12).fontColor('#999999').margin({ top: 8 })
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#F5F5F5')
          } else {
            MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
              .width('100%')
              .height('100%')

            // 屏幕中心固定的"选点针"图标（drag-style picker）
            Column() {
              Text('📍').fontSize(36)
            }
            .hitTestBehavior(HitTestMode.Transparent)
          }

          // 浮动按钮：定位到我（嵌套一层 Column 用 padding 控制定位避免 position 的兼容差异）
          Column() {
            Row() {
              Text('📍').fontSize(20)
            }
            .width(44).height(44).borderRadius(22).backgroundColor(Color.White)
            .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetY: 2 })
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.moveToMyLocation(); })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.End)
          .padding({ right: 16, bottom: 16 })
          .hitTestBehavior(HitTestMode.Transparent)

          // 搜索结果下拉（覆盖在地图顶部）
          if (this.showSearchResults && this.searchResults.length > 0) {
            Column() {
              Column() {
                Scroll() {
                  Column() {
                    ForEach(this.searchResults, (hit: SearchHit) => {
                      Column({ space: 4 }) {
                        Text(hit.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
                        Text(hit.address || `${hit.latitude.toFixed(4)}, ${hit.longitude.toFixed(4)}`)
                          .fontSize(12).fontColor('#999999')
                          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width('100%')
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                      .border({ width: { bottom: 0.5 }, color: '#EEEEEE' })
                      .onClick(() => { this.pickSearchResult(hit); })
                    }, (hit: SearchHit) => `${hit.latitude}-${hit.longitude}-${hit.name}`)

                    Row() {
                      Text('关闭').fontSize(13).fontColor('#999999')
                    }
                    .width('100%').padding(10).justifyContent(FlexAlign.Center)
                    .onClick(() => { this.showSearchResults = false; })
                  }
                }
                .scrollBar(BarState.Auto)
              }
              .width('92%').constraintSize({ maxHeight: 280 })
              .borderRadius(12)
              .backgroundColor(Color.White)
              .shadow({ radius: 10, color: 'rgba(0,0,0,0.18)', offsetY: 4 })
              .margin({ top: 8 })
            }
            .width('100%').height('100%')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Start)
          }
        }
        .layoutWeight(1)

        // 底部选中信息卡片
        Column({ space: 6 }) {
          Row() {
            Text('📌 当前选中').fontSize(14).fontColor('#666666').layoutWeight(1)
            Text(`${this.pickedLat.toFixed(5)}, ${this.pickedLon.toFixed(5)}`)
              .fontSize(12).fontColor('#999999')
          }
          Text(this.pickedAddress)
            .fontSize(15).fontColor('#333333')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: 10 }) {
            Row() {
              Text('取消').fontSize(15).fontColor('#666666')
            }
            .layoutWeight(1).height(42).borderRadius(21)
            .backgroundColor('#F5F5F5').justifyContent(FlexAlign.Center)
            .onClick(() => { router.back(); })
            Row() {
              Text('确认此位置').fontSize(15).fontColor(Color.White)
            }
            .layoutWeight(2).height(42).borderRadius(21)
            .backgroundColor(this.themePrimary).justifyContent(FlexAlign.Center)
            .onClick(() => { this.confirmPick(); })
          }
          .margin({ top: 6 })
        }
        .width('100%').padding(14).backgroundColor(Color.White)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%').height('100%')
      .backgroundColor(this.themeLightBg)
    }
    .width('100%').height('100%')
  }
}
