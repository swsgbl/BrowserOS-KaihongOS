interface CookieEntryJSON {
  name: string
  value: string
  domain: string
  path: string
  expires: number
  secure: boolean
  httpOnly: boolean
}

export class CookieEntry {
  name: string = ''
  value: string = ''
  domain: string = ''
  path: string = '/'
  expires: number = 0
  secure: boolean = false
  httpOnly: boolean = false

  constructor(name: string, value: string, domain: string) {
    this.name = name
    this.value = value
    this.domain = domain
  }

  toJSON(): CookieEntryJSON {
    const result: CookieEntryJSON = {
      name: this.name,
      value: this.value,
      domain: this.domain,
      path: this.path,
      expires: this.expires,
      secure: this.secure,
      httpOnly: this.httpOnly
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): CookieEntry {
    const entry = new CookieEntry(
      json['name'] as string,
      json['value'] as string,
      json['domain'] as string
    )
    entry.path = json['path'] as string
    entry.expires = json['expires'] as number
    entry.secure = json['secure'] as boolean
    entry.httpOnly = json['httpOnly'] as boolean
    return entry
  }
}

interface LoginStateDataJSON {
  domain: string
  cookies: CookieEntryJSON[]
  localStorage: Record<string, string>
  sessionStorage: Record<string, string>
  importTime: number
  isEncrypted: boolean
  expireTime: number
}

export class LoginStateData {
  domain: string = ''
  cookies: CookieEntry[] = []
  localStorage: Record<string, string> = {}
  sessionStorage: Record<string, string> = {}
  importTime: number = 0
  isEncrypted: boolean = false
  expireTime: number = 0

  constructor(domain: string) {
    this.domain = domain
    this.importTime = Date.now()
  }

  addCookie(cookie: CookieEntry): void {
    this.cookies.push(cookie)
  }

  setLocalStorageItem(key: string, value: string): void {
    this.localStorage[key] = value
  }

  setSessionStorageItem(key: string, value: string): void {
    this.sessionStorage[key] = value
  }

  toJSON(): LoginStateDataJSON {
    const result: LoginStateDataJSON = {
      domain: this.domain,
      cookies: this.cookies.map(c => c.toJSON()),
      localStorage: this.localStorage,
      sessionStorage: this.sessionStorage,
      importTime: this.importTime,
      isEncrypted: this.isEncrypted,
      expireTime: this.expireTime
    }
    return result
  }

  static fromJSON(json: Record<string, Object>): LoginStateData {
    const data = new LoginStateData(json['domain'] as string)
    data.cookies = (json['cookies'] as Record<string, Object>[]).map(c => CookieEntry.fromJSON(c))
    data.localStorage = json['localStorage'] as Record<string, string>
    data.sessionStorage = json['sessionStorage'] as Record<string, string>
    data.importTime = json['importTime'] as number
    data.isEncrypted = json['isEncrypted'] as boolean
    data.expireTime = json['expireTime'] as number
    return data
  }
}