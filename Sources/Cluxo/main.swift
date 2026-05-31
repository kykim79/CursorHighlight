import AppKit

// 사용자가 메뉴/환경설정에서 선택한 UI 언어를 NSApplication 생성 전에 override.
// .system(또는 키 없음)이면 AppleLanguages를 비워 macOS 시스템 언어 fallback.
if let raw = UserDefaults.standard.string(forKey: "preferredLanguage"),
   let lang = CursorSettings.PreferredLanguage(rawValue: raw),
   let code = lang.languageCode {
    UserDefaults.standard.set([code], forKey: "AppleLanguages")
} else {
    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApp.run()
}
