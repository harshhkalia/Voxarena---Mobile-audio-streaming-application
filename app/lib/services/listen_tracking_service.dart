import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ListenTrackingService {
  static final ListenTrackingService _instance =
      ListenTrackingService._internal();
  factory ListenTrackingService() => _instance;
  ListenTrackingService._internal();

  final _storage = const FlutterSecureStorage();
  Timer? _pollingTimer;
  int? _currentRoomId;
  int? _currentHistoryId;

  Function(int roomId, int listenerCount, int totalListens)?
  onListenerCountUpdate;

  Future<void> startListening(int roomId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/start-listening',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/start-listening',
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
        _currentRoomId = roomId;
        _currentHistoryId = data['history_id'];

        print('✅ Started listening to room $roomId');
        print('📊 Listener count: ${data['listener_count']}');
        print('🔴 Is live: ${data['is_live']}');

        if (data['is_live'] == true) {
          _startPolling(roomId);
        }
      } else {
        print('❌ Failed to start listening: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error starting listening: $e');
    }
  }

  Future<void> stopListening(int roomId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/stop-listening',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/stop-listening',
);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        print('✅ Stopped listening to room $roomId');

        _stopPolling();
        _currentRoomId = null;
        _currentHistoryId = null;
      }
    } catch (e) {
      print('❌ Error stopping listening: $e');
    }
  }

  Future<void> updateListenProgress({
    required int duration,
    required int lastPosition,
    required double completionRate,
    bool isCompleted = false,
    bool isSkipped = false,
  }) async {
    if (_currentHistoryId == null) return;

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/listen-history/$_currentHistoryId',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/listen-history/$_currentHistoryId',
);

      await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'duration': duration,
          'last_position': lastPosition,
          'completion_rate': completionRate,
          'is_completed': isCompleted,
          'is_skipped': isSkipped,
        }),
      );
    } catch (e) {
      print('❌ Error updating listen progress: $e');
    }
  }

  void _startPolling(int roomId) {
    _stopPolling();

    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchListenerCount(roomId);
    });

    _fetchListenerCount(roomId);
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _fetchListenerCount(int roomId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/listeners',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/listeners',
);

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final listenerCount = data['listener_count'] ?? 0;
        final totalListens = data['total_listens'] ?? 0;

        onListenerCountUpdate?.call(roomId, listenerCount, totalListens);
      }
    } catch (e) {
      print('❌ Error fetching listener count: $e');
    }
  }

  Future<Map<String, dynamic>?> getListenHistory({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/my-history?page=$page&limit=$limit',
      // );

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/my-history?page=$page&limit=$limit',
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
      print('❌ Error fetching listen history: $e');
    }
    return null;
  }

  void dispose() {
    _stopPolling();
  }
}
