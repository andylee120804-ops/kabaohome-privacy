/**
 * 卡宝Home - 家庭相册页面
 * 照片选择 + 事件归档 + 成员筛选 + 时间线展示
 */
import { Photo } from '../model/Photo';
import { PhotoComment } from '../model/PhotoComment';
import { BG_PAPER, BG_SUBTLE, BORDER_CORAL, BORDER_SUBTLE, NEUTRAL_INK, NEUTRAL_INK_SECONDARY, SEMANTIC_ERROR, SEMANTIC_INFO } from '../common/DesignTokens';
import { LocalDbService } from '../service/LocalDbService';
import { CloudService } from '../service/CloudService';
import { EmptyState } from '../components/EmptyState';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { FontSizeMode, THEME_PALETTES , PAGE_TRANSITION_DURATION, ModuleId } from '../common/Constants';
import { generateId, toDateAtLocalMidnight, formatIsoToLocal, toLocalDateKey } from '../common/Utils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import { curves, promptAction } from '@kit.ArkUI';

interface TagOption {
  tag: string;
  label: string;
}

@Entry
@Component
struct AlbumPage {
  @State photos: Photo[] = [];
  @State familyMembers: FamilyMember[] = [];
  @State selectedMemberFilter: string = '';
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
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themePrimary: string = SEMANTIC_INFO;
  @State themeBorder: string = BORDER_CORAL;
  @State themeLightBg: string = BG_PAPER;
  @State currentViewMode: number = 0; // 0=网格 1=按日期 2=按标签
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
    const member = this.familyVm.getCurrentMember();
    this.isLargeFont = member?.fontSizeMode === FontSizeMode.LARGE;
    const palette = THEME_PALETTES.find(p => p.id === this.db.getThemeColor()) ?? THEME_PALETTES[0];
    this.themePrimary = palette.primary;
    this.themeBorder = palette.border;
    this.themeLightBg = palette.lightBg;
    if (this.isLargeFont) {
      this.fontSize = 20;
      this.titleFontSize = 24;
    }
    // 补传未上云的照片（离线保存的 + 历史本地路径记录自愈），有补传则刷新列表
    CloudService.getInstance().syncPendingPhotoUploads().then((count: number) => {
      if (count > 0) {
        this.photos = this.db.getPhotos();
      }
    });
    // 主动拉取云端照片和互动并合并，其他成员新传的照片/点赞评论无需等全局同步（5分钟节流）即可显示
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

  /**
   * 把照片路径转成 Image 可加载的 src
   * ArkUI Image 加载本地沙箱文件只支持 file:// 协议（file:///data/storage/...），
   * 裸绝对路径（DB 里存的格式）加载失败。https/data:/file:// 原样返回。
   */
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
      // copyFileSync 不接受媒体库 URI（file://media/...），必须先 openSync 拿 fd 再复制
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

  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
    PageTransitionExit({ type: RouteType.Push, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionEnter({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Left)
    PageTransitionExit({ type: RouteType.Pop, duration: PAGE_TRANSITION_DURATION, curve: curves.springMotion() }).slide(SlideEffect.Right)
  }

  build() {
    Stack() {
      Column() {
      Row() {
        Row() {
          Text('<')
            .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.themePrimary)
        }.width(34).height(34).borderRadius(17)
        .backgroundColor(this.themeBorder)
        .justifyContent(FlexAlign.Center)
        .onClick(() => { router.back(); })
        Text('📷 家庭相册').fontSize(this.titleFontSize).fontWeight(FontWeight.Bold).layoutWeight(1).textAlign(TextAlign.Center)
        Row() { Text('+').fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold) }
          .width(32).height(32).borderRadius(16)
          .backgroundColor(this.themePrimary)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.resetForm();
            this.showAddDialog = true;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 筛选条
      Scroll() {
        Row({ space: 8 }) {
          Text('全部')
            .fontSize(12)
            .fontColor(this.selectedMemberFilter === '' ? Color.White : NEUTRAL_INK_SECONDARY)
            .backgroundColor(this.selectedMemberFilter === '' ? this.themePrimary : BG_SUBTLE)
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { this.selectedMemberFilter = ''; })
          ForEach(this.familyMembers, (member: FamilyMember) => {
            Text(member.avatar)
              .fontSize(14)
              .fontColor(this.selectedMemberFilter === member.id ? Color.White : NEUTRAL_INK_SECONDARY)
              .backgroundColor(this.selectedMemberFilter === member.id ? member.color : BG_SUBTLE)
              .borderRadius(12)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => { this.selectedMemberFilter = member.id; })
          }, (member: FamilyMember) => member.id + '_' + member.updatedAt)

          // 视图切换：网格 / 按日期 / 按标签
          Text('网格')
            .fontSize(12)
            .fontColor(this.currentViewMode === 0 ? Color.White : NEUTRAL_INK_SECONDARY)
            .backgroundColor(this.currentViewMode === 0 ? this.themePrimary : BG_SUBTLE)
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { this.currentViewMode = 0; })
          Text('按日期')
            .fontSize(12)
            .fontColor(this.currentViewMode === 1 ? Color.White : NEUTRAL_INK_SECONDARY)
            .backgroundColor(this.currentViewMode === 1 ? this.themePrimary : BG_SUBTLE)
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { this.currentViewMode = 1; })
          Text('按标签')
            .fontSize(12)
            .fontColor(this.currentViewMode === 2 ? Color.White : NEUTRAL_INK_SECONDARY)
            .backgroundColor(this.currentViewMode === 2 ? this.themePrimary : BG_SUBTLE)
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { this.currentViewMode = 2; })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      .edgeEffect(EdgeEffect.Spring)

      // 照片列表
      Scroll() {
        if (this.photos.length === 0) {
          EmptyState({
            icon: '📷',
            title: '暂无照片',
            subtitle: '记录家庭的美好瞬间',
            actionText: '+ 上传照片',
            buttonColor: this.themePrimary,
            onAction: () => { this.showAddDialog = true; }
          })
        } else if (this.currentViewMode === 0) {
          // 网格视图
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.getFilteredPhotos(), (photo: Photo) => {
              Column() {
                Column() {
                  if (photo.url || photo.thumbnailUrl) {
                    Image(this.toImageSrc(photo.url || photo.thumbnailUrl))
                      .width('100%').height(120)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(8)
                  } else {
                    Text('🖼️').fontSize(32)
                  }
                }
                .width('100%')
                .height(120)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(BG_SUBTLE)
                .borderRadius(8)

                if (photo.description) {
                  Text(photo.description)
                    .fontSize(15).fontColor(NEUTRAL_INK_SECONDARY)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                Row() {
                  if (photo.eventTag) {
                    Text(`🏷 ${photo.eventTag}`).fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
                  }
                  Text(toLocalDateKey(photo.takenAt).slice(5)).fontSize(12).fontColor(NEUTRAL_INK_SECONDARY)
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
            }, (photo: Photo) => `${photo.id}_${photo.updatedAt}`)
          }
          .padding(16)
        } else {
          // 分组视图：按日期 / 按标签
          Column({ space: 12 }) {
            ForEach(this.getGroupsForMode(), (group: PhotoGroup) => {
              Column({ space: 8 }) {
                Text(group.label).fontSize(16).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).width('100%')
                ForEach(group.photos, (photo: Photo) => {
                  Row() {
                    Column() {
                      if (photo.url || photo.thumbnailUrl) {
                        Image(this.toImageSrc(photo.url || photo.thumbnailUrl))
                          .width(60).height(60)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(8)
                      } else {
                        Text('🖼️').fontSize(24)
                      }
                    }
                    .width(60).height(60)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(BG_SUBTLE)
                    .borderRadius(8)
                    .margin({ right: 10 })

                    Column() {
                      Text(photo.description || '无描述').fontSize(17).fontColor(NEUTRAL_INK)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        // 按标签分组时头部已显示标签，行内不再重复
                        if (this.currentViewMode === 1 && photo.eventTag) {
                          Text(`🏷 ${photo.eventTag}`).fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).margin({ right: 8 })
                        }
                        Text(formatIsoToLocal(photo.takenAt).slice(11)).fontSize(13).fontColor(NEUTRAL_INK_SECONDARY)
                      }.margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(8)
                  .backgroundColor(Color.White)
                  .onClick(() => { this.openViewer(photo); })
                }, (photo: Photo) => `${photo.id}_${photo.updatedAt}`)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (group: PhotoGroup) => group.label)
          }
          .padding(16)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.themeLightBg)
    .bindContentCover(this.showAddDialog, this.AddPhotoDialog())

    if (this.showPhotoViewer) {
      this.PhotoViewerOverlay()
    }
    if (this.showEditDialog) {
      this.EditPhotoDialog()
    }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 全屏照片查看器 ====================
  // 点击小图 → 全屏查看上传原图；底部操作按钮：编辑 / 删除（仅上传者可见）
  @Builder
  PhotoViewerOverlay() {
    if (this.showPhotoViewer && this.viewerPhoto) {
      Column() {
        // 顶部栏：上传者 + 关闭
        Row() {
          Text(this.getMemberLabel(this.viewerPhoto!.creatorId))
            .fontSize(13).fontColor(Color.White).layoutWeight(1)
          Text('✕')
            .fontSize(18).fontColor(Color.White)
            .width(34).height(34)
            .textAlign(TextAlign.Center)
            .borderRadius(17)
            .backgroundColor('#33FFFFFF')
            .onClick(() => { this.closeViewer(); })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 12, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        // 原图大图（等比缩放完整显示上传的原图）
        Image(this.toImageSrc(this.viewerPhoto!.url || this.viewerPhoto!.thumbnailUrl))
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)

        // 底部信息：描述 + 标签 + 时间 + 操作按钮
        Column() {
          if (this.viewerPhoto!.description) {
            Text(this.viewerPhoto!.description)
              .fontSize(15).fontColor(Color.White)
              .width('100%')
          }
          Row({ space: 12 }) {
            if (this.viewerPhoto!.eventTag) {
              Text(`🏷 ${this.viewerPhoto!.eventTag}`).fontSize(13).fontColor('#CCFFFFFF')
            }
            Text(formatIsoToLocal(this.viewerPhoto!.takenAt)).fontSize(13).fontColor('#CCFFFFFF')
          }
          .width('100%')
          .margin({ top: 6 })

          // 点赞 + 保存到相册
          Row({ space: 12 }) {
            Row() {
              Text(this.viewerLikedByMe ? '❤️' : '🤍').fontSize(18)
              if (this.viewerLikes.length > 0) {
                Text(`${this.viewerLikes.length}`).fontSize(14).fontColor(Color.White).margin({ left: 4 })
              }
            }
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor(this.viewerLikedByMe ? '#33FF6B6B' : '#26FFFFFF')
            .onClick(() => { this.toggleLike(); })

            Button('💾 保存到相册')
              .fontSize(14).fontColor(Color.White)
              .backgroundColor('#26FFFFFF')
              .borderRadius(18).height(36).layoutWeight(1)
              .onClick(() => { this.downloadPhoto(this.viewerPhoto!); })
          }
          .width('100%')
          .margin({ top: 12 })

          // 评论列表（只能删自己的）
          if (this.viewerComments.length > 0) {
            Scroll() {
              Column({ space: 8 }) {
                ForEach(this.viewerComments, (c: PhotoComment) => {
                  Row() {
                    Text(this.getMemberLabel(c.creatorId)).fontSize(12).fontColor('#CCFFFFFF')
                    Text(c.content).fontSize(14).fontColor(Color.White)
                      .layoutWeight(1)
                      .margin({ left: 8, right: 8 })
                    Text(this.relativeTime(c.createdAt)).fontSize(11).fontColor('#66FFFFFF')
                    if (this.db.isRecordCreator(c.creatorId)) {
                      Text('删除').fontSize(12).fontColor('#FF9C94')
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
            .constraintSize({ maxHeight: 140 })
            .margin({ top: 12 })
            .scrollBar(BarState.Off)
          }

          // 评论输入
          Row({ space: 8 }) {
            TextInput({ placeholder: '写评论...', text: this.commentInput })
              .fontSize(14).fontColor(Color.White)
              .backgroundColor('#26FFFFFF')
              .borderRadius(18).height(36).layoutWeight(1)
              .placeholderColor('#66FFFFFF')
              .onChange((v: string) => { this.commentInput = v; })
              .onClick(() => {}) // 消费点击，避免冒泡到外层关闭查看器
            Button(this.isSendingComment ? '发送中' : '发送')
              .fontSize(14).fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(18).height(36)
              .enabled(!this.isSendingComment)
              .onClick(() => { this.sendComment(); })
          }
          .width('100%')
          .margin({ top: 10 })

          if (this.isCreator(this.viewerPhoto!.creatorId)) {
            // 编辑 / 删除为两个独立按钮，间距拉开避免误触
            Row({ space: 16 }) {
              Button('✏️ 编辑')
                .fontSize(15).fontColor(Color.White)
                .backgroundColor('#26FFFFFF')
                .borderRadius(22).height(44).layoutWeight(1)
                .onClick(() => { this.openEditDialog(this.viewerPhoto); })
              Button('🗑 删除')
                .fontSize(15).fontColor('#FF9C94')
                .backgroundColor('#26FF6B6B')
                .borderRadius(22).height(44).layoutWeight(1)
                .onClick(() => { this.showDeleteConfirm(this.viewerPhoto); })
            }
            .width('100%')
            .margin({ top: 16 })
          } else {
            Text('只有上传者可编辑或删除这张照片')
              .fontSize(11).fontColor('#66FFFFFF').margin({ top: 12 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onClick(() => { this.closeViewer(); })
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

  /** 点赞/取消点赞：新建或墓碑删除自己的点赞记录，本地立即反馈，异步推云 */
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
      // 本地保存失败：回滚 UI，避免展示与存储不一致
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

  /** 相对时间显示 */
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

  /** 长按/按钮下载照片：云端先下载到沙箱，本地直接用；走系统弹窗免权限保存到相册 */
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

  /** 根据 creatorId 找到成员显示名（兼容 memberId / userId 两种格式） */
  private getMemberLabel(creatorId: string): string {
    if (!creatorId) return '家庭成员';
    const member = this.familyMembers.find(m => m.id === creatorId);
    if (member) return `${member.avatar} ${member.name}`;
    const byUser = this.familyMembers.find(m => m.userId === creatorId);
    if (byUser) return `${byUser.avatar} ${byUser.name}`;
    return '家庭成员';
  }

  /** 打开简易编辑框：只改名称/备注和标签，不换照片 */
  private openEditDialog(photo: Photo | null): void {
    if (!photo) return;
    this.editDesc = photo.description;
    this.editTag = photo.eventTag;
    this.showEditDialog = true;
  }

  /** 删除确认（仅创建者可见入口，二次确认防误删） */
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

  /** 保存简易编辑：仅更新描述 + 标签，照片文件不变 */
  private async savePhotoEdit(): Promise<void> {
    if (this.isSavingEdit) return; // 防双击
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
        takenAt: photo.takenAt
      };
      await this.db.updatePhoto(updated);
      this.photos = this.db.getPhotos();
      // 查看器保持打开，刷新为最新数据
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
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).margin({ bottom: 16 })

        // 照片选择
        Column() {
          if (this.selectedPhotoUri) {
            Image(this.toImageSrc(this.selectedPhotoUri))
              .width('100%').height(150)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
          } else {
            Text('📷').fontSize(40)
            Text('点击选择照片').fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 8 })
            Text('从相册中选择或拍摄照片').fontSize(11).fontColor(NEUTRAL_INK_SECONDARY).margin({ top: 4 })
          }
        }
        .width('100%')
        .height(150)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor(BG_SUBTLE)
        .border({ width: 1, color: BORDER_SUBTLE, style: BorderStyle.Dashed })
        .margin({ bottom: 12 })
        .onClick(() => { this.pickPhoto(); })

        TextInput({ placeholder: '照片描述（可选）', text: this.newDescription })
          .width('100%').padding(14).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newDescription = v; })

        // 事件标签选择
        Text('事件标签').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 4 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tagOptions, (item: TagOption) => {
            Text(item.label)
              .fontSize(12)
              .fontColor(this.newEventTag === item.tag ? Color.White : NEUTRAL_INK_SECONDARY)
              .backgroundColor(this.newEventTag === item.tag ? this.themePrimary : BG_SUBTLE)
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .margin(3)
              .onClick(() => { this.newEventTag = item.tag; })
          }, (item: TagOption) => item.tag || 'none')
        }
        .width('100%')
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BORDER_SUBTLE)
            .borderRadius(20).layoutWeight(1)
            .onClick(() => {
              this.showAddDialog = false;
              this.resetForm();
            })
          Button(this.isSavingPhoto ? '保存中...' : '保存')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .enabled(!this.isSavingPhoto)
            .onClick(async () => {
              if (this.isSavingPhoto) return; // 防双击：上传期间忽略重复点击
              this.isSavingPhoto = true;
              try {
                const now = new Date().toISOString();
                const family = this.db.getCurrentFamily();
                const vis = this.db.resolveModuleVisibilityForRecord(ModuleId.ALBUM);
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
                  takenAt: now
                };
                // 先上传 Cloud Storage 再保存：url 改为云端下载 URL，其他成员才能看到照片；
                // 上传失败（离线等）保留本地路径，由 syncPendingPhotoUploads 后续补传
                if (photo.url && !photo.url.startsWith('http')) {
                  const downloadUrl = await CloudService.getInstance()
                    .uploadPhoto(photo.url, photo.familyId, photo.id);
                  if (downloadUrl) {
                    photo.url = downloadUrl; // thumbnailUrl 保留本地路径作本机缓存
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
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
      .onClick(() => {})
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
    }
  }

  /** 简易编辑框：仅改名称/备注 + 标签，不复用上传对话框 */
  @Builder
  EditPhotoDialog() {
    if (this.showEditDialog) {
      Column() {
        Column() {
          Text('编辑照片')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(NEUTRAL_INK).margin({ bottom: 4 })
          Text('修改名称备注和标签，照片本身不变')
            .fontSize(12).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 14 })

          Text('名称 / 备注').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 6 })
          TextInput({ placeholder: '给照片起个名字或备注（可选）', text: this.editDesc })
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .borderRadius(10)
            .backgroundColor(BG_SUBTLE)
            .margin({ bottom: 14 })
            .onChange((v: string) => { this.editDesc = v; })

          Text('标签').fontSize(13).fontColor(NEUTRAL_INK_SECONDARY).width('100%').margin({ bottom: 6 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tagOptions, (item: TagOption) => {
              Text(item.label)
                .fontSize(12)
                .fontColor(this.editTag === item.tag ? Color.White : NEUTRAL_INK_SECONDARY)
                .backgroundColor(this.editTag === item.tag ? this.themePrimary : BG_SUBTLE)
                .borderRadius(12)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .margin(3)
                .onClick(() => { this.editTag = item.tag; })
            }, (item: TagOption) => item.tag || 'none')
          }
          .width('100%')
          .margin({ bottom: 16 })

          Row({ space: 12 }) {
            Button('取消')
              .fontSize(14).fontColor(NEUTRAL_INK_SECONDARY).backgroundColor(BORDER_SUBTLE)
              .borderRadius(20).layoutWeight(1)
              .onClick(() => { this.showEditDialog = false; })
            Button(this.isSavingEdit ? '保存中...' : '保存')
              .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
              .borderRadius(20).layoutWeight(1)
              .enabled(!this.isSavingEdit)
              .onClick(() => { this.savePhotoEdit(); })
          }
        }
        .width('85%')
        .padding(20)
        .borderRadius(16)
        .backgroundColor(Color.White)
        .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#66000000')
      .justifyContent(FlexAlign.Center)
    }
  }

  private getFilteredPhotos(): Photo[] {
    if (!this.selectedMemberFilter) return this.photos;
    // creatorId 新格式存 memberId，旧格式存 userId（openID），需同时匹配
    const member = this.familyMembers.find(m => m.id === this.selectedMemberFilter);
    const targetUserId = member ? member.userId : '';
    return this.photos.filter(p =>
      p.creatorId === this.selectedMemberFilter || // 新格式：memberId
      (targetUserId && p.creatorId === targetUserId) // 旧格式：userId
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

  /** 按事件标签分组（未打标签或标签非预设的归入「未分类」），已定义标签在前、未分类最后 */
  private getTagGroups(): PhotoGroup[] {
    const filtered = this.getFilteredPhotos();
    const groups: PhotoGroup[] = [];
    const groupedIds = new Set<string>();
    for (const opt of this.tagOptions) {
      if (!opt.tag) continue;
      // 兼容旧数据：eventTag 可能存的是带 emoji 的 label（如 '☀️ 日常'），两种都归入本组
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
        label: '📷 未分类',
        photos: uncategorized.sort((a, b) => b.takenAt.localeCompare(a.takenAt))
      });
    }
    return groups;
  }

  /** 当前分组视图的数据源：按日期 / 按标签 */
  private getGroupsForMode(): PhotoGroup[] {
    return this.currentViewMode === 2 ? this.getTagGroups() : this.getGroupedPhotos();
  }

  private async deletePhotoWithFile(photo: Photo): Promise<void> {
    const localPaths: string[] = [];
    if (photo.url && !photo.url.startsWith('http')) { localPaths.push(photo.url); }
    if (photo.thumbnailUrl && !photo.thumbnailUrl.startsWith('http')) { localPaths.push(photo.thumbnailUrl); }
    for (const path of localPaths) {
      try { fileIo.unlinkSync(path); } catch (_) {}
    }
    // 已上云的照片同步删除云端文件，避免残留占用云存储
    if (photo.url && photo.url.startsWith('http')) {
      await CloudService.getInstance().deleteFile(CloudService.photoCloudPath(photo.familyId, photo.id));
    }
    // 级联删除该照片的点赞/评论记录
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
