export enum DocType {
  DEV_PLAN = 'dev-plan',
  DEV_LOG = 'dev-log',
  CHANGELOG = 'changelog',
  STATUS_REPORT = 'status-report',
  MEETING = 'meeting',
  ADR = 'adr'
}

export enum MilestoneStatus {
  PLANNED = 'PLANNED',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED',
  DELAYED = 'DELAYED',
  CANCELLED = 'CANCELLED'
}

export enum TaskStatus {
  NOT_STARTED = 'NOT_STARTED',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED',
  BLOCKED = 'BLOCKED'
}

export enum ProblemStatus {
  NEW_FOUND = 'NEW_FOUND',
  IN_PROGRESS = 'IN_PROGRESS',
  RESOLVED = 'RESOLVED',
  CLOSED = 'CLOSED'
}

export enum ChangeType {
  ADDED = 'Added',
  CHANGED = 'Changed',
  FIXED = 'Fixed',
  REMOVED = 'Removed'
}

export enum RiskLevel {
  LOW = 'LOW',
  MEDIUM = 'MEDIUM',
  HIGH = 'HIGH'
}

export enum ActionItemStatus {
  PENDING = 'PENDING',
  IN_PROGRESS = 'IN_PROGRESS',
  COMPLETED = 'COMPLETED'
}

export enum ADRStatus {
  PROPOSED = 'PROPOSED',
  ACCEPTED = 'ACCEPTED',
  DEPRECATED = 'DEPRECATED',
  SUPERSEDED = 'SUPERSEDED'
}
export enum AccessLevel {
  PUBLIC = 'PUBLIC',
  INTERNAL = 'INTERNAL',
  CONFIDENTIAL = 'CONFIDENTIAL'
}