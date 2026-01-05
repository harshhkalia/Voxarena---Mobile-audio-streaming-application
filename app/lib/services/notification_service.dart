import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class NotificationService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> getNotifications({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/notifications?page=$page&limit=$limit',
      );

      final response = await http.get(
        url,
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
      print('Error fetching notifications: $e');
      return null;
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return 0;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/notifications/unread-count',
      );

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['unread_count'] ?? 0;
      }
      return 0;
    } catch (e) {
      print('Error fetching unread count: $e');
      return 0;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return false;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/notifications/mark-all-read',
      );

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error marking notifications as read: $e');
      return false;
    }
  }

  Future<bool> deleteNotification(int notificationId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return false;

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/notifications/$notificationId',
      );

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error deleting notification: $e');
      return false;
    }
  }
}
