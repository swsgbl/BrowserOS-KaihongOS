import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { TabManager } from './TabManager'

/**
 * P55: TabGroupManager —— 命名标签分组（create/join/leave/list/ungroup）
 * 数据结构 { groupId, name, tabIds[], createdAt }，Preferences 持久化（tab_groups 键）。
 * tab 被关闭时自动从组内移除（由 MCPServer tabs close 路径调用 cleanupTab）。
 */
interface TabGroup {
  groupId: string
  name: string
  tabIds: string[]
  createdAt: number
}

class TabGroupManagerImpl {
  private groups: Map<string, TabGroup> = new Map()
  private static PREFS_CTX: common.UIAbilityContext | null = null
  private static readonly STORE_NAME: string = 'tab_groups_state'
  private static readonly KEY_GROUPS: string = 'groups'
  private prefsInstance: preferences.Preferences | null = null
  private persistTimer: number = -1

  setContext(ctx: common.UIAbilityContext): void {
    TabGroupManagerImpl.PREFS_CTX = ctx
    this.restore()
  }

  private ensurePrefs(): preferences.Preferences | null {
    if (this.prefsInstance) {
      return this.prefsInstance
    }
    if (!TabGroupManagerImpl.PREFS_CTX) {
      console.warn('[TabGroupManager] prefs context not set, persistence disabled')
      return null
    }
    try {
      this.prefsInstance = preferences.getPreferencesSync(TabGroupManagerImpl.PREFS_CTX,
        { name: TabGroupManagerImpl.STORE_NAME })
      return this.prefsInstance
    } catch (e) {
      console.error('[TabGroupManager] getPreferencesSync error: ' + e)
      return null
    }
  }

  private restore(): void {
    const p = this.ensurePrefs()
    if (!p) {
      return
    }
    try {
      const raw = p.getSync(TabGroupManagerImpl.KEY_GROUPS, '[]') as string
      const arr = JSON.parse(raw) as TabGroup[]
      this.groups.clear()
      for (const g of arr) {
        if (g && g.groupId && g.name !== undefined) {
          this.groups.set(g.groupId, {
            groupId: g.groupId, name: g.name,
            tabIds: Array.isArray(g.tabIds) ? g.tabIds : [],
            createdAt: g.createdAt || 0
          })
        }
      }
      console.info('[TabGroupManager] restored ' + this.groups.size + ' groups')
    } catch (e) {
      console.error('[TabGroupManager] restore error: ' + e)
    }
  }

  private schedulePersist(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer)
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1
      const p = this.ensurePrefs()
      if (!p) {
        return
      }
      try {
        const arr: TabGroup[] = []
        this.groups.forEach((g) => arr.push(g))
        p.putSync(TabGroupManagerImpl.KEY_GROUPS, JSON.stringify(arr))
        p.flush()
      } catch (e) {
        console.error('[TabGroupManager] persist error: ' + e)
      }
    }, 300)
  }

  /** 创建命名分组；同名组已存在直接返回 */
  create(name: string): TabGroup | null {
    if (!name || name.trim().length === 0) {
      return null
    }
    const existing = this.findByName(name.trim())
    if (existing) {
      return existing
    }
    const group: TabGroup = {
      groupId: 'grp_' + Date.now() + '_' + Math.floor(Math.random() * 10000),
      name: name.trim(),
      tabIds: [],
      createdAt: Date.now()
    }
    this.groups.set(group.groupId, group)
    this.schedulePersist()
    return group
  }

  /** tab 加入分组（已在他组则先移出；组不存在返回 false） */
  join(groupId: string, tabId: string): boolean {
    const g = this.groups.get(groupId)
    if (!g) {
      return false
    }
    if (!TabManager.getTab(tabId)) {
      return false
    }
    // leave any other group first (a tab belongs to at most one group)
    this.groups.forEach((other) => {
      if (other.groupId !== groupId) {
        const pos = other.tabIds.indexOf(tabId)
        if (pos >= 0) {
          other.tabIds.splice(pos, 1)
        }
      }
    })
    if (g.tabIds.indexOf(tabId) < 0) {
      g.tabIds.push(tabId)
    }
    this.schedulePersist()
    return true
  }

  /** tab 从分组移除（不在组内返回 false） */
  leave(groupId: string, tabId: string): boolean {
    const g = this.groups.get(groupId)
    if (!g) {
      return false
    }
    const pos = g.tabIds.indexOf(tabId)
    if (pos < 0) {
      return false
    }
    g.tabIds.splice(pos, 1)
    this.schedulePersist()
    return true
  }

  list(): TabGroup[] {
    const out: TabGroup[] = []
    this.groups.forEach((g) => out.push(g))
    return out
  }

  /** 解散分组：tabs 保留但不归组；组不存在返回 false */
  ungroup(groupId: string): boolean {
    const ok = this.groups.delete(groupId)
    if (ok) {
      this.schedulePersist()
    }
    return ok
  }

  findByName(name: string): TabGroup | null {
    let hit: TabGroup | null = null
    this.groups.forEach((g) => {
      if (!hit && g.name === name) {
        hit = g
      }
    })
    return hit
  }

  /** tab 关闭时清理所有组内引用 */
  cleanupTab(tabId: string): void {
    let dirty = false
    this.groups.forEach((g) => {
      const pos = g.tabIds.indexOf(tabId)
      if (pos >= 0) {
        g.tabIds.splice(pos, 1)
        dirty = true
      }
    })
    if (dirty) {
      this.schedulePersist()
    }
  }
}

export const TabGroupManager = new TabGroupManagerImpl()
