/**
 * P18: 搜索引擎注册表 —— omnibox 非 URL 输入的搜索引擎 fallback 数据源。
 * queryUrl 为含参数名的查询模板，拼接 encodeURIComponent(input) 即成完整搜索 URL。
 */
export class SearchEngine {
  id: string = ''
  name: string = ''
  queryUrl: string = ''
  homeUrl: string = ''
  desc: string = ''

  constructor(id: string, name: string, queryUrl: string, homeUrl: string, desc: string) {
    this.id = id
    this.name = name
    this.queryUrl = queryUrl
    this.homeUrl = homeUrl
    this.desc = desc
  }
}

export const SEARCH_ENGINES: SearchEngine[] = [
  new SearchEngine('google', 'Google', 'https://www.google.com/search?q=', 'https://www.google.com', '全球最常用的搜索引擎'),
  new SearchEngine('bing', 'Bing', 'https://www.bing.com/search?q=', 'https://www.bing.com', '微软搜索引擎'),
  new SearchEngine('duckduckgo', 'DuckDuckGo', 'https://duckduckgo.com/?q=', 'https://duckduckgo.com', '不追踪的隐私搜索'),
  new SearchEngine('baidu', '百度', 'https://www.baidu.com/s?wd=', 'https://www.baidu.com', '国内最大中文搜索引擎'),
  new SearchEngine('sogou', '搜狗', 'https://www.sogou.com/web?query=', 'https://www.sogou.com', '腾讯系搜索引擎'),
  new SearchEngine('so360', '360 搜索', 'https://www.so.com/s?q=', 'https://www.so.com', '360 系搜索引擎'),
  new SearchEngine('toutiao', '头条搜索', 'https://so.toutiao.com/search?dvpf=pc&source=input&keyword=', 'https://so.toutiao.com', '字节跳动搜索引擎'),
  new SearchEngine('yandex', 'Yandex', 'https://yandex.com/search/?text=', 'https://yandex.com', '俄罗斯搜索引擎'),
  new SearchEngine('brave', 'Brave Search', 'https://search.brave.com/search?q=', 'https://search.brave.com', 'Brave 独立索引搜索')
]

export function getEngineById(id: string): SearchEngine {
  for (const e of SEARCH_ENGINES) {
    if (e.id === id) {
      return e
    }
  }
  return SEARCH_ENGINES[0]
}
