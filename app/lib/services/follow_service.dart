import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class FollowService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> toggleFollow(int userId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) return null;

      // final response = await http.post(
      //   Uri.parse('http://$serverIP:$serverPort/api/v1/users/$userId/follow'),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'Authorization': 'Bearer $token',
      //   },
      // );

       final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/users/$userId/follow',
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
      print('Error toggling follow: $e');
      return null;
    }
  }

  Future<bool> checkFollowStatus(int userId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) return false;

      // final response = await http.get(
      //   Uri.parse(
      //     'http://$serverIP:$serverPort/api/v1/users/$userId/follow-status',
      //   ),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'Authorization': 'Bearer $token',
      //   },
      // );

      final response = await http.get(
  Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/users/$userId/follow-status',
  ),
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  },
);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['is_following'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error checking follow status: $e');
      return false;
    }
  }

 Future<Map<String, dynamic>?> getFollowers(
  int userId, {
  int page = 1,
  int limit = 20,
}) async {
  //  final serverIP = dotenv.get('SERVER_IP');
  //  final serverPort = dotenv.get('SERVER_PORT');

  final token = await _storage.read(key: 'jwt_token');

  // final response = await http.get(
  //   Uri.parse(
  //     'http://$serverIP:$serverPort/api/v1/users/$userId/followers?page=$page&limit=$limit',
  //   ),
  //   headers: {
  //     'Authorization': 'Bearer $token',
  //   },
  // );

  final response = await http.get(
  Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/users/$userId/followers?page=$page&limit=$limit',
  ),
  headers: {
    'Authorization': 'Bearer $token',
  },
);

  if (response.statusCode == 200) {
    return json.decode(response.body);
  }

  return null;
}


 Future<Map<String, dynamic>?> getFollowing(
  int userId, {
  int page = 1,
  int limit = 20,
}) async {
  // final serverIP = dotenv.get('SERVER_IP');
  // final serverPort = dotenv.get('SERVER_PORT');
  final token = await _storage.read(key: 'jwt_token');

  if (token == null) return null;

  // final response = await http.get(
  //   Uri.parse(
  //     'http://$serverIP:$serverPort/api/v1/users/$userId/following?page=$page&limit=$limit',
  //   ),
  //   headers: {
  //     'Authorization': 'Bearer $token',
  //   },
  // );

  final response = await http.get(
  Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/users/$userId/following?page=$page&limit=$limit',
  ),
  headers: {
    'Authorization': 'Bearer $token',
  },
);

  if (response.statusCode == 200) {
    return json.decode(response.body);
  }

  return null;
}

Future<Map<String, dynamic>?> getFollowingRooms({
  int page = 1,
  int limit = 20,
}) async {
  // final serverIP = dotenv.get('SERVER_IP');
  // final serverPort = dotenv.get('SERVER_PORT');
  final token = await _storage.read(key: 'jwt_token');

  if (token == null) return null;

  // final response = await http.get(
  //   Uri.parse(
  //     'http://$serverIP:$serverPort/api/v1/following/rooms?page=$page&limit=$limit',
  //   ),
  //   headers: {
  //     'Authorization': 'Bearer $token',
  //   },
  // );

  final response = await http.get(
  Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/following/rooms?page=$page&limit=$limit',
  ),
  headers: {
    'Authorization': 'Bearer $token',
  },
);

  if (response.statusCode == 200) {
    return json.decode(response.body);
  }

  return null;
}

Future<Map<String, dynamic>?> removeFollower(int userId) async {
  // final serverIP = dotenv.get('SERVER_IP');
  // final serverPort = dotenv.get('SERVER_PORT');
  final token = await _storage.read(key: 'jwt_token');

  // final response = await http.delete(
  //   Uri.parse(
  //     'http://$serverIP:$serverPort/api/v1/users/$userId/remove-follower',
  //   ),
  //   headers: {
  //     'Authorization': 'Bearer $token',
  //     'Content-Type': 'application/json',
  //   },
  // );

  final response = await http.delete(
  Uri.parse(
    '${ApiConfig.baseUrl}/api/v1/users/$userId/remove-follower',
  ),
  headers: {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  },
);

  if (response.statusCode == 200) {
    return json.decode(response.body);
  }

  return null;
}
}
