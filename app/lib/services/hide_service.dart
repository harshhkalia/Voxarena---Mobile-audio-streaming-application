import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class HideService {
  static final HideService _instance = HideService._internal();
  factory HideService() => _instance;
  HideService._internal();

  final _storage = const FlutterSecureStorage();
  final Map<int, bool> _hideStatusCache = {};

  Future<Map<String, dynamic>?> toggleHideUser(int userId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) {
        print('❌ No auth token found');
        return null;
      }

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/users/$userId/hide',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/users/$userId/hide',
);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['is_hidden'] != null) {
          _hideStatusCache[userId] = data['is_hidden'];
        }
        
        return data;
      } else {
        print('❌ Failed to toggle hide: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error toggling hide user: $e');
    }
    return null;
  }

  Future<bool> checkHideStatus(int userId) async {
    if (_hideStatusCache.containsKey(userId)) {
      return _hideStatusCache[userId]!;
    }

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) {
        print('❌ No auth token found');
        return false;
      }

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/users/$userId/hide-status',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/users/$userId/hide-status',
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
        final isHidden = data['is_hidden'] ?? false;
        
        _hideStatusCache[userId] = isHidden;
        
        return isHidden;
      } else {
        print('❌ Failed to check hide status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error checking hide status: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> getHiddenUsers({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) {
        print('❌ No auth token found');
        return null;
      }

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/hidden-users?page=$page&limit=$limit',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/hidden-users?page=$page&limit=$limit',
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
      } else {
        print('❌ Failed to get hidden users: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error getting hidden users: $e');
    }
    return null;
  }

  void clearCache(int userId) {
    _hideStatusCache.remove(userId);
  }

  void clearAllCache() {
    _hideStatusCache.clear();
  }
}