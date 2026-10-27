/**
 * P9-A: Chromium 风格浏览器 chrome 补全组件
 * - ThreeDotMenu: ⋮ 主菜单下拉（分组：新建标签页/新窗口 | 历史/书签/下载 | 设置/帮助 | 退出）
 * - OmniboxSuggestions: omnibox 聚焦建议下拉（历史+书签匹配）
 * - BookmarkBubble: 星标书签气泡（名称编辑 + 完成/删除）
 * 设计语言：#F1F3F4 chrome / #FFFFFF 卡 / #5F6368 图标 / #1A73E8 强调 / 分隔 #E0E0E0
 */

import { Palette } from '../common/Palette'
import { I18n } from '../common/I18n'

export interface SuggestItem {
  kind: string // 'search' | 'history' | 'bookmark'
  title: string
  url: string
}

interface MenuEntry {
  icon: Resource
  label: string
  action: string
}

/** ⋮ 三点主菜单（自绘下拉，右上下锚定） */
@Component
export struct ThreeDotMenu {
  // P48: locale 刷新锚 —— @StorageProp 变化时递增 version 驱动本 struct 重渲染
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }  onAction: (action: string) => void = (action: string) => {}
  onClose: () => void = () => {}
  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  private group1(): MenuEntry[] {
    return [
      { icon: $rawfile('ic_add.svg'), label: I18n.t('menuNewTab'), action: 'new_tab' },
      // P50: 设置置顶第 2 位 —— 原在 group3 第 9 行,菜单卡 constraintSize(420) 不可滚,实际被裁剪不可见(用户找不到设置入口根因)
      { icon: $rawfile('ic_settings.svg'), label: I18n.t('menuSettings'), action: 'settings' },
      { icon: $rawfile('ic_content_copy.svg'), label: I18n.t('menuNewWindow'), action: 'new_window' },
      { icon: $rawfile('ic_incognito.svg'), label: I18n.t('menuNewIncognito'), action: 'new_incognito' }
    ]
  }
  private group2(): MenuEntry[] {
    return [
      { icon: $rawfile('ic_history.svg'), label: I18n.t('menuHistory'), action: 'history' },
      { icon: $rawfile('ic_star_outline.svg'), label: I18n.t('menuBookmarks'), action: 'bookmarks' },
      { icon: $rawfile('ic_download.svg'), label: I18n.t('menuDownloads'), action: 'downloads' },
      { icon: $rawfile('ic_key.svg'), label: I18n.t('menuPasswords'), action: 'passwords' }
    ]
  }
  private group3(): MenuEntry[] {
    return [
      { icon: $rawfile('ic_schedule.svg'), label: I18n.t('menuScheduled'), action: 'scheduled_tasks' },
      { icon: $rawfile('ic_robot.svg'), label: I18n.t('menuSkills'), action: 'skills' },
      { icon: $rawfile('ic_zoom_search.svg'), label: I18n.t('menuZoomIn'), action: 'zoom_in' },
      { icon: $rawfile('ic_zoom_out.svg'), label: I18n.t('menuZoomOut'), action: 'zoom_out' },
      { icon: $rawfile('ic_reload.svg'), label: I18n.t('menuZoomReset'), action: 'zoom_reset' },
      { icon: $rawfile('ic_reader.svg'), label: I18n.t('menuReader'), action: 'reader' },
      { icon: $rawfile('ic_edit.svg'), label: I18n.t('menuFillForm'), action: 'fill_form' },
      { icon: $rawfile('ic_bug.svg'), label: I18n.t('menuDevtools'), action: 'devtools' },
      { icon: $rawfile('ic_find.svg'), label: I18n.t('menuFind'), action: 'find' },
      { icon: $rawfile('ic_help.svg'), label: I18n.t('menuHelp'), action: 'help' }
    ]
  }

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('ChromeWidgets theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P51-C: localeVersion anchor
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      // 全屏透明遮罩：点击任意处关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.onClose()
        })

      // 菜单卡（右上下锚定，宽 240）
      Column() {
        this.MenuGroup(this.group1())
        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })
        this.MenuGroup(this.group2())
        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })
        this.MenuGroup(this.group3())
        Divider().color(this.pal().border).margin({ top: 4, bottom: 4 })
        Row() {
          Image($rawfile('ic_exit.svg'))
            .width(18).height(18)
            .fillColor('#C5221F')
            .draggable(false)
          Text(I18n.t('menuExit'))
            .fontSize(14)
            .fontColor('#C5221F')
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .onClick(() => {
          this.onAction('exit')
        })
      }
      .width(240)
      .constraintSize({ maxHeight: 420 })
      .padding(6)
      .borderRadius(12)
      .backgroundColor(this.pal().surface)
      .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 44, right: 8 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MenuGroup(entries: MenuEntry[]): void {
    ForEach(entries, (entry: MenuEntry) => {
      Row() {
        Image(entry.icon)
          .width(18).height(18)
          .fillColor(this.pal().text2)
          .draggable(false)
        Text(entry.label)
          .fontSize(14)
          .fontColor(this.pal().text)
          .margin({ left: 4 })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .borderRadius(6)
      .onClick(() => {
        this.onAction(entry.action)
      })
    }, (entry: MenuEntry) => entry.action)
  }
}

/** omnibox 聚焦建议下拉（历史+书签匹配，图标+标题+URL） */
@Component
export struct OmniboxSuggestions {
  // P48: locale 刷新锚 —— @StorageProp 变化时递增 version 驱动本 struct 重渲染
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  items: SuggestItem[] = []
  engineName: string = ''
  onPick: (kind: string, url: string) => void = (kind: string, url: string) => {}
  onSwitchEngine: () => void = () => {}
  onClose: () => void = () => {}

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('ChromeWidgets theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Stack({ alignContent: Alignment.TopStart }) {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P51-C: localeVersion anchor
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      // 透明遮罩截获外部点击（不压暗）
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onClose()
        })

      if (this.items.length > 0) {
        Column() {
          ForEach(this.items, (item: SuggestItem, index: number) => {
            // P11d: kind 变化处插组头(历史记录/书签)
            if (index > 0 && item.kind !== this.items[index - 1].kind) {
              Text(item.kind === 'bookmark' ? I18n.t('menuBookmarks') : I18n.t('tbHistory'))
                .fontSize(11)
                .fontColor(this.pal().text2)
                .margin({ top: 4, bottom: 2, left: 8 })
                .alignSelf(ItemAlign.Start)
            }
            Row() {
              if (item.kind === 'search') {
                // P11d: 首行搜索项 —— ic_search + 「搜索 kw」粗体
                Image($rawfile('ic_search.svg'))
                  .width(16).height(16)
                  .fillColor(this.pal().text2)
                  .draggable(false)
                // P18: title 由 shell 侧拼好引擎名（如「百度 搜索 xx」）
                Text(item.title)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal().text)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 0 })
              } else {
                Image(item.kind === 'bookmark' ? $rawfile('ic_star_filled.svg') : $rawfile('ic_history.svg'))
                  .width(16).height(16)
                  .fillColor(item.kind === 'bookmark' ? '#F9AB00' : '#5F6368')
                  .draggable(false)
                Column() {
                  Text(item.title.length > 0 ? item.title : item.url)
                    .fontSize(13)
                    .fontColor(this.pal().text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.url)
                    .fontSize(10)
                    .fontColor(this.pal().text2)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 1 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .borderRadius(6)
            .backgroundColor(index === 0 ? this.pal().selected : this.pal().surface)
            .onClick(() => {
              this.onPick(item.kind, item.url)
            })
          }, (item: SuggestItem, index: number) => item.kind + '_' + item.url + '_' + index)
          // P18: 底部当前引擎标识 + 「切换」入口（跳设置页搜索节）
          Divider().color(this.pal().border).margin({ top: 4 })
          Row() {
            Image($rawfile('ic_search.svg'))
              .width(12).height(12)
              .fillColor(this.pal().text2)
              .draggable(false)
            Text(I18n.t('ntSearchEngine') + this.engineName)
              .fontSize(11)
              .fontColor(this.pal().text2)
              .layoutWeight(1)
              .margin({ left: 6 })
            Text(I18n.t('ntSwitch'))
              .fontSize(11)
              .fontColor('#1A73E8')
          }
          .width('100%')
          .height(34)
          .padding({ left: 12, right: 12 })
          .borderRadius(6)
          .onClick(() => {
            this.onSwitchEngine()
          })
        }
        .width(520)
        .constraintSize({ maxHeight: 360 })
        .padding(6)
        .borderRadius(12)
        .backgroundColor(this.pal().surface)
        .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
        .margin({ top: 50, left: 128 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 星标书签气泡：名称可编辑 + 完成/删除 */
@Component
export struct BookmarkBubble {
  // P48: locale 刷新锚 —— @StorageProp 变化时递增 version 驱动本 struct 重渲染
  @StorageProp('app_locale') @Watch('onLocaleFlip') appLocale: string = 'zh'
  @State localeVersion: number = 0

  onLocaleFlip(): void {
    this.localeVersion++
  }  @StorageProp('darkMode') @Watch('onThemeFlip') darkMode: boolean = false // P44
  @State themeVersion: number = 0 // P44

  private pal(): Palette {
    return Palette.of(this.darkMode)
  }

  title: string = ''
  url: string = ''
  editingExisting: boolean = false
  onTitleChange: (title: string) => void = (title: string) => {}
  onDone: () => void = () => {}
  onRemove: () => void = () => {}
  onClose: () => void = () => {}

  // P44: 主题翻转钩子——@StorageProp 变更不触发 @Builder 重调,靠 themeVersion 递增驱动全树重渲染
  onThemeFlip(): void {
    this.themeVersion++
    console.info('ChromeWidgets theme flipped: darkMode=' + this.darkMode + ' v=' + this.themeVersion)
  }

  build(): void {
    Stack({ alignContent: Alignment.TopEnd }) {
        // P44: themeVersion 渲染依赖锚（@Watch 递增触发全树重渲染——暗/浅切换时 @Builder 不重调的修复）
        if (this.themeVersion < 0) {
          Text('').fontSize(0)
        }
        // P51-C: localeVersion anchor
        if (this.localeVersion < 0) {
          Text('').fontSize(0)
        }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#22000000')
        .onClick(() => {
          this.onClose()
        })

      Column() {
        Text(this.editingExisting ? I18n.t('bmEdited') : I18n.t('bmAdded'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal().text)
          .alignSelf(ItemAlign.Start)

        Text(this.url)
          .fontSize(10)
          .fontColor(this.pal().text2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .alignSelf(ItemAlign.Start)

        Text(I18n.t('bmName'))
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 10, bottom: 4 })
          .alignSelf(ItemAlign.Start)
        TextInput({ text: this.title })
          .width('100%')
          .height(36)
          .fontSize(13)
          .backgroundColor(this.pal().surfaceAlt)
          .borderRadius(8)
          .onChange((value: string) => {
            this.onTitleChange(value)
          })

        // P11d: 文件夹只读行(书签数据模型无层级,固定「书签栏」)
        Text(I18n.t('bmFolder'))
          .fontSize(11)
          .fontColor(this.pal().text2)
          .margin({ top: 10, bottom: 4 })
          .alignSelf(ItemAlign.Start)
        Row() {
          Image($rawfile('ic_folder.svg'))
            .width(16).height(16)
            .fillColor(this.pal().text2)
            .draggable(false)
          Text(I18n.t('bmBar'))
            .fontSize(13)
            .fontColor(this.pal().text)
            .margin({ left: 6 })
          Blank()
          Image($rawfile('ic_more_vert.svg'))
            .width(14).height(14)
            .fillColor(this.pal().text2)
            .opacity(0.4)
            .draggable(false)
        }
        .width('100%')
        .height(34)
        .padding({ left: 10, right: 10 })
        .backgroundColor(this.pal().surfaceAlt)
        .borderRadius(8)

        Row() {
          if (this.editingExisting) {
            Button(I18n.t('delete'))
              .fontSize(13)
              .height(34)
              .backgroundColor(this.pal().surface)
              .fontColor('#C5221F')
              .borderRadius(17)
              .border({ width: 1, color: this.pal().border })
              .onClick(() => {
                this.onRemove()
              })
          }
          Blank()
          Button(I18n.t('done'))
            .fontSize(13)
            .height(34)
            .backgroundColor('#1A73E8')
            .fontColor('#FFFFFF')
            .borderRadius(17)
            .onClick(() => {
              this.onDone()
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width(280)
      .padding(14)
      .borderRadius(12)
      .backgroundColor(this.pal().surface)
      .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 44, right: 52 })
    }
    .width('100%')
    .height('100%')
  }
}
