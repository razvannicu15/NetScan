import 'dart:ui' show PlatformDispatcher;

/// Current UI language: 'ro' or 'en'. Set from settings ('system' resolves
/// to Romanian on Romanian devices, English everywhere else).
String _lang = 'ro';

String get currentLang => _lang;
bool get isEn => _lang == 'en';

void setLanguage(String pref) {
  if (pref == 'ro' || pref == 'en') {
    _lang = pref;
  } else {
    final code = PlatformDispatcher.instance.locale.languageCode;
    _lang = code == 'ro' ? 'ro' : 'en';
  }
}

/// Inline translation: tr('Romanian text', 'English text').
String tr(String ro, String en) => _lang == 'en' ? en : ro;
