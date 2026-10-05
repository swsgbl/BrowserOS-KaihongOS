import { StorageManager } from '../storage/StorageManager'

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
    return bookmark
  }

  removeBookmark(id: string): boolean {
    const result = this.bookmarks.delete(id)
    if (result) {
      this.persist()
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

  getBookmarkCount(): number {
    return this.bookmarks.size
  }
}

export const BookmarkManager = new BookmarkManagerImpl()