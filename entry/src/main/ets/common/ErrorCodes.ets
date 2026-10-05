export class ErrorCodes {
  static readonly MCP_PREFIX: string = 'MCP'
  static readonly AGT_PREFIX: string = 'AGT'
  static readonly BCP_PREFIX: string = 'BCP'
  static readonly SES_PREFIX: string = 'SES'
  static readonly LGN_PREFIX: string = 'LGN'
  static readonly CON_PREFIX: string = 'CON'
  static readonly TAB_PREFIX: string = 'TAB'
  static readonly CFG_PREFIX: string = 'CFG'
  static readonly STG_PREFIX: string = 'STG'
  static readonly SYS_PREFIX: string = 'SYS'

  static readonly MCP_001: string = 'MCP-001'
  static readonly MCP_002: string = 'MCP-002'
  static readonly MCP_003: string = 'MCP-003'
  static readonly MCP_004: string = 'MCP-004'
  static readonly MCP_005: string = 'MCP-005'

  static readonly AGT_001: string = 'AGT-001'
  static readonly AGT_002: string = 'AGT-002'
  static readonly AGT_003: string = 'AGT-003'
  static readonly AGT_004: string = 'AGT-004'
  static readonly AGT_005: string = 'AGT-005'

  static readonly BCP_001: string = 'BCP-001'
  static readonly BCP_002: string = 'BCP-002'
  static readonly BCP_003: string = 'BCP-003'
  static readonly BCP_004: string = 'BCP-004'
  static readonly BCP_005: string = 'BCP-005'

  static readonly SES_001: string = 'SES-001'
  static readonly SES_002: string = 'SES-002'
  static readonly SES_003: string = 'SES-003'
  static readonly SES_004: string = 'SES-004'

  static readonly LGN_001: string = 'LGN-001'
  static readonly LGN_002: string = 'LGN-002'
  static readonly LGN_003: string = 'LGN-003'
  static readonly LGN_004: string = 'LGN-004'

  static readonly CON_001: string = 'CON-001'
  static readonly CON_002: string = 'CON-002'
  static readonly CON_003: string = 'CON-003'

  static readonly TAB_001: string = 'TAB-001'
  static readonly TAB_002: string = 'TAB-002'
  static readonly TAB_003: string = 'TAB-003'

  static readonly CFG_001: string = 'CFG-001'
  static readonly CFG_002: string = 'CFG-002'

  static readonly STG_001: string = 'STG-001'
  static readonly STG_002: string = 'STG-002'
  static readonly STG_003: string = 'STG-003'

  static readonly SYS_001: string = 'SYS-001'
  static readonly SYS_002: string = 'SYS-002'

  static getMessage(code: string): string {
    switch (code) {
      case ErrorCodes.MCP_001:
        return '认证失败：无效或缺失的认证令牌'
      case ErrorCodes.MCP_002:
        return '工具不存在：请求的MCP工具未定义'
      case ErrorCodes.MCP_003:
        return '参数错误：工具调用参数缺失或格式错误'
      case ErrorCodes.MCP_004:
        return '端口冲突：MCP服务器端口已被占用'
      case ErrorCodes.MCP_005:
        return '连接断开：MCP连接意外断开'
      case ErrorCodes.AGT_001:
        return '代理数量超限：已达到最大并行代理数'
      case ErrorCodes.AGT_002:
        return '代理不存在：指定的代理ID不存在'
      case ErrorCodes.AGT_003:
        return '代理状态错误：当前状态不允许此操作'
      case ErrorCodes.AGT_004:
        return '资源不足：内存不足，无法创建新代理'
      case ErrorCodes.AGT_005:
        return '代理超时：代理执行超时无进展'
      case ErrorCodes.BCP_001:
        return 'JS Bridge注入失败：WebView未准备好'
      case ErrorCodes.BCP_002:
        return '操作超时：BCP操作超过10秒未返回'
      case ErrorCodes.BCP_003:
        return '元素未找到：CSS选择器未匹配到元素'
      case ErrorCodes.BCP_004:
        return '页面未加载：目标页面尚未加载完成'
      case ErrorCodes.BCP_005:
        return '截图失败：html2canvas执行失败'
      case ErrorCodes.SES_001:
        return '录制启动失败：无法开始会话录制'
      case ErrorCodes.SES_002:
        return '存储空间不足：录制文件超出最大存储空间'
      case ErrorCodes.SES_003:
        return '会话文件损坏：录制文件无法读取'
      case ErrorCodes.SES_004:
        return '回放失败：会话数据不完整'
      case ErrorCodes.LGN_001:
        return 'Chrome数据未找到：无法检测到Chrome安装'
      case ErrorCodes.LGN_002:
        return 'Chrome数据格式不兼容：版本不支持'
      case ErrorCodes.LGN_003:
        return '加密存储失败：HUKS不可用'
      case ErrorCodes.LGN_004:
        return '登录态应用失败：WebView无法注入Cookie'
      case ErrorCodes.CON_001:
        return 'AI工具未检测到：本地未安装支持的AI工具'
      case ErrorCodes.CON_002:
        return '配置写入失败：权限不足'
      case ErrorCodes.CON_003:
        return '连接失败：MCP端点无法连接'
      case ErrorCodes.TAB_001:
        return '标签页创建失败：WebView实例创建失败'
      case ErrorCodes.TAB_002:
        return '标签页不存在：指定的标签页ID不存在'
      case ErrorCodes.TAB_003:
        return '标签页切换失败：WebView状态恢复失败'
      case ErrorCodes.CFG_001:
        return '配置项无效：值超出允许范围'
      case ErrorCodes.CFG_002:
        return '配置加载失败：配置文件损坏'
      case ErrorCodes.STG_001:
        return '存储初始化失败：文件系统不可用'
      case ErrorCodes.STG_002:
        return '存储读写失败：权限不足'
      case ErrorCodes.STG_003:
        return '存储空间不足：磁盘空间不够'
      case ErrorCodes.SYS_001:
        return '系统错误：未预期的内部错误'
      case ErrorCodes.SYS_002:
        return '内存不足：系统内存不足以继续运行'
      default:
        return `未知错误：${code}`
    }
  }
}