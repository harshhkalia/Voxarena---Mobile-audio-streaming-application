import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class LikeService {
  static final LikeService _instance = LikeService._internal();
  factory LikeService() => _instance;
  LikeService._internal();

  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> toggleLike(int roomId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/like',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/like',
);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('❌ Error toggling like: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> checkLikeStatus(int roomId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/like-status',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/like-status',
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
    } catch (e) {
      print('❌ Error checking like status: $e');
    }
    return null;
  }
}
