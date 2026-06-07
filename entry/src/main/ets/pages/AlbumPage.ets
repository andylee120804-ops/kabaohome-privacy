/**
 * 卡宝Home - 家庭相册页面
 * 照片选择 + 事件归档 + 成员筛选 + 时间线展示
 */
import { Photo } from '../model/Photo';
import { LocalDbService } from '../service/LocalDbService';
import { EmptyState } from '../components/EmptyState';
import { FamilyMember } from '../model/FamilyMember';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { Visibility, FontSizeMode, THEME_PALETTES } from '../common/Constants';
import { generateId, formatDate } from '../common/Utils';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import router from '@ohos.router';

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
  @State editingPhotoId: string = '';
  @State newDescription: string = '';
  @State newEventTag: string = '';
  @State selectedPhotoUri: string = '';
  @State showPhotoDetail: boolean = false;
  @State detailPhoto: Photo | null = null;
  @State isLargeFont: boolean = false;
  @State fontSize: number = 16;
  @State titleFontSize: number = 20;
  @State themePrimary: string = '#1565C0';
  @State themeBorder: string = '#FFD4C2';
  @State themeLightBg: string = '#FFF5F0';
  @State currentViewMode: number = 0; // 0=网格 1=时间线

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
    return creatorId === this.db.getCurrentUserId();
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
      fileIo.copyFileSync(sourceUri, destPath);
      return destPath;
    } catch (_) {
      return sourceUri;
    }
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
            this.editingPhotoId = '';
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
            .fontColor(this.selectedMemberFilter === '' ? Color.White : '#666666')
            .backgroundColor(this.selectedMemberFilter === '' ? this.themePrimary : '#F5F5F5')
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .onClick(() => { this.selectedMemberFilter = ''; })
          ForEach(this.familyMembers, (member: FamilyMember) => {
            Text(member.avatar)
              .fontSize(14)
              .fontColor(this.selectedMemberFilter === member.id ? Color.White : '#666666')
              .backgroundColor(this.selectedMemberFilter === member.id ? member.color : '#F5F5F5')
              .borderRadius(12)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => { this.selectedMemberFilter = member.id; })
          }, (member: FamilyMember) => member.id)

          // 视图切换
          Text(this.currentViewMode === 0 ? '📋' : '🖼')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor('#999999')
            .borderRadius(12)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => { this.currentViewMode = this.currentViewMode === 0 ? 1 : 0; })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

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
                    Image(photo.url || photo.thumbnailUrl)
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
                .backgroundColor('#F5F5F5')
                .borderRadius(8)

                if (photo.description) {
                  Text(photo.description)
                    .fontSize(15).fontColor('#666666')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                Row() {
                  if (photo.eventTag) {
                    Text(`🏷 ${photo.eventTag}`).fontSize(12).fontColor('#999999')
                  }
                  Text(photo.takenAt.slice(5, 10)).fontSize(12).fontColor('#CCCCCC')
                }.width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ top: 2 })
              }
              .width('48%')
              .margin('1%')
              .alignItems(HorizontalAlign.Start)
              .onClick(() => {
                this.detailPhoto = photo;
                this.showPhotoDetail = true;
              })
              .gesture(
                LongPressGesture()
                  .onAction(() => {
                    if (!this.isCreator(photo.creatorId)) {
                      AlertDialog.show({ message: '只能删除自己创建的记录' });
                      return;
                    }
                    AlertDialog.show({
                      title: '确认删除',
                      message: '确定要删除这张照片吗？',
                      primaryButton: { value: '取消', action: () => {} },
                      secondaryButton: {
                        value: '删除', fontColor: '#C62828',
                        action: async () => {
                          await this.db.deletePhoto(photo.id);
                          this.photos = this.db.getPhotos();
                        }
                      }
                    });
                  })
              )
            }, (photo: Photo) => photo.id)
          }
          .padding(16)
        } else {
          // 时间线视图
          Column({ space: 12 }) {
            ForEach(this.getGroupedPhotos(), (group: PhotoGroup) => {
              Column({ space: 8 }) {
                Text(group.dateLabel).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#333333').width('100%')
                ForEach(group.photos, (photo: Photo) => {
                  Row() {
                    Column() {
                      if (photo.url || photo.thumbnailUrl) {
                        Image(photo.url || photo.thumbnailUrl)
                          .width(60).height(60)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(8)
                      } else {
                        Text('🖼️').fontSize(24)
                      }
                    }
                    .width(60).height(60)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor('#F5F5F5')
                    .borderRadius(8)
                    .margin({ right: 10 })

                    Column() {
                      Text(photo.description || '无描述').fontSize(17).fontColor('#333333')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row() {
                        if (photo.eventTag) {
                          Text(`🏷 ${photo.eventTag}`).fontSize(13).fontColor('#999999').margin({ right: 8 })
                        }
                        Text(photo.takenAt.slice(11, 16)).fontSize(13).fontColor('#CCCCCC')
                      }.margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(8)
                  .backgroundColor(Color.White)
                  .onClick(() => {
                    this.detailPhoto = photo;
                    this.showPhotoDetail = true;
                  })
                }, (photo: Photo) => photo.id)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (group: PhotoGroup) => group.dateLabel)
          }
          .padding(16)
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.themeLightBg)
    .bindContentCover(this.showAddDialog, this.AddPhotoDialog())

    if (this.showPhotoDetail) {
      this.PhotoDetailOverlay()
    }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 照片详情弹窗 ====================
  @Builder
  PhotoDetailOverlay() {
    Column() {
      Column() {
        Row() {
          Text('📷 照片详情').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          Text('✕').fontSize(18).fontColor('#999999').onClick(() => {
            this.showPhotoDetail = false;
            this.detailPhoto = null;
          })
        }.width('100%').margin({ bottom: 16 })

        if (this.detailPhoto) {
          // 照片预览
          Column() {
            if (this.detailPhoto.url || this.detailPhoto.thumbnailUrl) {
              Image(this.detailPhoto.url || this.detailPhoto.thumbnailUrl)
                .width('100%').height(200)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)
            } else {
              Text('🖼️').fontSize(48)
            }
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F5F5F5')
          .borderRadius(12)
          .margin({ bottom: 12 })

          // 描述
          if (this.detailPhoto.description) {
            Text(this.detailPhoto.description)
              .fontSize(15).fontColor('#444444')
              .width('100%').margin({ bottom: 8 })
          }

          // 标签
          Row({ space: 8 }) {
            if (this.detailPhoto.eventTag) {
              Text(`🏷 ${this.detailPhoto.eventTag}`)
                .fontSize(13).fontColor('#999999')
            }
            Text(this.detailPhoto.takenAt.slice(0, 16).replace('T', ' '))
              .fontSize(12).fontColor('#BBBBBB')
          }
          .width('100%').margin({ bottom: 16 })

          Row({ space: 12 }) {
            Button('关闭')
              .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
              .borderRadius(20).layoutWeight(1)
              .onClick(() => {
                this.showPhotoDetail = false;
                this.detailPhoto = null;
              })

            if (this.isCreator(this.detailPhoto.creatorId)) {
              Button('编辑')
                .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
                .borderRadius(20).layoutWeight(1)
                .onClick(() => {
                  const photo = this.detailPhoto!;
                  this.editingPhotoId = photo.id;
                  this.newDescription = photo.description;
                  this.newEventTag = photo.eventTag;
                  this.showPhotoDetail = false;
                  this.detailPhoto = null;
                  this.showAddDialog = true;
                })
            }
          }
          .width('100%')
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
    .onClick(() => {
      this.showPhotoDetail = false;
      this.detailPhoto = null;
    })
  }

  @Builder
  AddPhotoDialog() {
    if (this.showAddDialog) {
      Column() {
        Text(this.editingPhotoId ? '编辑照片' : '上传照片')
          .fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 16 })

        // 照片选择
        Column() {
          if (this.selectedPhotoUri) {
            Image(this.selectedPhotoUri)
              .width('100%').height(150)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
          } else {
            Text('📷').fontSize(40)
            Text('点击选择照片').fontSize(14).fontColor('#666666').margin({ top: 8 })
            Text('从相册中选择或拍摄照片').fontSize(11).fontColor('#999999').margin({ top: 4 })
          }
        }
        .width('100%')
        .height(150)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor('#F5F5F5')
        .border({ width: 1, color: '#E0E0E0', style: BorderStyle.Dashed })
        .margin({ bottom: 12 })
        .onClick(() => { this.pickPhoto(); })

        TextInput({ placeholder: '照片描述（可选）', text: this.newDescription })
          .width('100%').padding(14).borderRadius(8).margin({ bottom: 8 })
          .onChange((v: string) => { this.newDescription = v; })

        // 事件标签选择
        Text('事件标签').fontSize(13).fontColor('#666666').width('100%').margin({ bottom: 4 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tagOptions, (item: TagOption) => {
            Text(item.label)
              .fontSize(12)
              .fontColor(this.newEventTag === item.tag ? Color.White : '#666666')
              .backgroundColor(this.newEventTag === item.tag ? this.themePrimary : '#F5F5F5')
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
            .fontSize(14).fontColor('#666666').backgroundColor('#F0F0F0')
            .borderRadius(20).layoutWeight(1)
            .onClick(() => {
              this.showAddDialog = false;
              this.editingPhotoId = '';
              this.resetForm();
            })
          Button('保存')
            .fontSize(14).fontColor(Color.White).backgroundColor(this.themePrimary)
            .borderRadius(20).layoutWeight(1)
            .onClick(async () => {
              if (this.editingPhotoId) {
                const existing = this.photos.find(p => p.id === this.editingPhotoId);
                if (existing) {
                  const updated: Photo = {
                    id: existing.id,
                    familyId: existing.familyId,
                    creatorId: existing.creatorId,
                    visibility: existing.visibility,
                    visibleMembers: existing.visibleMembers,
                    version: existing.version + 1,
                    createdAt: existing.createdAt,
                    updatedAt: new Date().toISOString(),
                    url: this.selectedPhotoUri || existing.url,
                    thumbnailUrl: this.selectedPhotoUri || existing.thumbnailUrl,
                    description: this.newDescription,
                    eventTag: this.newEventTag,
                    takenAt: existing.takenAt
                  };
                  await this.db.updatePhoto(updated);
                }
              } else {
                const now = new Date().toISOString();
                const userId = this.db.getCurrentUserId();
                const family = this.db.getCurrentFamily();
                const photo: Photo = {
                  id: generateId('ph'),
                  familyId: family?.id ?? '',
                  creatorId: userId,
                  visibility: Visibility.FAMILY,
                  visibleMembers: [],
                  version: 1,
                  createdAt: now,
                  updatedAt: now,
                  url: this.selectedPhotoUri,
                  thumbnailUrl: this.selectedPhotoUri,
                  description: this.newDescription,
                  eventTag: this.newEventTag,
                  takenAt: now
                };
                await this.db.savePhoto(photo);
              }
              this.showAddDialog = false;
              this.editingPhotoId = '';
              this.resetForm();
              this.photos = this.db.getPhotos();
            })
        }
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Color.White)
      .shadow({ radius: 20, color: '#33000000', offsetX: 0, offsetY: 10 })
    }
  }

  private getFilteredPhotos(): Photo[] {
    if (!this.selectedMemberFilter) return this.photos;
    // selectedMemberFilter 存的是 memberId，而 photo.creatorId 是 userId，需先查成员的 userId 再匹配
    const member = this.familyMembers.find(m => m.id === this.selectedMemberFilter);
    const targetUserId = member ? member.userId : '';
    if (!targetUserId) return this.photos;
    return this.photos.filter(p => p.creatorId === targetUserId);
  }

  private getGroupedPhotos(): PhotoGroup[] {
    const filtered = this.getFilteredPhotos();
    const groups: PhotoGroup[] = [];
    const dateMap: Record<string, Photo[]> = {};

    for (const photo of filtered) {
      const dateKey = photo.takenAt.slice(0, 10);
      if (!dateMap[dateKey]) {
        dateMap[dateKey] = [];
      }
      dateMap[dateKey].push(photo);
    }

    const sortedDates = Object.keys(dateMap).sort((a, b) => b.localeCompare(a));
    for (const date of sortedDates) {
      const d = new Date(date);
      const weekDays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
      groups.push({
        dateLabel: `${date.slice(5)} ${weekDays[d.getDay()]}`,
        photos: dateMap[date]
      });
    }

    return groups;
  }

  private resetForm(): void {
    this.newDescription = '';
    this.newEventTag = '';
    this.editingPhotoId = '';
    this.selectedPhotoUri = '';
  }
}

interface PhotoGroup {
  dateLabel: string;
  photos: Photo[];
}
