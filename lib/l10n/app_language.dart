import 'dart:ui';

enum AppLanguage {
  system,
  zh,
  en;

  static AppLanguage parse(Object? value) =>
      values.where((language) => language.name == value).firstOrNull ?? system;

  Locale resolve(Locale systemLocale) => switch (this) {
    zh => const Locale('zh'),
    en => const Locale('en'),
    system => Locale(
      systemLocale.languageCode.toLowerCase().startsWith('zh') ? 'zh' : 'en',
    ),
  };
}
