import { StorageManager } from '../storage/StorageManager'
import { EventBus, EventBusEvents } from '../infra/EventBus'

interface BookmarksChangedData {
  count: number
  action: string
}


interface Bookmark {
  id: string
  url: string
  title: string
  createdAt: number
}

interface BookmarkData {
  id: string
  url: string
  title: string
  createdAt: number
}

class BookmarkManagerImpl {
  private bookmarks: Map<string, Bookmark> = new Map()
  private bookmarkCounter: number = 0

  addBookmark(url: string, title: string): Bookmark {
    const id = `bm_${++this.bookmarkCounter}_${Date.now()}`
    const bookmark: Bookmark = { id, url, title, createdAt: Date.now() }
    this.bookmarks.set(id, bookmark)
    this.persist()
    this.notifyChanged('add')
    return bookmark
  }

  removeBookmark(id: string): boolean {
    const result = this.bookmarks.delete(id)
    if (result) {
      this.persist()
      this.notifyChanged('remove')
    }
    return result
  }

  updateBookmark(id: string, url?: string, title?: string): boolean {
    const bookmark = this.bookmarks.get(id)
    if (!bookmark) {
      return false
    }
    if (url) {
      bookmark.url = url
    }
    if (title) {
      bookmark.title = title
    }
    this.persist()
    this.notifyChanged('update')
    return true
  }

  getBookmark(id: string): Bookmark | null {
    return this.bookmarks.get(id) || null
  }

  getAllBookmarks(): Bookmark[] {
    return Array.from(this.bookmarks.values()).sort((a, b) => b.createdAt - a.createdAt)
  }

  searchBookmarks(keyword: string): Bookmark[] {
    const lowerKeyword = keyword.toLowerCase()
    return this.getAllBookmarks().filter(b =>
      b.title.toLowerCase().includes(lowerKeyword) ||
      b.url.toLowerCase().includes(lowerKeyword)
    )
  }

  isBookmarked(url: string): boolean {
    for (const bookmark of this.bookmarks.values()) {
      if (bookmark.url === url) {
        return true
      }
    }
    return false
  }

  getBookmarkIdByUrl(url: string): string | null {
    let result: string | null = null
    this.bookmarks.forEach((bookmark: Bookmark, id: string) => {
      if (bookmark.url === url && result === null) {
        result = id
      }
    })
    return result
  }

  /** P19b: 清空全部书签（设置页「清除浏览数据」用） */
  clearAllBookmarks(): void {
    if (this.bookmarks.size === 0) {
      return
    }
    this.bookmarks.clear()
    this.persist()
    this.notifyChanged('clear_all')
    console.info('[BookmarkManager] clearAllBookmarks done')
  }

  private async persist(): Promise<void> {
    const data: Record<string, BookmarkData> = {}
    this.bookmarks.forEach((bookmark: Bookmark, id: string) => {
      const bookmarkData: BookmarkData = {
        id: bookmark.id,
        url: bookmark.url,
        title: bookmark.title,
        createdAt: bookmark.createdAt
      }
      data[id] = bookmarkData
    })
    await StorageManager.saveJSON('tabs/bookmarks.json', data)
  }

  async load(): Promise<void> {
    const json = await StorageManager.loadJSON('tabs/bookmarks.json')
    if (json) {
      this.bookmarks.clear()
      for (const key of Object.keys(json)) {
        const bm = json[key] as Record<string, Object>
        this.bookmarks.set(key, {
          id: bm['id'] as string,
          url: bm['url'] as string,
          title: bm['title'] as string,
          createdAt: bm['createdAt'] as number
        })
      }
    }
  }

  /** P14b: 增删改后广播（订阅方: BrowserShell 书签条/星标、BookmarksPage 列表） */
  private notifyChanged(action: string): void {
    const data: BookmarksChangedData = { count: this.bookmarks.size, action: action }
    EventBus.emit(EventBusEvents.BOOKMARKS_CHANGED, data)
  }

  getBookmarkCount(): number {
    return this.bookmarks.size
  }
}

export const BookmarkManager = new BookmarkManagerImpl()