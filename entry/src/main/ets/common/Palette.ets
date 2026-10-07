/** p10a: 成对色板 —— 浅色 / 深色（Chrome 系配色）
 * surface 卡片/面板 · surfaceAlt 工具栏/导航 · surfaceInput 输入框/磁贴
 * text 主文本 · text2 次级 · border 边线 · selected 选中底 · tabInactive 非激活标签
 */
export class Palette {
  surface: string = '#FFFFFF'
  surfaceAlt: string = '#F1F3F4'
  surfaceInput: string = '#F5F5F5'
  text: string = '#202124'
  text2: string = '#5F6368'
  border: string = '#DADCE0'
  selected: string = '#E8F0FE'
  tabInactive: string = '#DEE1E6'
  accent: string = '#1A73E8'

  static of(dark: boolean): Palette {
    const p = new Palette()
    if (dark) {
      p.surface = '#292A2D'
      p.surfaceAlt = '#202124'
      p.surfaceInput = '#3C4043'
      p.text = '#E8EAED'
      p.text2 = '#9AA0A6'
      p.border = '#3C4043'
      p.selected = '#394457'
      p.tabInactive = '#35363A'
    }
    return p
  }
}
