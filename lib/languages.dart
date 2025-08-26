import 'package:flutter/material.dart';

const supportedLanguageNames = {
  'it': 'Italiano',
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español'
};

List<Locale> getAvailableLocales() {
  return supportedLanguageNames.keys.map((code) => Locale(code)).toList();
}

String getLanguageName(String code) {
  return supportedLanguageNames[code] ?? code;
}

List<DropdownMenuItem<String>> languageDropDownMenuItems(BuildContext context) {
  List<String> supportedLanguages = supportedLanguageNames.keys.toList();

  return supportedLanguages.map((language) {
    return DropdownMenuItem(
      value: language,
      child: Text(getLanguageName(language)),
    );
  }).toList();
}