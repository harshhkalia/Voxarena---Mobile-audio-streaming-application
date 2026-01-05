import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/room.dart';
import '../config/api_config.dart';

class QueueService {
  final _storage = const FlutterSecureStorage();

  Future<List<Room>> fetchSmartQueue({
    required int currentRoomId,
    String? topic,
    int limit = 20,
  }) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) {
        throw Exception('Not authenticated');
      }

      // final response = await http.post(
      //   Uri.parse('http://$serverIP:$serverPort/api/v1/queue/smart'),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'Authorization': 'Bearer $token',
      //   },
      //   body: json.encode({
      //     'current_room_id': currentRoomId,
      //     if (topic != null) 'topic': topic,
      //     'limit': limit,
      //   }),
      // );

      final response = await http.post(
  Uri.parse('${ApiConfig.baseUrl}/api/v1/queue/smart'),
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  },
  body: json.encode({
    'current_room_id': currentRoomId,
    if (topic != null) 'topic': topic,
    'limit': limit,
  }),
);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final queueList = data['queue'] as List? ?? [];
        return queueList
            .map((json) => Room.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to fetch queue: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching smart queue: $e');
      return [];
    }
  }

  Future<List<Room>> fetchQueueFromSearch({
    required int currentRoomId,
    required String query,
  }) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null) {
        throw Exception('Not authenticated');
      }

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/queue/search?current_room_id=$currentRoomId&query=${Uri.encodeComponent(query)}',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/queue/search'
  '?current_room_id=$currentRoomId&query=${Uri.encodeComponent(query)}',
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
        final queueList = data['queue'] as List? ?? [];
        return queueList
            .map((json) => Room.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to fetch search queue: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching search queue: $e');
      return [];
    }
  }
}