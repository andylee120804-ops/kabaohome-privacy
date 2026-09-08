/**
 * 卡宝Home - 家庭相册页面
 * 设计：Direction C · 极简编辑风（纸白底 + 墨黑正文 + flat 分隔线）
 * 照片选择 + 事件归档 + 成员筛选 + 时间线展示
 */
import { Photo } from '../model/Photo';
import { PhotoComment } from '../model/PhotoComment';
import {
  BG_PAPER, BG_CARD, BG_SUBTLE, DIVIDER, BORDER_SUBTLE,
  NEUTRAL_INK, NEUTRAL_INK_SECONDARY, NEUTRAL_INK_TERTIARY,
  BRAND_RED, BRAND_RED_LG, SEMANTIC_ERROR, SEMANTIC_INFO,
  FONT_BODY, FONT_BODY_LARGE, FONT_CAPTION, FONT_CAPTION_SM, FONT_TITLE,
  FONT_FAMILY_SERIF, SPACE_MD, SPACE_LG, getModuleIconRes
} from '../common/DesignTokens';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { AuthService } from '../service/AuthService';
import { EmptyState } from '../components/EmptyState';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { FontSizeMode, PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import { generateId, toDateAtLocalMidnight, formatIsoToLocal, toLocalDateKey } from '../common/Utils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { promptAction } from '@kit.ArkUI';

interface TagOption {
  tag: string;
  label: string;
}

interface ImageSize {
  width: number;
  height: number;
}

@Entry
@Component
struct AlbumPage {
  @State photos: Photo[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State selectedMemberFilter: string = '';
  @State isRefreshing: boolean = false;
  @State showFullscreenZoom: boolean = false;
  @State zoomScale: number = 1;
  @State showAddDialog: boolean = false;
  @State isSavingPhoto: boolean = false;
  @State newDescription: string = '';
  @State newEventTag: string = '';
  @State selectedPhotoUri: string = '';
  @State showPhotoViewer: boolean = false;
  @State viewerPhoto: Photo | null = null;
  @State showEditDialog: boolean = false;
  @State editDesc: string = '';
  @State editTag: string = '';
  @State isSavingEdit: boolean = false;
  @State isLargeFont: boolean = false;
  @State fontSize: number = FONT_BODY_LARGE;
  @State titleFontSize: number = FONT_TITLE;
  @State currentViewMode: number = 0;
  @State isFamilyOwner: boolean = false;
  @State compactGroups: boolean = false;
  private wallBusy: string = '';
  @State viewerLikes: PhotoComment[] = [];
  @State viewerComments: PhotoComment[] = [];
  @State viewerLikedByMe: boolean = false;
  @State commentInput: string = '';
  @State isSendingComment: boolean = false;
  @State isTogglingLike: boolean = false;

  private db: LocalDbService = LocalDbService.getInstance();
  private familyVm: FamilyViewModel = new FamilyViewModel();

  private tagOptions: TagOption[] = [
    { tag: '', label: '无' },
    { tag: '春游', label: '🌸 春游' },
    { tag: '生日', label: '🎂 生日' },
    { tag: '聚会', label: '🎉 聚会' },
    { tag: '日常', label: '☀️ 日常' },
    { tag: '旅行', label: '✈️ 旅行' },
    { tag: '节日', label: '🎊 节日' }
  ];

  private isCreator(creatorId: string): boolean {
    return this.db.isRecordCreator(creatorId);
  }

  aboutToAppear(): void {
    this.photos = this.db.getPhotos();
    this.familyMembers = this.familyVm.getFamilyMembers();
    this.isFamilyOwner = AuthService.getInstance().isCreator();
    this.compactGroups = this.db.getSetting('album_compact_groups', false);
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
    CloudService.getInstance().syncPendingPhotoUploads().then((count: number) => {
      if (count > 0) {
        this.photos = this.db.getPhotos();
      }
    });
    const family = this.db.getCurrentFamily();
    if (family) {
      CloudService.getInstance().pullPhotos(family.id).then((merged: number) => {
        if (merged > 0) {
          this.photos = this.db.getPhotos();
          if (this.viewerPhoto) {
            this.refreshViewerInteractions(this.viewerPhoto.id);
          }
        }
      });
    }
  }

  private async handlePullRefresh(): Promise<void> {
    try {
      const familyId = this.db.getCurrentFamilyId();
      if (familyId && CloudService.getInstance().isCloudAvailable()) {
        await CloudService.getInstance().syncAll(familyId, true);
      }
    } finally {
      this.isRefreshing = false;
      this.photos = this.db.getPhotos();
      this.familyMembers = this.familyVm.getFamilyMembers();
    }
  }

  private openFullscreenZoom(): void {
    this.zoomScale = 1;
    this.showFullscreenZoom = true;
  }

  private toImageSrc(path: string): string {
    if (!path) return '';
    if (path.startsWith('http') || path.startsWith('file://') || path.startsWith('data:')) {
      return path;
    }
    return 'file://' + path;
  }

  private async pickPhoto(): Promise<void> {
    try {
      const config: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const photoSelect = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await photoSelect.select(config);
      if (result.photoUris && result.photoUris.length > 0) {
        this.selectedPhotoUri = await this.copyPhotoToSandbox(result.photoUris[0]);
      }
    } catch (_) {
      this.selectedPhotoUri = '';
    }
  }

  private async copyPhotoToSandbox(sourceUri: string): Promise<string> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const sandboxDir = context.filesDir;
      const fileName = `photo_${Date.now()}.jpg`;
      const destPath = `${sandboxDir}/${fileName}`;
      const srcFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.copyFileSync(srcFile.fd, destPath);
      } finally {
        fileIo.closeSync(srcFile);
      }
      return destPath;
    } catch (_) {
      return sourceUri;
    }
  }

  onBackPress(): boolean {
    if (this.showFullscreenZoom) {
      this.showFullscreenZoom = false;
      return true;
    }
    if (this.showPhotoViewer) {
      this.closeViewer();
      return true;
    }
    return false;
  }

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: Curve.EaseInOut }).slide(SlideEffect.Right)
  }

  build() {
    Stack() {
      Column() {
      // —— 顶栏 ——
      Row() {
        Image($r('app.media.icon_back'))
          .width(24).height(24).fillColor(NEUTRAL_INK)
          .onClick(() => { router.back(); })

        Row() {
          Image(getModuleIconRes('album'))
            .width(20).height(20).fillColor(NEUTRAL_INK)
          Text('家庭相册')
            .fontSize(this.titleFontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
            .margin({ left: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)

        Text('+')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK)
          .onClick(() => {
            this.resetForm();
            this.showAddDialog = true;
          })
      }
      .width('100%')
      .padding({ left: SPACE_MD, right: SPACE_MD, top: 12, bottom: 8 })

      // —— 筛选条 ——
      Scroll() {
        Row({ space: 16 }) {
          ForEach(this.familyMembers, (member: FamilyMember) => {
            Text(member.avatar)
              .fontSize(16)
              .fontColor(this.selectedMemberFilter === member.id ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
              .fontWeight(this.selectedMemberFilter === member.id ? FontWeight.Bold : FontWeight.Normal)
              .border({ width: { bottom: this.selectedMemberFilter === member.id ? 2 : 0 }, color: NEUTRAL_INK })
              .padding({ left: 4, right: 4, bottom: 4 })
              .onClick(() => {
                this.selectedMemberFilter = this.selectedMemberFilter === member.id ? '' : member.id;
              })
          }, (member: FamilyMember) => member.id + '_' + member.updatedAt)

          Text('照片墙')
            .fontSize(FONT_CAPTION)
            .fontColor(this.currentViewMode === 0 ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
            .fontWeight(this.currentViewMode === 0 ? FontWeight.Bold : FontWeight.Normal)
            .border({ width: { bottom: this.currentViewMode === 0 ? 2 : 0 }, color: NEUTRAL_INK })
            .padding({ bottom: 4 })
            .onClick(() => { this.currentViewMode = 0; })
          Text('全部照片')
            .fontSize(FONT_CAPTION)
            .fontColor(this.currentViewMode === 3 ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
            .fontWeight(this.currentViewMode === 3 ? FontWeight.Bold : FontWeight.Normal)
            .border({ width: { bottom: this.currentViewMode === 3 ? 2 : 0 }, color: NEUTRAL_INK })
            .padding({ bottom: 4 })
            .onClick(() => {
              this.currentViewMode = 3;
              this.selectedMemberFilter = '';
            })
          Text('时间线')
            .fontSize(FONT_CAPTION)
            .fontColor(this.currentViewMode === 1 ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
            .fontWeight(this.currentViewMode === 1 ? FontWeight.Bold : FontWeight.Normal)
            .border({ width: { bottom: this.currentViewMode === 1 ? 2 : 0 }, color: NEUTRAL_INK })
            .padding({ bottom: 4 })
            .onClick(() => { this.currentViewMode = 1; })
          Text('按标签')
            .fontSize(FONT_CAPTION)
            .fontColor(this.currentViewMode === 2 ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
            .fontWeight(this.currentViewMode === 2 ? FontWeight.Bold : FontWeight.Normal)
            .border({ width: { bottom: this.currentViewMode === 2 ? 2 : 0 }, color: NEUTRAL_INK })
            .padding({ bottom: 4 })
            .onClick(() => { this.currentViewMode = 2; })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ left: SPACE_MD, right: SPACE_MD, bottom: 8 })
      .edgeEffect(EdgeEffect.Spring)

      // —— 展示密度切换 ——
      if (this.currentViewMode === 1 || this.currentViewMode === 2) {
        Row() {
          Blank()
          Row({ space: 16 }) {
            Text('列表')
              .fontSize(FONT_CAPTION)
              .fontColor(!this.compactGroups ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
              .fontWeight(!this.compactGroups ? FontWeight.Bold : FontWeight.Normal)
              .border({ width: { bottom: !this.compactGroups ? 2 : 0 }, color: NEUTRAL_INK })
              .padding({ bottom: 4 })
              .onClick(() => {
                this.compactGroups = false;
                this.db.saveSetting('album_compact_groups', false);
              })
            Text('宫格')
              .fontSize(FONT_CAPTION)
              .fontColor(this.compactGroups ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
              .fontWeight(this.compactGroups ? FontWeight.Bold : FontWeight.Normal)
              .border({ width: { bottom: this.compactGroups ? 2 : 0 }, color: NEUTRAL_INK })
              .padding({ bottom: 4 })
              .onClick(() => {
                this.compactGroups = true;
                this.db.saveSetting('album_compact_groups', true);
              })
          }
        }
        .width('100%')
        .padding({ left: SPACE_MD, right: SPACE_MD, bottom: 6 })
      }

      // —— 照片列表 ——
      Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        if (this.photos.length === 0) {
          EmptyState({
            icon: '📷',
            title: '暂无照片',
            subtitle: '记录家庭的美好瞬间',
            actionText: '+ 上传照片',
            buttonColor: NEUTRAL_INK,
            onAction: () => { this.showAddDialog = true; }
          })
        } else if (this.currentViewMode === 0) {
          if (this.getWallPhotos().length === 0) {
            this.WallEmptyGuide()
          } else {
            Row({ space: 10 }) {
              Column({ space: 10 }) {
                ForEach(this.getWallColumn(0), (photo: Photo) => {
                  this.PhotoWallTile(photo)
                }, (photo: Photo) => `${photo.id}_${photo.updatedAt || ''}`)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 10 }) {
                ForEach(this.getWallColumn(1), (photo: Photo) => {
                  this.PhotoWallTile(photo)
                }, (photo: Photo) => `${photo.id}_${photo.updatedAt || ''}`)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(SPACE_MD)
            .alignItems(VerticalAlign.Top)
          }
        } else if (this.currentViewMode === 3) {
          this.AllPhotosGrid()
        } else {
          Column({ space: 12 }) {
            ForEach(this.getGroupsForMode(), (group: PhotoGroup) => {
              Column({ space: 8 }) {
                Text(group.label)
                  .fontSize(FONT_BODY)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(NEUTRAL_INK)
                  .fontFamily(FONT_FAMILY_SERIF)
                  .width('100%')
                if (this.compactGroups) {
                  this.GroupThumbGrid(group.photos)
                } else {
                  ForEach(group.photos, (photo: Photo) => {
                  Row() {
                    Column() {
                      if (photo.url || photo.thumbnailUrl) {
                        Image(this.toImageSrc(photo.url || photo.thumbnailUrl))
                          .width(60).height(60)
                          .objectFit(ImageFit.Cover)
                      } else {
                        Text('🖼️').fontSize(24)
                      }
                    }
                    .width(60).height(60)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(BG_SUBTLE)
                    .margin({ right: 10 })

                    Column() {
                      Text(photo.description || '无描述')
                        .fontSize(this.fontSize)
                        .fontColor(NEUTRAL_INK)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        if (this.currentViewMode === 1 && photo.eventTag) {
                          Text(`🏷 ${photo.eventTag}`)
                            .fontSize(FONT_CAPTION)
                            .fontColor(NEUTRAL_INK_SECONDARY)
                            .margin({ right: 8 })
                        }
                        Text(formatIsoToLocal(photo.takenAt).slice(11))
                          .fontSize(FONT_CAPTION)
                          .fontColor(NEUTRAL_INK_SECONDARY)
                      }.margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (this.isFamilyOwner) {
                      Column() {
                        Image(photo.isOnWall === true ? $r('app.media.icon_star') : $r('app.media.icon_star_outline'))
                          .width(20).height(20)
                          .fillColor(photo.isOnWall === true ? BRAND_RED_LG : NEUTRAL_INK_SECONDARY)
                      }
                      .width(36).height(60)
                      .justifyContent(FlexAlign.Center)
                      .onClick(() => { this.toggleWall(photo); })
                    }
                  }
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                  .border({ width: { bottom: 0.5 }, color: DIVIDER })
                  .onClick(() => { this.openViewer(photo); })
                  }, (photo: Photo) => `${photo.id}_${photo.updatedAt}`)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (group: PhotoGroup) => this.groupKey(group))
          }
          .padding(SPACE_MD)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .layoutWeight(1)
    .onRefreshing(() => { this.handlePullRefresh().catch(() => {}); })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(BG_PAPER)
    .bindContentCover(this.showAddDialog, this.AddPhotoDialog())

    if (this.showPhotoViewer) {
      this.PhotoViewerOverlay()
    }
    if (this.showFullscreenZoom) {
      this.PhotoZoomOverlay()
    }
    if (this.showEditDialog) {
      this.EditPhotoDialog()
    }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 全屏照片查看器 ====================
  @Builder
  PhotoViewerOverlay() {
    if (this.showPhotoViewer && this.viewerPhoto) {
      Column() {
        Row() {
          Text(this.getMemberLabel(this.viewerPhoto!.creatorId))
            .fontSize(FONT_CAPTION).fontColor(Color.White).layoutWeight(1)
          Text('✕')
            .fontSize(18).fontColor(Color.White)
            .width(34).height(34)
            .textAlign(TextAlign.Center)
            .backgroundColor('#33FFFFFF')
            .onClick(() => { this.closeViewer(); })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 12, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        Image(this.toImageSrc(this.viewerPhoto!.url || this.viewerPhoto!.thumbnailUrl))
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .bindContextMenu(this.SavePhotoMenu, ResponseType.LongPress)
          .onClick(() => { this.openFullscreenZoom(); })

        Column() {
          if (this.viewerPhoto!.description) {
            Text(this.viewerPhoto!.description)
              .fontSize(FONT_BODY).fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          Row({ space: 12 }) {
            if (this.viewerPhoto!.eventTag) {
              Text(`🏷 ${this.viewerPhoto!.eventTag}`).fontSize(FONT_CAPTION).fontColor('#CCFFFFFF')
            }
            Text(formatIsoToLocal(this.viewerPhoto!.takenAt)).fontSize(FONT_CAPTION).fontColor('#CCFFFFFF')
            Blank()
            Text('点击图片全屏查看').fontSize(FONT_CAPTION_SM).fontColor('#99FFFFFF')
          }
          .width('100%')
          .margin({ top: 4 })

          Row({ space: 8 }) {
            if (this.isFamilyOwner) {
              Row({ space: 5 }) {
                Image(this.viewerPhoto!.isOnWall === true ? $r('app.media.icon_star') : $r('app.media.icon_star_outline'))
                  .width(18).height(18)
                  .fillColor(this.viewerPhoto!.isOnWall === true ? BRAND_RED_LG : Color.White)
                Text(this.viewerPhoto!.isOnWall === true ? '已上墙' : '上墙')
                  .fontSize(FONT_CAPTION).fontColor(Color.White)
              }
              .padding({ left: 12, right: 14, top: 8, bottom: 8 })
              .backgroundColor(this.viewerPhoto!.isOnWall === true ? 'rgba(200,74,50,0.2)' : 'rgba(255,255,255,0.15)')
              .onClick(() => { this.toggleWall(this.viewerPhoto!); })
            }
            Row({ space: 6 }) {
              Image(this.viewerLikedByMe ? $r('app.media.icon_heart') : $r('app.media.icon_heart_outline'))
                .width(20).height(20)
                .fillColor(this.viewerLikedByMe ? BRAND_RED_LG : Color.White)
              if (this.viewerLikes.length > 0) {
                Text(`${this.viewerLikes.length}`).fontSize(FONT_BODY).fontColor(Color.White)
              }
            }
            .padding({ left: 12, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.viewerLikedByMe ? 'rgba(200,74,50,0.2)' : 'rgba(255,255,255,0.15)')
            .onClick(() => { this.toggleLike(); })

            TextInput({ placeholder: '写评论...', text: this.commentInput })
              .fontSize(FONT_BODY).fontColor(Color.White)
              .backgroundColor('rgba(255,255,255,0.15)')
              .height(36).layoutWeight(1)
              .placeholderColor('#66FFFFFF')
              .onChange((v: string) => { this.commentInput = v; })
              .onClick(() => {})
            Button(this.isSendingComment ? '发送中' : '发送')
              .fontSize(FONT_BODY).fontColor(Color.White)
              .backgroundColor(BRAND_RED)
              .height(36)
              .enabled(!this.isSendingComment)
              .onClick(() => { this.sendComment(); })
          }
          .width('100%')
          .margin({ top: 8 })

          if (this.viewerComments.length > 0) {
            Scroll() {
              Column({ space: 6 }) {
                ForEach(this.viewerComments, (c: PhotoComment) => {
                  Row() {
                    Text(this.getMemberLabel(c.creatorId)).fontSize(FONT_CAPTION).fontColor('#CCFFFFFF')
                    Text(c.content).fontSize(FONT_BODY).fontColor(Color.White)
                      .layoutWeight(1)
                      .margin({ left: 8, right: 8 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.relativeTime(c.createdAt)).fontSize(FONT_CAPTION_SM).fontColor('#66FFFFFF')
                    if (this.db.isRecordCreator(c.creatorId)) {
                      Text('删除').fontSize(FONT_CAPTION).fontColor(SEMANTIC_ERROR)
                        .margin({ left: 6 })
                        .onClick(() => { this.deleteComment(c.id); })
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }, (c: PhotoComment) => `${c.id}_${c.updatedAt}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .constraintSize({ maxHeight: 84 })
            .margin({ top: 8 })
            .scrollBar(BarState.Off)
          }

          if (this.isCreator(this.viewerPhoto!.creatorId)) {
            Row({ space: 16 }) {
              Button('编辑')
                .fontSize(FONT_BODY).fontColor(Color.White)
                .backgroundColor('rgba(255,255,255,0.15)')
                .height(44).layoutWeight(1)
                .onClick(() => { this.openEditDialog(this.viewerPhoto); })
              Button('删除')
                .fontSize(FONT_BODY).fontColor(SEMANTIC_ERROR)
                .backgroundColor('rgba(184,64,42,0.15)')
                .height(44).layoutWeight(1)
                .onClick(() => { this.showDeleteConfirm(this.viewerPhoto); })
            }
            .width('100%')
            .margin({ top: 12 })
          } else {
            Text('只有上传者可编辑或删除这张照片')
              .fontSize(FONT_CAPTION_SM).fontColor('#66FFFFFF').margin({ top: 8 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0], ['#CC000000', 1]]
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onClick(() => { this.closeViewer(); })
    }
  }

  // ==================== 全屏图片缩放查看器 ====================
  @Builder
  PhotoZoomOverlay() {
    Stack() {
      if (this.showFullscreenZoom && this.viewerPhoto) {
        Image(this.toImageSrc(this.viewerPhoto!.url || this.viewerPhoto!.thumbnailUrl))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .gesture(
            PinchGesture({ fingers: 2 })
              .onActionStart(() => {})
              .onActionUpdate((event: GestureEvent) => {
                let s = event.scale;
                if (s < 1) s = 1;
                if (s > 4) s = 4;
                this.zoomScale = s;
              })
              .onActionEnd(() => {
                if (this.zoomScale < 1.3) {
                  this.zoomScale = 1;
                }
              })
          )
          .onClick(() => { this.showFullscreenZoom = false; })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  // ==================== 长按图片 → 保存菜单 ====================
  @Builder
  SavePhotoMenu() {
    Menu() {
      MenuItem({ content: '保存到相册' })
        .onClick(() => { this.downloadPhoto(this.viewerPhoto!); })
    }
  }

  // ==================== 照片墙 ====================
  @Builder
  PhotoWallTile(photo: Photo) {
    Stack() {
      Column() {
        if (photo.url || photo.thumbnailUrl) {
          Image(this.toImageSrc(photo.url || photo.thumbnailUrl))
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Text('🖼️').fontSize(32).fontColor(NEUTRAL_INK_SECONDARY)
        }
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(BG_SUBTLE)

      Row() {
        if (photo.description || photo.takenAt) {
          Text(photo.description || toLocalDateKey(photo.takenAt).slice(5))
            .fontSize(FONT_CAPTION).fontColor(Color.White)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .backgroundColor('#59000000')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .margin({ left: 6, bottom: 6 })
            .constraintSize({ maxWidth: '92%' })
        }
      }
      .width('100%').height('100%')
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.Start)

      if (this.isFamilyOwner) {
        Row() {
          Column() {
            Image(photo.isOnWall === true ? $r('app.media.icon_star') : $r('app.media.icon_star_outline'))
              .width(15).height(15)
              .fillColor(photo.isOnWall === true ? BRAND_RED_LG : Color.White)
          }
          .width(28).height(28)
          .backgroundColor('#66000000')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 6, right: 6 })
          .onClick(() => { this.toggleWall(photo); })
        }
        .width('100%').height('100%')
        .alignItems(VerticalAlign.Top)
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .aspectRatio(this.wallRatio(photo))
    .clip(true)
    .backgroundColor(BG_SUBTLE)
    .onClick(() => { this.openViewer(photo); })
    .gesture(LongPressGesture().onAction((event: GestureEvent) => {
      this.downloadPhoto(photo);
    }))
  }

  @Builder
  WallStarCorner(photo: Photo) {
    Row() {
      Column() {
        Image(photo.isOnWall === true ? $r('app.media.icon_star') : $r('app.media.icon_star_outline'))
          .width(15).height(15)
          .fillColor(photo.isOnWall === true ? BRAND_RED_LG : Color.White)
      }
      .width(26).height(26)
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.toggleWall(photo); })
    }
    .width('100%').height('100%')
    .alignItems(VerticalAlign.Top)
    .justifyContent(FlexAlign.End)
    .padding({ top: 6, right: 6 })
  }

  // ==================== 全部照片网格 ====================
  @Builder
  AllPhotosGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.getFilteredPhotos(), (photo: Photo) => {
        Column() {
          Stack() {
            Column() {
              if (photo.url || photo.thumbnailUrl) {
                Image(this.toImageSrc(photo.url || photo.thumbnailUrl))
                  .width('100%').height('100%')
                  .objectFit(ImageFit.Cover)
              } else {
                Text('🖼️').fontSize(32)
              }
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor(BG_SUBTLE)

            if (this.isFamilyOwner) {
              this.WallStarCorner(photo)
            }
          }
          .width('100%').height(120)
          .clip(true)

          if (photo.description) {
            Text(photo.description)
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }
          Row() {
            if (photo.eventTag) {
              Text(`🏷 ${photo.eventTag}`).fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
            }
            Text(toLocalDateKey(photo.takenAt).slice(5)).fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
          }.width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 2 })
        }
        .width('48%')
        .margin('1%')
        .alignItems(HorizontalAlign.Start)
        .onClick(() => { this.openViewer(photo); })
        .gesture(LongPressGesture().onAction((event: GestureEvent) => {
          this.downloadPhoto(photo);
        }))
      }, (photo: Photo) => `${photo.id}_${photo.updatedAt || ''}`)
    }
    .padding(SPACE_MD)
  }

  @Builder
  WallEmptyGuide() {
    Column() {
      Text('⭐').fontSize(44)
      Text('照片墙还空着')
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(NEUTRAL_INK)
        .fontFamily(FONT_FAMILY_SERIF)
        .margin({ top: 14 })
      Text(this.isFamilyOwner
        ? '点照片上的 ☆ 星标（全部照片 / 时间线 / 按标签里都行），把最爱的瞬间放上墙'
        : '等家庭主人挑选照片，把美好瞬间放上墙吧')
        .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY)
        .textAlign(TextAlign.Center)
        .width('72%')
        .margin({ top: 8 })
      if (this.isFamilyOwner) {
        Text('去挑照片')
          .fontSize(FONT_BODY)
          .fontColor(Color.White)
          .padding({ left: 26, right: 26, top: 12, bottom: 12 })
          .backgroundColor(NEUTRAL_INK)
          .margin({ top: 18 })
          .onClick(() => { this.currentViewMode = 1; })
      }
    }
    .width('100%')
    .padding({ top: 110, left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
  }

  private getWallPhotos(): Photo[] {
    const list = this.getFilteredPhotos().filter((p: Photo) => p.isOnWall === true);
    return list.sort((a: Photo, b: Photo) => {
      const ta = a.updatedAt || '';
      const tb = b.updatedAt || '';
      return tb.localeCompare(ta);
    });
  }

  private getWallColumn(colIndex: number): Photo[] {
    const wall = this.getWallPhotos();
    const col: Photo[] = [];
    for (let i = colIndex; i < wall.length; i += 2) {
      col.push(wall[i]);
    }
    return col;
  }

  private wallRatio(photo: Photo): number {
    const w = photo.width || 0;
    const h = photo.height || 0;
    if (w > 0 && h > 0) {
      const r = w / h;
      if (r < 0.55) return 0.55;
      if (r > 1.8) return 1.8;
      return r;
    }
    const variants: number[] = [0.8, 1.0, 1.25, 1.0];
    let hash = 0;
    const id = photo.id || '';
    for (let i = 0; i < id.length; i++) {
      hash = (hash * 31 + id.charCodeAt(i)) >>> 0;
    }
    return variants[hash % variants.length];
  }

  private async toggleWall(photo: Photo): Promise<void> {
    if (!this.isFamilyOwner) {
      promptAction.showToast({ message: '仅家庭主人可布置照片墙' });
      return;
    }
    if (this.wallBusy === photo.id) return;
    this.wallBusy = photo.id;
    try {
      const now = new Date().toISOString();
      const updated: Photo = {
        id: photo.id,
        familyId: photo.familyId,
        creatorId: photo.creatorId,
        visibility: photo.visibility,
        visibleMembers: photo.visibleMembers,
        version: (photo.version || 0) + 1,
        createdAt: photo.createdAt,
        updatedAt: now,
        url: photo.url,
        thumbnailUrl: photo.thumbnailUrl,
        description: photo.description,
        eventTag: photo.eventTag,
        takenAt: photo.takenAt,
        isOnWall: photo.isOnWall !== true,
        width: photo.width || 0,
        height: photo.height || 0
      };
      await this.db.updatePhoto(updated);
      this.photos = this.db.getPhotos();
      if (this.viewerPhoto && this.viewerPhoto.id === photo.id) {
        this.viewerPhoto = this.photos.find((p: Photo) => p.id === photo.id) ?? updated;
      }
    } finally {
      this.wallBusy = '';
    }
  }

  private async readImageSize(localPath: string): Promise<ImageSize> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(localPath, fileIo.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      source.release();
      fileIo.closeSync(file);
      return { width: info.size.width, height: info.size.height };
    } catch (_) {
      if (file) {
        try { fileIo.closeSync(file); } catch (_) {}
      }
      return { width: 0, height: 0 };
    }
  }

  private openViewer(photo: Photo): void {
    this.viewerPhoto = photo;
    this.showPhotoViewer = true;
    this.refreshViewerInteractions(photo.id);
  }

  private closeViewer(): void {
    this.showPhotoViewer = false;
    this.viewerPhoto = null;
  }

  // ==================== 照片互动（点赞/评论） ====================
  private refreshViewerInteractions(photoId: string): void {
    const all = this.db.getPhotoComments(photoId);
    const active = all.filter(c => c.isDeleted !== true);
    this.viewerLikes = active.filter(c => c.isLike);
    this.viewerComments = active.filter(c => !c.isLike)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    this.viewerLikedByMe = this.viewerLikes.some(c => this.db.isRecordCreator(c.creatorId));
  }

  private async toggleLike(): Promise<void> {
    if (this.isTogglingLike) return;
    const photo = this.viewerPhoto;
    if (!photo) return;
    this.isTogglingLike = true;
    const wasLiked = this.viewerLikedByMe;
    const prevLikes = this.viewerLikes;
    try {
      const myLike = this.viewerLikes.find(c => this.db.isRecordCreator(c.creatorId));
      if (myLike) {
        this.viewerLikedByMe = false;
        this.viewerLikes = this.viewerLikes.filter(c => c.id !== myLike.id);
        await this.db.deletePhotoComment(myLike.id);
      } else {
        const now = new Date().toISOString();
        const comment: PhotoComment = {
          id: generateId('pc'),
          familyId: photo.familyId,
          photoId: photo.id,
          creatorId: this.db.getCurrentMemberId(),
          visibility: photo.visibility,
          visibleMembers: photo.visibleMembers,
          version: 1,
          createdAt: now,
          updatedAt: now,
          isLike: true,
          content: ''
        };
        this.viewerLikedByMe = true;
        this.viewerLikes = [...this.viewerLikes, comment];
        await this.db.savePhotoComment(comment);
      }
    } catch (err) {
      this.viewerLikedByMe = wasLiked;
      this.viewerLikes = prevLikes;
    } finally {
      this.isTogglingLike = false;
    }
  }

  private async sendComment(): Promise<void> {
    if (this.isSendingComment) return;
    const photo = this.viewerPhoto;
    const text = this.commentInput.trim();
    if (!photo || !text) return;
    this.isSendingComment = true;
    try {
      const now = new Date().toISOString();
      const comment: PhotoComment = {
        id: generateId('pc'),
        familyId: photo.familyId,
        photoId: photo.id,
        creatorId: this.db.getCurrentMemberId(),
        visibility: photo.visibility,
        visibleMembers: photo.visibleMembers,
        version: 1,
        createdAt: now,
        updatedAt: now,
        isLike: false,
        content: text
      };
      this.viewerComments = [...this.viewerComments, comment];
      this.commentInput = '';
      await this.db.savePhotoComment(comment);
    } finally {
      this.isSendingComment = false;
    }
  }

  private async deleteComment(id: string): Promise<void> {
    this.viewerComments = this.viewerComments.filter(c => c.id !== id);
    await this.db.deletePhotoComment(id);
  }

  private relativeTime(iso: string): string {
    if (!iso) return '';
    const t = new Date(iso).getTime();
    if (isNaN(t)) return '';
    const diff = Date.now() - t;
    const min = Math.floor(diff / 60000);
    if (min < 1) return '刚刚';
    if (min < 60) return `${min}分钟前`;
    const hour = Math.floor(min / 60);
    if (hour < 24) return `${hour}小时前`;
    const day = Math.floor(hour / 24);
    if (day < 30) return `${day}天前`;
    return formatIsoToLocal(iso).slice(5, 16);
  }

  // ==================== 保存到系统相册 ====================
  private toFileUri(path: string): string {
    if (path.startsWith('file://')) return path;
    return fileUri.getUriFromPath(path);
  }

  private async downloadPhoto(photo: Photo): Promise<void> {
    try {
      let localPath = photo.url || '';
      let isTemp = false;
      if (!localPath || localPath.startsWith('http')) {
        const context = getContext(this) as common.UIAbilityContext;
        const destPath = `${context.filesDir}/download_${Date.now()}.jpg`;
        const ok = await CloudService.getInstance()
          .downloadFile(CloudService.photoCloudPath(photo.familyId, photo.id), destPath);
        if (!ok) {
          promptAction.showToast({ message: '照片下载失败' });
          return;
        }
        localPath = destPath;
        isTemp = true;
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(getContext(this));
      await helper.showAssetsCreationDialog(
        [this.toFileUri(localPath)],
        [{ fileNameExtension: 'jpg', photoType: photoAccessHelper.PhotoType.IMAGE }]
      );
      if (isTemp) {
        try { fileIo.unlinkSync(localPath); } catch (_) {}
      }
      promptAction.showToast({ message: '已保存到系统相册' });
    } catch (err) {
      promptAction.showToast({ message: '保存失败，请重试' });
    }
  }

  private getMemberLabel(creatorId: string): string {
    if (!creatorId) return '家庭成员';
    const member = this.familyMembers.find(m => m.id === creatorId);
    if (member) return `${member.avatar} ${member.name}`;
    const byUser = this.familyMembers.find(m => m.userId === creatorId);
    if (byUser) return `${byUser.avatar} ${byUser.name}`;
    return '家庭成员';
  }

  private openEditDialog(photo: Photo | null): void {
    if (!photo) return;
    this.editDesc = photo.description;
    this.editTag = photo.eventTag;
    this.showEditDialog = true;
  }

  private showDeleteConfirm(photo: Photo | null): void {
    if (!photo) return;
    AlertDialog.show({
      title: '确认删除',
      message: '确定要删除这张照片吗？',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除', fontColor: SEMANTIC_ERROR,
        action: async () => {
          await this.deletePhotoWithFile(photo);
          this.closeViewer();
        }
      }
    });
  }

  private async savePhotoEdit(): Promise<void> {
    if (this.isSavingEdit) return;
    const photo = this.viewerPhoto;
    if (!photo) return;
    this.isSavingEdit = true;
    try {
      const updated: Photo = {
        id: photo.id,
        familyId: photo.familyId,
        creatorId: photo.creatorId,
        visibility: photo.visibility,
        visibleMembers: photo.visibleMembers,
        version: photo.version + 1,
        createdAt: photo.createdAt,
        updatedAt: new Date().toISOString(),
        url: photo.url,
        thumbnailUrl: photo.thumbnailUrl,
        description: this.editDesc,
        eventTag: this.editTag,
        takenAt: photo.takenAt,
        isOnWall: photo.isOnWall === true,
        width: photo.width || 0,
        height: photo.height || 0
      };
      await this.db.updatePhoto(updated);
      this.photos = this.db.getPhotos();
      this.viewerPhoto = this.photos.find(p => p.id === photo.id) ?? null;
      this.showEditDialog = false;
    } finally {
      this.isSavingEdit = false;
    }
  }

  @Builder
  AddPhotoDialog() {
    if (this.showAddDialog) {
      Column() {
      Column() {
        Text('上传照片')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(NEUTRAL_INK)
          .fontFamily(FONT_FAMILY_SERIF)
          .margin({ bottom: 16 })

        Column() {
          if (this.selectedPhotoUri) {
            Image(this.toImageSrc(this.selectedPhotoUri))
              .width('100%').height(150)
              .objectFit(ImageFit.Cover)
          } else {
            Text('📷').fontSize(40)
            Text('点击选择照片')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 8 })
            Text('从相册中选择或拍摄照片')
              .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_TERTIARY).margin({ top: 4 })
          }
        }
        .width('100%')
        .height(150)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(BG_SUBTLE)
        .border({ width: 1, color: DIVIDER, style: BorderStyle.Dashed })
        .margin({ bottom: 12 })
        .onClick(() => { this.pickPhoto(); })

        TextInput({ placeholder: '照片描述（可选）', text: this.newDescription })
          .width('100%').padding(14).borderRadius(0).backgroundColor(BG_SUBTLE).margin({ bottom: 8 })
          .onChange((v: string) => { this.newDescription = v; })

        Text('事件标签')
          .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tagOptions, (item: TagOption) => {
            Text(item.label)
              .fontSize(FONT_CAPTION)
              .fontColor(this.newEventTag === item.tag ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
              .fontWeight(this.newEventTag === item.tag ? FontWeight.Bold : FontWeight.Normal)
              .border({ width: { bottom: this.newEventTag === item.tag ? 2 : 0 }, color: NEUTRAL_INK })
              .padding({ bottom: 4 })
              .margin(3)
              .onClick(() => { this.newEventTag = item.tag; })
          }, (item: TagOption) => item.tag || 'none')
        }
        .width('100%')
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: DIVIDER })
            .borderRadius(0).layoutWeight(1)
            .onClick(() => {
              this.showAddDialog = false;
              this.resetForm();
            })
          Button(this.isSavingPhoto ? '保存中...' : '保存')
            .fontSize(FONT_BODY).fontColor(Color.White)
            .backgroundColor(NEUTRAL_INK)
            .borderRadius(0).layoutWeight(1)
            .enabled(!this.isSavingPhoto)
            .onClick(async () => {
              if (this.isSavingPhoto) return;
              this.isSavingPhoto = true;
              try {
                const now = new Date().toISOString();
                const family = this.db.getCurrentFamily();
                const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.ALBUM);
                const size = await this.readImageSize(this.selectedPhotoUri);
                const photo: Photo = {
                  id: generateId('ph'),
                  familyId: family?.id ?? '',
                  creatorId: this.db.getCurrentMemberId(),
                  visibility: vis.visibility,
                  visibleMembers: vis.visibleMembers,
                  version: 1,
                  createdAt: now,
                  updatedAt: now,
                  url: this.selectedPhotoUri,
                  thumbnailUrl: this.selectedPhotoUri,
                  description: this.newDescription,
                  eventTag: this.newEventTag,
                  takenAt: now,
                  isOnWall: false,
                  width: size.width,
                  height: size.height
                };
                if (photo.url && !photo.url.startsWith('http')) {
                  const downloadUrl = await CloudService.getInstance()
                    .uploadPhoto(photo.url, photo.familyId, photo.id);
                  if (downloadUrl) {
                    photo.url = downloadUrl;
                  }
                }
                await this.db.savePhoto(photo);
                this.showAddDialog = false;
                this.resetForm();
                this.photos = this.db.getPhotos();
              } finally {
                this.isSavingPhoto = false;
              }
            })
        }
      }
      .width('90%')
      .padding(20)
      .backgroundColor(BG_CARD)
      .onClick(() => {})
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  EditPhotoDialog() {
    if (this.showEditDialog) {
      Column() {
        Column() {
          Text('编辑照片')
            .fontSize(FONT_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor(NEUTRAL_INK)
            .fontFamily(FONT_FAMILY_SERIF)
            .margin({ bottom: 4 })
          Text('修改名称备注和标签，照片本身不变')
            .fontSize(FONT_CAPTION_SM).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 14 })

          Text('名称 / 备注')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 6 })
          TextInput({ placeholder: '给照片起个名字或备注（可选）', text: this.editDesc })
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .borderRadius(0)
            .backgroundColor(BG_SUBTLE)
            .margin({ bottom: 14 })
            .onChange((v: string) => { this.editDesc = v; })

          Text('标签')
            .fontSize(FONT_CAPTION).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 6 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tagOptions, (item: TagOption) => {
              Text(item.label)
                .fontSize(FONT_CAPTION)
                .fontColor(this.editTag === item.tag ? NEUTRAL_INK : NEUTRAL_INK_TERTIARY)
                .fontWeight(this.editTag === item.tag ? FontWeight.Bold : FontWeight.Normal)
                .border({ width: { bottom: this.editTag === item.tag ? 2 : 0 }, color: NEUTRAL_INK })
                .padding({ bottom: 4 })
                .margin(3)
                .onClick(() => { this.editTag = item.tag; })
            }, (item: TagOption) => item.tag || 'none')
          }
          .width('100%')
          .margin({ bottom: 16 })

          Row({ space: 12 }) {
            Button('取消')
              .fontSize(FONT_BODY).fontColor(NEUTRAL_INK_SECONDARY)
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: DIVIDER })
              .borderRadius(0).layoutWeight(1)
              .onClick(() => { this.showEditDialog = false; })
            Button(this.isSavingEdit ? '保存中...' : '保存')
              .fontSize(FONT_BODY).fontColor(Color.White)
              .backgroundColor(NEUTRAL_INK)
              .borderRadius(0).layoutWeight(1)
              .enabled(!this.isSavingEdit)
              .onClick(() => { this.savePhotoEdit(); })
          }
        }
        .width('85%')
        .padding(20)
        .backgroundColor(BG_CARD)
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.5)')
      .justifyContent(FlexAlign.Center)
    }
  }

  private getFilteredPhotos(): Photo[] {
    if (!this.selectedMemberFilter) return this.photos;
    const member = this.familyMembers.find(m => m.id === this.selectedMemberFilter);
    const targetUserId = member ? member.userId : '';
    return this.photos.filter(p =>
      p.creatorId === this.selectedMemberFilter ||
      (targetUserId && p.creatorId === targetUserId)
    );
  }

  private getGroupedPhotos(): PhotoGroup[] {
    const filtered = this.getFilteredPhotos();
    const groups: PhotoGroup[] = [];
    const dateMap: Record<string, Photo[]> = {};

    for (const photo of filtered) {
      const dateKey = toLocalDateKey(photo.takenAt);
      if (!dateMap[dateKey]) {
        dateMap[dateKey] = [];
      }
      dateMap[dateKey].push(photo);
    }

    const sortedDates = Object.keys(dateMap).sort((a, b) => b.localeCompare(a));
    for (const date of sortedDates) {
      const d = toDateAtLocalMidnight(date);
      const weekDays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
      groups.push({
        label: `${date.slice(5)} ${weekDays[d.getDay()]}`,
        photos: dateMap[date]
      });
    }

    return groups;
  }

  private getTagGroups(): PhotoGroup[] {
    const filtered = this.getFilteredPhotos();
    const groups: PhotoGroup[] = [];
    const groupedIds = new Set<string>();
    for (const opt of this.tagOptions) {
      if (!opt.tag) continue;
      const list = filtered.filter(p => p.eventTag === opt.tag || p.eventTag === opt.label);
      if (list.length > 0) {
        groups.push({
          label: `🏷 ${opt.tag}`,
          photos: list.sort((a, b) => b.takenAt.localeCompare(a.takenAt))
        });
        for (const p of list) groupedIds.add(p.id);
      }
    }
    const uncategorized = filtered.filter(p => !groupedIds.has(p.id));
    if (uncategorized.length > 0) {
      groups.push({
        label: '未分类',
        photos: uncategorized.sort((a, b) => b.takenAt.localeCompare(a.takenAt))
      });
    }
    return groups;
  }

  private getGroupsForMode(): PhotoGroup[] {
    return this.currentViewMode === 2 ? this.getTagGroups() : this.getGroupedPhotos();
  }

  // ==================== 小图宫格 ====================
  @Builder
  GroupThumbGrid(photos: Photo[]) {
    Column({ space: 6 }) {
      ForEach(this.chunkPhotos(photos), (row: Photo[]) => {
        Row({ space: 6 }) {
          ForEach(row, (photo: Photo) => {
            Stack() {
              Column() {
                if (photo.url || photo.thumbnailUrl) {
                  Image(this.toImageSrc(photo.url || photo.thumbnailUrl))
                    .width('100%').height('100%')
                    .objectFit(ImageFit.Cover)
                } else {
                  Text('🖼️').fontSize(16).fontColor(NEUTRAL_INK_SECONDARY)
                }
              }
              .width('100%').height('100%')
              .justifyContent(FlexAlign.Center)
              .backgroundColor(BG_SUBTLE)

              if (this.isFamilyOwner) {
                this.WallStarCorner(photo)
              }
            }
            .layoutWeight(1)
            .aspectRatio(1)
            .clip(true)
            .onClick(() => { this.openViewer(photo); })
          }, (photo: Photo) => `${photo.id}_${photo.updatedAt || ''}`)
          if (row.length < 4) {
            ForEach(this.fillerCells(4 - row.length), (i: number) => {
              Column().layoutWeight(1).aspectRatio(1)
            }, (i: number) => 'f' + i)
          }
        }
        .width('100%')
      }, (row: Photo[]) => row[0].id + '_' + row.length)
    }
    .width('100%')
  }

  private groupKey(group: PhotoGroup): string {
    let wallCount = 0;
    for (const p of group.photos) {
      if (p.isOnWall === true) {
        wallCount++;
      }
    }
    return `${group.label}_${group.photos.length}_${wallCount}`;
  }

  private chunkPhotos(photos: Photo[]): Photo[][] {
    const rows: Photo[][] = [];
    for (let i = 0; i < photos.length; i += 4) {
      rows.push(photos.slice(i, i + 4));
    }
    return rows;
  }

  private fillerCells(count: number): number[] {
    const cells: number[] = [];
    for (let i = 0; i < count; i++) {
      cells.push(i);
    }
    return cells;
  }

  private async deletePhotoWithFile(photo: Photo): Promise<void> {
    const localPaths: string[] = [];
    if (photo.url && !photo.url.startsWith('http')) { localPaths.push(photo.url); }
    if (photo.thumbnailUrl && !photo.thumbnailUrl.startsWith('http')) { localPaths.push(photo.thumbnailUrl); }
    for (const path of localPaths) {
      try { fileIo.unlinkSync(path); } catch (_) {}
    }
    if (photo.url && photo.url.startsWith('http')) {
      await CloudService.getInstance().deleteFile(CloudService.photoCloudPath(photo.familyId, photo.id));
    }
    const comments = this.db.getPhotoComments(photo.id);
    for (const c of comments) {
      await this.db.deletePhotoComment(c.id);
    }
    await this.db.deletePhoto(photo.id);
    this.photos = this.db.getPhotos();
  }

  private resetForm(): void {
    this.newDescription = '';
    this.newEventTag = '';
    this.selectedPhotoUri = '';
  }
}

interface PhotoGroup {
  label: string;
  photos: Photo[];
}
