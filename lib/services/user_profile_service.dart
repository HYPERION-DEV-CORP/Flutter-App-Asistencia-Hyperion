// lib/services/user_profile_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

typedef JsonMap = Map<String, dynamic>;

class UserProfileService {
  static Future<JsonMap> getProfileSignature(String userId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/users/signature?userId=$userId'),
      headers: {'Content-Type': 'application/json'},
    );
    return _decode(res);
  }

  static Future<JsonMap> updateProfileSignature({
    required String userId,
    required String signatureBase64,
  }) async {
    final res = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/users/signature'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'signatureBase64': signatureBase64,
      }),
    );
    return _decode(res);
  }

  static Future<JsonMap> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/users/password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    return _decode(res);
  }

  static Future<JsonMap> forgotPassword(String identifier) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifier': identifier}),
    );
    return _decode(res);
  }

  static Future<JsonMap> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier,
        'code': code,
        'newPassword': newPassword,
      }),
    );
    return _decode(res);
  }

  static Future<JsonMap> getMonthlyTareo({
    required String userId,
    required int year,
    required int month,
  }) async {
    final res = await http.get(
      Uri.parse(
        '${ApiConfig.baseUrl}/reports/attendance-sheet?userId=$userId&year=$year&month=$month',
      ),
      headers: {'Content-Type': 'application/json'},
    );
    return _decode(res);
  }

  static Future<JsonMap> signMonthlyClosing({
    required String userId,
    required int year,
    required int month,
    required String closingSignatureBase64,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/reports/attendance-sheet/sign-closing'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'year': year,
        'month': month,
        'closingSignature': closingSignatureBase64,
      }),
    );
    return _decode(res);
  }

  static JsonMap _decode(http.Response res) {
    final data = res.body.isNotEmpty ? jsonDecode(res.body) as JsonMap : <String, dynamic>{};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    throw Exception(data['error'] ?? 'Error de servidor (${res.statusCode})');
  }
}