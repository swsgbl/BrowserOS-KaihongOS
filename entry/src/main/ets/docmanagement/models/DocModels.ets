import { MilestoneStatus, TaskStatus, ProblemStatus, ChangeType, RiskLevel, ActionItemStatus, ADRStatus, AccessLevel } from '../enums/DocEnums'

export interface Task {
  id: string
  milestoneId: string
  sddTaskRef: string
  name: string
  assignee: string
  estimatedDays: number
  status: TaskStatus
  plannedStart: string
  plannedEnd: string
}

export interface Milestone {
  id: string
  name: string
  description: string
  deliverables: string
  plannedDate: string
  actualDate: string
  status: MilestoneStatus
  tasks: Task[]
}

export interface Problem {
  id: string
  description: string
  status: ProblemStatus
  solution: string
  foundDate: string
  resolvedDate: string
}

export interface DevLogEntry {
  id: string
  date: string
  author: string
  workSummary: string
  problems: Problem[]
  decisions: string
  relatedTaskId: string
}

export interface ChangeEntry {
  version: string
  type: ChangeType
  description: string
  commitRange: string
  hapFileName: string
  releaseDate: string
}

export interface MilestoneStatusItem {
  milestoneId: string
  name: string
  plannedDate: string
  actualDate: string
  status: MilestoneStatus
  isDelayed: boolean
  delayDays: number
}

export interface RiskItem {
  id: string
  description: string
  level: RiskLevel
  impact: string
  source: string
}

export interface BlockerItem {
  id: string
  description: string
  resolver: string
  expectedResolveDate: string
}

export interface StatusReport {
  reportDate: string
  weekNumber: number
  overallProgress: number
  milestoneStatuses: MilestoneStatusItem[]
  risks: RiskItem[]
  blockers: BlockerItem[]
  completedThisWeek: string[]
  plannedNextWeek: string[]
}

export interface ActionItem {
  id: string
  description: string
  assignee: string
  dueDate: string
  status: ActionItemStatus
  relatedTaskId: string
}

export interface MeetingMinutes {
  id: string
  topic: string
  time: string
  participants: string[]
  discussionContent: string
  decisions: string
  actionItems: ActionItem[]
}

export interface SDDLink {
  docPath: string
  section: string
}

export interface ADR {
  id: string
  number: string
  title: string
  status: ADRStatus
  accessLevel: AccessLevel
  context: string
  decision: string
  consequences: string
  sddLinks: SDDLink[]
  supersededBy: string
  supersedes: string
  createdDate: string
  acceptedDate: string
}