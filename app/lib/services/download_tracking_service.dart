import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class DownloadTrackingService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> trackDownload({
    required int roomId,
    String? fileName,
    int? fileSize,
    String? downloadPath,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/downloads');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'room_id': roomId,
          if (fileName != null) 'file_name': fileName,
          if (fileSize != null) 'file_size': fileSize,
          if (downloadPath != null) 'download_path': downloadPath,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('Error tracking download: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getDownloadHistory({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/my-downloads?page=$page&limit=$limit',
      );

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('Error fetching download history: $e');
      return null;
    }
  }

  Future<bool> deleteDownloadHistory(int downloadId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return false;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/download-history/$downloadId',
      );

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting download history: $e');
      return false;
    }
  }

  Future<bool> clearAllDownloadHistory() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return false;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/download-history',
      );

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error clearing download history: $e');
      return false;
    }
  }
}