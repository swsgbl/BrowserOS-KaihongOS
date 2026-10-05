import { EventBus, EventBusEvents } from './EventBus'
import { ErrorCodes } from '../common/ErrorCodes'

export class AppError extends Error {
  code: string = ''
  module: string = ''
  context: Object = ''

  constructor(code: string, message?: string, context?: Object) {
    super(message || ErrorCodes.getMessage(code))
    this.code = code
    this.module = code.split('-')[0]
    if (context) {
      this.context = context
    }
  }
}

interface ErrorEventData {
  code: string
  message: string
  module: string
  context: Object
  timestamp: number
}

class ErrorHandlerImpl {
  handle(error: Error | AppError, context?: Object): void {
    const appError = error instanceof AppError ? error : new AppError(ErrorCodes.SYS_001, error.message)

    console.error(`[${appError.module}] ${appError.code}: ${appError.message}`)
    if (context) {
      console.error(`Context: ${JSON.stringify(context)}`)
    }

    const errorData: ErrorEventData = {
      code: appError.code,
      message: appError.message,
      module: appError.module,
      context: appError.context,
      timestamp: Date.now()
    }
    EventBus.emit(EventBusEvents.ERROR_OCCURRED, errorData)
  }

  wrap<T>(fn: () => T, context?: Object): T | null {
    try {
      return fn()
    } catch (e) {
      this.handle(e as Error, context)
      return null
    }
  }

  async wrapAsync<T>(fn: () => Promise<T>, context?: Object): Promise<T | null> {
    try {
      return await fn()
    } catch (e) {
      this.handle(e as Error, context)
      return null
    }
  }
}

export const ErrorHandler = new ErrorHandlerImpl()