import Cocoa

/// 原生菜单在 Dart 启动前即存在，先读取同一份偏好，再由语言协议同步更新。
enum NativeStrings {
  private(set) static var languageCode = initialLanguage()

  static func resolve(savedLanguage: String?, preferredLanguages: [String]) -> String {
    if savedLanguage == "en" || savedLanguage == "zh" { return savedLanguage! }
    return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh" : "en"
  }

  private static func initialLanguage() -> String {
    let json = UserDefaults.standard.string(forKey: "fruler.state.v1")
    let data = json?.data(using: .utf8)
    let state = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    return resolve(savedLanguage: state?["language"] as? String,
      preferredLanguages: Locale.preferredLanguages)
  }

  static func configure(_ languageCode: String) {
    self.languageCode = resolve(savedLanguage: languageCode, preferredLanguages: Locale.preferredLanguages)
  }

  static func bundle(for languageCode: String) -> Bundle {
    let name = languageCode == "zh" ? "zh-Hans" : "en"
    guard let path = Bundle.main.path(forResource: name, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return .main }
    return bundle
  }

  static func text(_ key: String, _ arguments: CVarArg...) -> String {
    let value = bundle(for: languageCode).localizedString(forKey: key, value: key, table: "Localizable")
    if arguments.isEmpty { return value }
    return String(format: value, locale: Locale(identifier: languageCode), arguments: arguments)
  }

  static func localizeMenu(_ menu: NSMenu?) {
    for item in menu?.items ?? [] {
      if let identifier = item.identifier?.rawValue, identifier.hasPrefix("l10n.") {
        item.title = text(String(identifier.dropFirst(5)))
        item.submenu?.title = item.title
      }
      localizeMenu(item.submenu)
    }
  }
}
