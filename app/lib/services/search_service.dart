import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/user_search_result.dart';
import '../models/room.dart';
import '../config/api_config.dart';

class SearchService {
  final _storage = const FlutterSecureStorage();

  Future<SearchResult> search(String query, {int limit = 20, String? type}) async {
    if (query.trim().isEmpty) {
      throw ArgumentError('Search query cannot be empty');
    }

    if (query.length < 2) {
      throw ArgumentError('Search query must be at least 2 characters');
    }

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final uri = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/search',
      // ).replace(queryParameters: {
      //   'q': query,
      //   'limit': limit.toString(),
      //   if (type != null) 'type': type,
      // });

      final uri = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/search',
).replace(queryParameters: {
  'q': query,
  'limit': limit.toString(),
  if (type != null) 'type': type,
});

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Search request timed out');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        final users = (data['users'] as List<dynamic>?)
                ?.map((json) => UserSearchResult.fromJson(json as Map<String, dynamic>))
                .toList() ??
            [];

        final rooms = (data['rooms'] as List<dynamic>?)
                ?.map((json) => Room.fromSearchJson(json as Map<String, dynamic>))
                .toList() ??
            [];

        return SearchResult(users: users, rooms: rooms);
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw SearchException(error['message'] ?? 'Invalid search query');
      } else {
        throw SearchException('Search failed with status: ${response.statusCode}');
      }
    } on TimeoutException {
      throw SearchException('Search request timed out. Please try again.');
    } catch (e) {
      if (e is SearchException) rethrow;
      throw SearchException('Failed to perform search: $e');
    }
  }
}

class SearchResult {
  final List<UserSearchResult> users;
  final List<Room> rooms;

  SearchResult({
    required this.users,
    required this.rooms,
  });

  bool get isEmpty => users.isEmpty && rooms.isEmpty;
}

class SearchException implements Exception {
  final String message;
  SearchException(this.message);

  @override
  String toString() => message;
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}