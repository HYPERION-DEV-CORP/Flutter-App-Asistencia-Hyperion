// lib/config/api_config.dart
class ApiConfig {
  // Cambia a 'false' únicamente cuando vayas a generar el APK final de Producción
  static const bool isStaging = true;

  static const String _prodUrl =
      'https://frontend-backend-asistencia-hyperion.onrender.com/api/v1';
  static const String _stagingUrl =
      'https://frontend-backend-asistencia-hyperion-uvn7.onrender.com/api/v1';

  static String get baseUrl => isStaging ? _stagingUrl : _prodUrl;
}