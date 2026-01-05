import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class CommentService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> getComments(int roomId, {int page = 1}) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/comments?page=$page&limit=20',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/comments?page=$page&limit=20',
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
      print('Error fetching comments: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> createComment(
    int roomId,
    String content, {
    int? parentId,
    int? replyToUserId,
  }) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/comments',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/comments',
);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'content': content,
          if (parentId != null) 'parent_id': parentId,
          if (replyToUserId != null) 'reply_to_user_id': replyToUserId,
        }),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error creating comment: $e');
      return null;
    }
  }

  Future<bool> deleteComment(int commentId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/comments/$commentId',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/comments/$commentId',
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
      print('Error deleting comment: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> toggleCommentLike(int commentId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/comments/$commentId/like',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/comments/$commentId/like',
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
      return null;
    } catch (e) {
      print('Error toggling comment like: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getReplies(
    int commentId, {
    int page = 1,
  }) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/comments/$commentId/replies?page=$page&limit=20',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/comments/$commentId/replies?page=$page&limit=20',
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
      print('Error fetching replies: $e');
      return null;
    }
  }
}
