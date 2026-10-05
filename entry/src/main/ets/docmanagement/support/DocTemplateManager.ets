import { DocType } from '../enums/DocEnums'
import { TemplateParams, TemplateInfo } from '../models/DocDataTypes'
import { DocErrorCodes } from '../common/DocErrorCodes'
import { ErrorHandler, AppError } from '../../infra/ErrorHandler'

const DEV_PLAN_TEMPLATE: string = `# BrowserOS KaihongOS 开发计划

## 里程碑总览

| 编号 | 名称 | 描述 | 目标交付物 | 计划完成日期 | 实际完成日期 | 状态 |
|------|------|------|-----------|-------------|-------------|------|
| {milestone-id} | {name} | {description} | {deliverables} | {planned-date} | {actual-date} | {status} |

## 任务分解

### {milestone-name}

| 任务编号 | 任务名称 | 关联SDD条目 | 负责人 | 预估工时(人日) | 计划开始 | 计划结束 | 状态 |
|---------|---------|------------|--------|--------------|---------|---------|------|
| {task-id} | {name} | {sdd-ref} | {assignee} | {estimated-days} | {planned-start} | {planned-end} | {status} |

## 时间线

{gantt-chart-placeholder}

## 资源分配

| 负责人 | 任务列表 | 总工时(人日) | 可用工时(人日) | 状态 |
|--------|---------|------------|--------------|------|
| {assignee} | {task-list} | {total-days} | {available-days} | {status} |
`

const DEV_LOG_TEMPLATE: string = `# 开发日志 - {year}年{month}月

## {date} - {author}

### 工作内容
{work-summary}

### 问题与风险
- [{problem-id}] {problem-description} — 状态: {status}
  - 解决方案: {solution}

### 决策与结论
{decisions}

### 关联任务
- {task-id}: {task-name}
`

const CHANGELOG_TEMPLATE: string = `# Changelog

本文件记录 BrowserOS KaihongOS 项目的所有版本变更，遵循 Keep a Changelog 规范。

## [{version}] - {date}

### Added
- {change-description}

### Changed
- {change-description}

### Fixed
- {change-description}

### Removed
- {change-description}
`

const STATUS_REPORT_TEMPLATE: string = `# 项目状态报告 - {year}年第{week}周

## 整体进度
- 项目整体进度: {progress}%
- 当前里程碑: {milestone-name} ({milestone-status})

## 里程碑状态

| 里程碑 | 计划完成日期 | 实际完成日期 | 状态 |
|--------|-------------|-------------|------|
| {name} | {planned-date} | {actual-date} | {status} |

## 风险项

| 风险描述 | 风险等级 | 影响范围 |
|---------|---------|---------|
| {description} | {level} | {impact} |

## 阻塞项

| 阻塞描述 | 解决人 | 期望解决时间 |
|---------|--------|------------|
| {description} | {resolver} | {expected-date} |

## 本周完成
- {completed-item}

## 下周计划
- {planned-item}
`

const MEETING_TEMPLATE: string = `# 会议纪要 - {topic}

## 会议信息
- 主题: {topic}
- 时间: {time}
- 参与人员: {participants}

## 讨论内容
{discussion-content}

## 决策结果
{decisions}

## 行动项

| 行动项 | 负责人 | 截止日期 | 状态 |
|--------|--------|---------|------|
| {description} | {assignee} | {due-date} | {status} |
`

const ADR_TEMPLATE: string = `# ADR-{number}: {title}

## 状态
{status}

## 访问级别
{access-level}

## 上下文
{context}

## 决策
{decision}

## 后果
{consequences}

## 关联 SDD 文档
- {doc-path} — 章节: {section}
`

const ADR_INDEX_TEMPLATE: string = `# ADR 索引

| 编号 | 标题 | 状态 | 创建日期 | 接受日期 |
|------|------|------|---------|---------|
| ADR-{number} | {title} | {status} | {created-date} | {accepted-date} |
`

class DocTemplateManagerImpl {
  private static countPlaceholders(template: string): number {
    const regex = /\{[a-zA-Z0-9_-]+\}/g
    const matches = template.match(regex)
    return matches ? matches.length : 0
  }

  getTemplate(docType: DocType): string {
    switch (docType) {
      case DocType.DEV_PLAN:
        return DEV_PLAN_TEMPLATE
      case DocType.DEV_LOG:
        return DEV_LOG_TEMPLATE
      case DocType.CHANGELOG:
        return CHANGELOG_TEMPLATE
      case DocType.STATUS_REPORT:
        return STATUS_REPORT_TEMPLATE
      case DocType.MEETING:
        return MEETING_TEMPLATE
      case DocType.ADR:
        return ADR_TEMPLATE
      default:
        throw new AppError(DocErrorCodes.DOC_TPL_001, `Unknown doc type: ${docType}`)
    }
  }

  getADRIndexTemplate(): string {
    return ADR_INDEX_TEMPLATE
  }

  createFromTemplate(docType: DocType, params: TemplateParams): string {
    const template = this.getTemplate(docType)
    return this.replacePlaceholders(template, params)
  }

  replacePlaceholders(template: string, params: TemplateParams): string {
    let result = template
    const regex = /\{([a-zA-Z0-9_-]+)\}/g
    const keys: string[] = []
    let m: RegExpExecArray | null = regex.exec(template)
    while (m !== null) {
      if (!keys.includes(m[1])) {
        keys.push(m[1])
      }
      m = regex.exec(template)
    }
    for (const key of keys) {
      const value = params[key]
      if (value !== undefined && value !== null) {
        let strValue: string
        if (Array.isArray(value)) {
          strValue = (value as string[]).join(', ')
        } else {
          strValue = String(value)
        }
        result = result.split(`{${key}}`).join(strValue)
      }
    }
    return result
  }

  listTemplates(): TemplateInfo[] {
    const infos: TemplateInfo[] = [
      {
        docType: DocType.DEV_PLAN,
        templateName: 'development-plan',
        description: '开发计划模板：里程碑总览表 + 任务分解表 + 时间线 + 资源分配表',
        placeholderCount: DocTemplateManagerImpl.countPlaceholders(DEV_PLAN_TEMPLATE)
      },
      {
        docType: DocType.DEV_LOG,
        templateName: 'dev-log',
        description: '开发日志模板：按日期章节 + 工作内容 + 问题与风险 + 决策与结论 + 关联任务',
        placeholderCount: DocTemplateManagerImpl.countPlaceholders(DEV_LOG_TEMPLATE)
      },
      {
        docType: DocType.CHANGELOG,
        templateName: 'CHANGELOG',
        description: '变更日志模板：遵循 Keep a Changelog 规范，Added/Changed/Fixed/Removed 四类',
        placeholderCount: DocTemplateManagerImpl.countPlaceholders(CHANGELOG_TEMPLATE)
      },
      {
        docType: DocType.STATUS_REPORT,
        templateName: 'status-report',
        description: '项目状态报告模板：整体进度 + 里程碑状态 + 风险项 + 阻塞项 + 本周完成 + 下周计划',
        placeholderCount: DocTemplateManagerImpl.countPlaceholders(STATUS_REPORT_TEMPLATE)
      },
      {
        docType: DocType.MEETING,
        templateName: 'meeting-minutes',
        description: '会议纪要模板：会议信息 + 讨论内容 + 决策结果 + 行动项表',
        placeholderCount: DocTemplateManagerImpl.countPlaceholders(MEETING_TEMPLATE)
      },
      {
        docType: DocType.ADR,
        templateName: 'adr',
        description: 'ADR 模板：状态 + 上下文 + 决策 + 后果 + 关联 SDD 文档',
        placeholderCount: DocTemplateManagerImpl.countPlaceholders(ADR_TEMPLATE)
      }
    ]
    return infos
  }
}

export const DocTemplateManager = new DocTemplateManagerImpl()