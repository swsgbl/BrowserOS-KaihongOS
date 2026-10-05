import { ProblemStatus, ADRStatus, DocType } from '../enums/DocEnums'

export type TemplateParams = Record<string, Object>

export interface PathParams {
  year?: number
  month?: number
  week?: number
  date?: string
  version?: string
  number?: number
}

export interface MilestoneData {
  name: string
  description: string
  deliverables: string
  plannedDate: string
}

export interface TaskData {
  sddTaskRef: string
  name: string
  assignee: string
  estimatedDays: number
  plannedStart: string
  plannedEnd: string
}

export interface DevLogEntryData {
  date: string
  author: string
  workSummary: string
  decisions: string
  relatedTaskId: string
}

export interface ADRData {
  title: string
  context: string
  decision: string
  consequences: string
  sddLinks: SDDLink[]
}

export interface ActionItemData {
  description: string
  assignee: string
  dueDate: string
  relatedTaskId?: string
}

export interface MeetingMinutesData {
  topic: string
  time: string
  participants: string[]
  discussionContent: string
  decisions: string
  actionItems: ActionItemData[]
}

export interface PrerequisiteDetail {
  name: string
  met: boolean
  description: string
}

export interface PrerequisiteCheckResult {
  allMet: boolean
  unmetItems: string[]
  details: PrerequisiteDetail[]
}

export interface TimelineItem {
  id: string
  name: string
  type: 'milestone' | 'task'
  plannedStart: string
  plannedEnd: string
  status: string
  hasConflict: boolean
}

export interface ResourceAllocation {
  assignee: string
  tasks: string[]
  totalDays: number
  availableDays: number
  isOverloaded: boolean
}

export interface MilestoneProgressItem {
  milestoneId: string
  name: string
  progress: number
  plannedDeliverables: number
  completedDeliverables: number
}

export interface ProgressData {
  overallProgress: number
  totalTasks: number
  completedTasks: number
  milestoneProgress: MilestoneProgressItem[]
}

export interface MissingDataSource {
  sourceName: string
  filePath: string
  impact: string
}

export interface DataConflict {
  source1: string
  source2: string
  description: string
  value1: string
  value2: string
}

export interface ADRConflict {
  adrId: string
  sddDocPath: string
  section: string
  description: string
}

export interface TemplateInfo {
  docType: DocType
  templateName: string
  description: string
  placeholderCount: number
}

export interface DocConfig {
  archiveRetentionDays: number
  namingConvention: string
  templateVersion: string
}

export interface UpdateResult {
  problemId: string
  status: ProblemStatus
}

export interface ADRUpdateResult {
  adrId: string
  status: ADRStatus
}