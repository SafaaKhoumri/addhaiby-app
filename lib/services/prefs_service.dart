import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _keyDarkMode = 'dark_mode';
  static const _keyLanguage = 'language';

  /// Charge les préférences sauvegardées
  static Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isDarkMode': prefs.getBool(_keyDarkMode) ?? false,
      'language': prefs.getString(_keyLanguage) ?? 'Français',
    };
  }

  /// Sauvegarde le mode nuit/jour
  static Future<void> saveDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
  }

  /// Sauvegarde la langue choisie
  static Future<void> saveLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, value);
  }
}