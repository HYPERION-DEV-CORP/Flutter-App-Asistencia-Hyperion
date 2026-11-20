// lib/services/iso_attendance_service.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class IsoAttendanceService {
  static const _storage = FlutterSecureStorage();
  static const String _configStorageKey = 'company_lunch_config';

  static Map<String, dynamic> get defaultCompanyConfig => {
    'lunchWindowStart': '13:00',
    'lunchWindowEnd': '13:30',
    'lunchDurationMinutes': 60,
    'lunchDays': [1, 2, 3, 4, 5],
    'saturdayWorkHours': 4.5,
  };

  static Future<void> saveCompanyConfig(Map<String, dynamic>? config) async {
    if (config == null) return;
    await _storage.write(key: _configStorageKey, value: jsonEncode(config));
  }

  static Future<Map<String, dynamic>> getSavedCompanyConfig() async {
    try {
      final raw = await _storage.read(key: _configStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return {...defaultCompanyConfig, ...decoded};
      }
    } catch (_) {}
    return defaultCompanyConfig;
  }

  static Future<Map<String, dynamic>> getTodayStatus(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/attendance/today?userId=$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      final isJson = response.headers['content-type']?.contains('application/json') ?? false;
      if (isJson && response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['companyConfig'] is Map<String, dynamic>) {
          await saveCompanyConfig(decoded['companyConfig']);
        }
        return {'success': true, 'data': decoded};
      }
      return {'success': false, 'data': null};
    } catch (e) {
      return {'success': false, 'data': null};
    }
  }

  static Future<Map<String, dynamic>> postAttendance({
    required String userId,
    required String type,
    required String actionType,
    required double lat,
    required double lng,
    String? signature,
    String? qrContent,
    String? biometricToken,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/attendance');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'type': type,
          'actionType': actionType,
          'lat': lat.toString(),
          'lng': lng.toString(),
          'signature': signature,
          'qrContent': qrContent,
          'biometricToken': biometricToken,
        }),
      );

      final isJson = response.headers['content-type']?.contains('application/json') ?? false;

      if (isJson) {
        final data = jsonDecode(response.body);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return {
            'success': true,
            'message': data['message'] ?? 'Marcación registrada con éxito',
            'data': data,
          };
        } else {
          return {
            'success': false,
            'message': data['error'] ?? 'Error en la solicitud',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Respuesta no válida del servidor (${response.statusCode}). Verifique la conexión con Next.js.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error de conexión o red: ${e.toString().replaceAll('Exception: ', '')}',
      };
    }
  }
}