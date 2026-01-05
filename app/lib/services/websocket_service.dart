import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/app_notification.dart';

class WebSocketService extends ChangeNotifier {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final _storage = const FlutterSecureStorage();
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _pingInterval = Duration(seconds: 30);

  final _notificationController = StreamController<AppNotification>.broadcast();
  Stream<AppNotification> get notificationStream => _notificationController.stream;

  final _removeNotificationsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get removeNotificationsStream => _removeNotificationsController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        print('WebSocket: No auth token, cannot connect');
        _isConnecting = false;
        return;
      }

      final wsUrl = ApiConfig.baseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      
      final uri = Uri.parse('$wsUrl/api/v1/ws?token=$token');

      print('WebSocket: Connecting to $uri');

      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      _startPingTimer();

      print('WebSocket: Connected successfully');
      notifyListeners();
    } catch (e) {
      print('WebSocket: Connection error - $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic message) {
    try {
      print('WebSocket: Received message - $message');

      final data = json.decode(message as String);
      
      if (data['type'] == 'notification') {
        final notificationData = data['data'] as Map<String, dynamic>;
        final notification = AppNotification.fromJson(notificationData);
        
        _notificationController.add(notification);
        notifyListeners();
        
        print('WebSocket: New notification - ${notification.title}');
      } else if (data['type'] == 'remove_notifications') {
        final removeData = data['data'] as Map<String, dynamic>;
        _removeNotificationsController.add(removeData);
        notifyListeners();
        
        print('WebSocket: Remove notifications for room ${removeData['reference_id']}');
      } else if (data['type'] == 'remove_comment_notification') {
        final removeData = data['data'] as Map<String, dynamic>;
        removeData['type'] = 'comment';
        _removeNotificationsController.add(removeData);
        notifyListeners();
        
        print('WebSocket: Remove comment notification for room ${removeData['room_id']}');
      } else if (data['type'] == 'remove_comment_like_notification') {
        final removeData = data['data'] as Map<String, dynamic>;
        removeData['type'] = 'comment_like';
        _removeNotificationsController.add(removeData);
        notifyListeners();
        
        print('WebSocket: Remove comment like notification from actor ${removeData['actor_id']}');
      } else if (data['type'] == 'remove_follow_notification') {
        final removeData = data['data'] as Map<String, dynamic>;
        removeData['type'] = 'follow';
        _removeNotificationsController.add(removeData);
        notifyListeners();
        
        print('WebSocket: Remove follow notification from actor ${removeData['actor_id']}');
      }
    } catch (e) {
      print('WebSocket: Error parsing message - $e');
    }
  }

  void _onError(dynamic error) {
    print('WebSocket: Error - $error');
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
    _scheduleReconnect();
  }

  void _onDone() {
    print('WebSocket: Connection closed');
    _isConnected = false;
    _isConnecting = false;
    _stopPingTimer();
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('WebSocket: Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      print('WebSocket: Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts');
      connect();
    });
  }

  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(json.encode({'type': 'ping'}));
        } catch (e) {
          print('WebSocket: Ping failed - $e');
        }
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void disconnect() {
    print('WebSocket: Disconnecting');
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;
    notifyListeners();
  }

  void resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }

  @override
  void dispose() {
    disconnect();
    _notificationController.close();
    _removeNotificationsController.close();
    super.dispose();
  }
}
