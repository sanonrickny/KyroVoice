export type SectionId =
  | 'general'
  | 'hotkey'
  | 'models'
  | 'permissions'
  | 'advanced'
  | 'about'

export type DictationMode = 'normal' | 'email' | 'code'
export type HotkeyMode = 'pushToTalk' | 'toggle'
export type ModelVariant = 'baseEN' | 'smallEN'
export type InjectionStrategy = 'pasteboard' | 'accessibility' | 'auto'
export type PermissionStatus = 'granted' | 'notGranted' | 'unknown'

export interface AppSettings {
  mode: DictationMode
  hotkeyMode: HotkeyMode
  cloudCleanup: boolean
  model: ModelVariant
  injection: InjectionStrategy
  permissions: {
    microphone: PermissionStatus
    accessibility: PermissionStatus
    inputMonitoring: PermissionStatus
  }
  hotkey: {
    keys: string[] // e.g. ['⌘', '⇧', 'Space']
  }
}
