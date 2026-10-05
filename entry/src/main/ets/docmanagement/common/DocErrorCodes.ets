export class DocErrorCodes {
  static readonly DOC_PATH_001: string = 'DOC_PATH_001'
  static readonly DOC_PATH_002: string = 'DOC_PATH_002'
  static readonly DOC_PATH_003: string = 'DOC_PATH_003'

  static readonly DOC_STG_001: string = 'DOC_STG_001'
  static readonly DOC_STG_002: string = 'DOC_STG_002'
  static readonly DOC_STG_003: string = 'DOC_STG_003'
  static readonly DOC_STG_004: string = 'DOC_STG_004'
  static readonly DOC_STG_005: string = 'DOC_STG_005'

  static readonly DOC_TPL_001: string = 'DOC_TPL_001'
  static readonly DOC_TPL_002: string = 'DOC_TPL_002'

  static readonly DEV_PLAN_001: string = 'DEV_PLAN_001'
  static readonly DEV_PLAN_002: string = 'DEV_PLAN_002'
  static readonly DEV_PLAN_003: string = 'DEV_PLAN_003'
  static readonly DEV_PLAN_004: string = 'DEV_PLAN_004'
  static readonly DEV_PLAN_005: string = 'DEV_PLAN_005'
  static readonly DEV_PLAN_006: string = 'DEV_PLAN_006'
  static readonly DEV_PLAN_007: string = 'DEV_PLAN_007'

  static readonly DEV_LOG_001: string = 'DEV_LOG_001'
  static readonly DEV_LOG_002: string = 'DEV_LOG_002'
  static readonly DEV_LOG_003: string = 'DEV_LOG_003'
  static readonly DEV_LOG_004: string = 'DEV_LOG_004'
  static readonly DEV_LOG_005: string = 'DEV_LOG_005'

  static readonly CHANGELOG_001: string = 'CHANGELOG_001'
  static readonly CHANGELOG_002: string = 'CHANGELOG_002'
  static readonly CHANGELOG_003: string = 'CHANGELOG_003'
  static readonly CHANGELOG_004: string = 'CHANGELOG_004'
  static readonly CHANGELOG_005: string = 'CHANGELOG_005'
  static readonly CHANGELOG_006: string = 'CHANGELOG_006'

  static readonly STATUS_001: string = 'STATUS_001'
  static readonly STATUS_002: string = 'STATUS_002'
  static readonly STATUS_003: string = 'STATUS_003'

  static readonly MEETING_001: string = 'MEETING_001'
  static readonly MEETING_002: string = 'MEETING_002'
  static readonly MEETING_003: string = 'MEETING_003'
  static readonly MEETING_004: string = 'MEETING_004'

  static readonly ADR_001: string = 'ADR_001'
  static readonly ADR_002: string = 'ADR_002'
  static readonly ADR_003: string = 'ADR_003'
  static readonly ADR_004: string = 'ADR_004'
  static readonly ADR_005: string = 'ADR_005'
  static readonly ADR_006: string = 'ADR_006'

  static getMessage(code: string): string {
    switch (code) {
      case DocErrorCodes.DOC_PATH_001:
        return '路径错误：无效的文档类型'
      case DocErrorCodes.DOC_PATH_002:
        return '路径错误：目录层级超过3层限制'
      case DocErrorCodes.DOC_PATH_003:
        return '路径错误：目录创建失败'
      case DocErrorCodes.DOC_STG_001:
        return '存储错误：文档保存失败'
      case DocErrorCodes.DOC_STG_002:
        return '存储错误：文档加载失败'
      case DocErrorCodes.DOC_STG_003:
        return '存储错误：文档删除失败'
      case DocErrorCodes.DOC_STG_004:
        return '存储错误：路径越界（包含..或绝对路径前缀）'
      case DocErrorCodes.DOC_STG_005:
        return '存储错误：追加内容失败'
      case DocErrorCodes.DOC_TPL_001:
        return '模板错误：无效的文档类型'
      case DocErrorCodes.DOC_TPL_002:
        return '模板错误：占位符替换失败'
      case DocErrorCodes.DEV_PLAN_001:
        return '开发计划错误：里程碑名称超长（>30字符）'
      case DocErrorCodes.DEV_PLAN_002:
        return '开发计划错误：里程碑描述超长（>200字符）'
      case DocErrorCodes.DEV_PLAN_003:
        return '开发计划错误：计划完成日期格式无效或早于当前日期'
      case DocErrorCodes.DEV_PLAN_004:
        return '开发计划错误：里程碑状态流转违规'
      case DocErrorCodes.DEV_PLAN_005:
        return '开发计划错误：任务未关联到SDD tasks.md条目'
      case DocErrorCodes.DEV_PLAN_006:
        return '开发计划错误：任务粒度超过3个工作日'
      case DocErrorCodes.DEV_PLAN_007:
        return '开发计划错误：资源过载'
      case DocErrorCodes.DEV_LOG_001:
        return '开发日志错误：日志条目缺少必填字段'
      case DocErrorCodes.DEV_LOG_002:
        return '开发日志错误：日期格式无效'
      case DocErrorCodes.DEV_LOG_003:
        return '开发日志错误：问题状态流转违规'
      case DocErrorCodes.DEV_LOG_004:
        return '开发日志错误：月度归档失败'
      case DocErrorCodes.DEV_LOG_005:
        return '开发日志错误：检测到敏感凭证信息'
      case DocErrorCodes.CHANGELOG_001:
        return '变更日志错误：版本号不符合SemVer格式'
      case DocErrorCodes.CHANGELOG_002:
        return '变更日志错误：版本号跳号'
      case DocErrorCodes.CHANGELOG_003:
        return '变更日志错误：版本号已存在'
      case DocErrorCodes.CHANGELOG_004:
        return '变更日志错误：发布前置条件未满足'
      case DocErrorCodes.CHANGELOG_005:
        return '变更日志错误：变更类型无效'
      case DocErrorCodes.CHANGELOG_006:
        return '变更日志错误：HAP包构建失败'
      case DocErrorCodes.STATUS_001:
        return '状态报告错误：数据源文档缺失'
      case DocErrorCodes.STATUS_002:
        return '状态报告错误：进度数据矛盾'
      case DocErrorCodes.STATUS_003:
        return '状态报告错误：报告生成失败'
      case DocErrorCodes.MEETING_001:
        return '会议纪要错误：缺少必填字段'
      case DocErrorCodes.MEETING_002:
        return '会议纪要错误：行动项缺少负责人或截止日期'
      case DocErrorCodes.MEETING_003:
        return '会议纪要错误：行动项逾期未完成'
      case DocErrorCodes.MEETING_004:
        return '会议纪要错误：ADR提取失败'
      case DocErrorCodes.ADR_001:
        return 'ADR错误：编号格式无效'
      case DocErrorCodes.ADR_002:
        return 'ADR错误：编号冲突'
      case DocErrorCodes.ADR_003:
        return 'ADR错误：状态流转违规'
      case DocErrorCodes.ADR_004:
        return 'ADR错误：禁止删除已创建的ADR'
      case DocErrorCodes.ADR_005:
        return 'ADR错误：禁止修改已接受状态的ADR内容'
      case DocErrorCodes.ADR_006:
        return 'ADR错误：ADR与SDD文档矛盾'
      default:
        return '文档管理未知错误'
    }
  }
}