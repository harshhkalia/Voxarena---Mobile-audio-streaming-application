import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class RoomReportService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> reportRoom({
    required int roomId,
    required String reason,
    String? details,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) return null;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/rooms/$roomId/report'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'reason': reason,
          if (details != null) 'details': details,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 409) {
        return json.decode(response.body);
      } else if (response.statusCode == 400) {
        return json.decode(response.body);
      }

      return null;
    } catch (e) {
      print('Error reporting room: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkReportStatus(int roomId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/rooms/$roomId/report-status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }

      return null;
    } catch (e) {
      print('Error checking report status: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getRoomReports(
    int roomId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) return null;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/reports?page=$page&limit=$limit',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }

      return null;
    } catch (e) {
      print('Error fetching room reports: $e');
      return null;
    }
  }

  Future<bool> hasReportedRoom(int roomId) async {
    final status = await checkReportStatus(roomId);
    return status?['has_reported'] ?? false;
  }
}
