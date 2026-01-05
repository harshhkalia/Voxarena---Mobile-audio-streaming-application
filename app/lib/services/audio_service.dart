import 'dart:collection';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'listen_tracking_service.dart';
import '../config/api_config.dart';

class GlobalAudioService extends ChangeNotifier {
  static final GlobalAudioService _instance = GlobalAudioService._internal();
  factory GlobalAudioService() => _instance;
  GlobalAudioService._internal();

  final AudioPlayer player = AudioPlayer();
  final ListenTrackingService _trackingService = ListenTrackingService();

  String? currentTitle;
  String? currentUrl;
  Map<String, dynamic>? currentRoom;

  bool isPlaying = false;
  bool isLooping = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  bool isAutoplayEnabled = false;
  List<Map<String, dynamic>>? _queue;
  int _queueIndex = -1;

  DateTime? _lastBackwardPress;
  static const _doubleTapWindow = Duration(seconds: 3);

  DateTime? _lastProgressUpdate;
  double playbackSpeed = 1.0;

  DateTime? _lastUiNotify;
  static const _uiUpdateInterval = Duration(seconds: 1);

  bool _shouldNotifyUi() {
    final now = DateTime.now();
    if (_lastUiNotify == null ||
        now.difference(_lastUiNotify!) >= _uiUpdateInterval) {
      _lastUiNotify = now;
      return true;
    }
    return false;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await player.setPlaybackRate(speed);
    notifyListeners();
  }

  void initListeners() {
    player.onPlayerStateChanged.listen((state) {
      isPlaying = state == PlayerState.playing;
      notifyListeners();
    });

    player.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });

    player.onPositionChanged.listen((p) {
      position = p;

      if (_shouldNotifyUi()) {
        notifyListeners();
      }

      _maybeUpdateProgress();
    });

    player.onPlayerComplete.listen((event) async {
      _updateProgressOnComplete();

      if (isLooping && currentUrl != null) {
        await player.play(UrlSource(currentUrl!));
        return;
      }

      if (isAutoplayEnabled && _queue != null && _queue!.isNotEmpty) {
        if (_queueIndex < 0 && currentUrl != null) {
          _queueIndex = _queue!.indexWhere((r) => r['audio_url'] == currentUrl);
        }

        final nextIndex = _queueIndex + 1;
        if (nextIndex >= 0 && nextIndex < _queue!.length) {
          _queueIndex = nextIndex;
          final nextRoom = _queue![nextIndex];
          await playRoom(nextRoom, resetLoop: false, fromUser: false);
        } else {
          disableAutoplay();
        }
      }
    });
  }

  void setAutoplayQueue(List<Map<String, dynamic>> rooms, int startIndex) {
    _queue = rooms;
    _queueIndex = startIndex;
    isAutoplayEnabled = true;
    notifyListeners();
  }

  void disableAutoplay() {
    isAutoplayEnabled = false;
    _queue = null;
    _queueIndex = -1;
    notifyListeners();
  }

  List<Map<String, dynamic>> get autoplayQueue => _queue ?? [];
  int get currentQueueIndex => _queueIndex;

  Future<void> playQueueItem(int index) async {
    if (_queue == null || index < 0 || index >= _queue!.length) return;
    _queueIndex = index;
    await playRoom(_queue![index], resetLoop: false, fromUser: true);
    notifyListeners();
  }

  bool get hasPrevious =>
      _queue != null && _queue!.isNotEmpty && _queueIndex > 0;

  bool get hasNext =>
      _queue != null &&
      _queue!.isNotEmpty &&
      _queueIndex >= 0 &&
      _queueIndex < _queue!.length - 1;

  Future<void> skipToPrevious() async {
    final now = DateTime.now();
    final isDoubleTap =
        _lastBackwardPress != null &&
        now.difference(_lastBackwardPress!) < _doubleTapWindow;

    if (!isDoubleTap || position.inSeconds > 3) {
      await player.seek(Duration.zero);
      _lastBackwardPress = now;
      notifyListeners();
      return;
    }

    if (hasPrevious) {
      _queueIndex--;
      await playRoom(_queue![_queueIndex], resetLoop: false, fromUser: false);
      _lastBackwardPress = null;
    } else {
      await player.seek(Duration.zero);
      _lastBackwardPress = now;
    }

    notifyListeners();
  }

  Future<void> skipToNext() async {
    if (!hasNext) return;
    _queueIndex++;
    await playRoom(_queue![_queueIndex], resetLoop: false, fromUser: false);
    notifyListeners();
  }

  Future<void> playRoom(
    Map<String, dynamic> room, {
    bool resetLoop = true,
    bool fromUser = true,
  }) async {
    if (currentRoom?['id'] != null) {
      await _trackingService.stopListening(currentRoom!['id']);
    }

    if (resetLoop && isLooping) {
      await setLoop(false);
    }

    try {
      await player.stop();
    } catch (_) {}

    currentRoom = room;
    currentTitle = room['title'];
    currentUrl = room['audio_url'];

    if (_queue != null && currentUrl != null) {
      final index = _queue!.indexWhere((r) => r['audio_url'] == currentUrl);
      if (index >= 0) _queueIndex = index;
    }

    await player.play(UrlSource(currentUrl!));
    await player.setPlaybackRate(playbackSpeed);
    isPlaying = true;

    if (room['id'] != null) {
      await _recordUniqueListen(room['id']);
      await _trackingService.startListening(room['id']);
      _lastProgressUpdate = DateTime.now();
    }

    if (fromUser && _queue == null) {
      disableAutoplay();
    }

    _lastBackwardPress = null;
    notifyListeners();
  }

  Future<void> _recordUniqueListen(int roomId) async {
    try {
      final storage = const FlutterSecureStorage();
      final token = await storage.read(key: 'jwt_token');

      if (token == null) return;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/rooms/$roomId/record-listen'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (currentRoom != null && data['total_listens'] != null) {
          currentRoom!['total_listens'] = data['total_listens'];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Failed to record unique listen: $e');
    }
  }

  Future<void> togglePlayPause() async {
    isPlaying ? await player.pause() : await player.resume();
    notifyListeners();
  }

  Future<void> toggleLoop() async => setLoop(!isLooping);

  Future<void> setLoop(bool loop) async {
    isLooping = loop;
    await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    notifyListeners();
  }

  void _maybeUpdateProgress() {
    if (_lastProgressUpdate == null || currentRoom?['id'] == null) return;

    final now = DateTime.now();
    if (now.difference(_lastProgressUpdate!) < const Duration(seconds: 30)) {
      return;
    }

    _lastProgressUpdate = now;
    _updateListenProgress();
  }

  void _updateListenProgress() {
    if (duration.inSeconds == 0) return;

    _trackingService.updateListenProgress(
      duration: duration.inSeconds,
      lastPosition: position.inSeconds,
      completionRate: position.inSeconds / duration.inSeconds,
      isCompleted: false,
      isSkipped: false,
    );
  }

  void _updateProgressOnComplete() {
    if (currentRoom == null) return;

    _trackingService.updateListenProgress(
      duration: duration.inSeconds,
      lastPosition: duration.inSeconds,
      completionRate: 1.0,
      isCompleted: true,
      isSkipped: false,
    );
  }

  Future<void> cleanup() async {
    if (currentRoom?['id'] != null) {
      await _trackingService.stopListening(currentRoom!['id']);
    }
    _trackingService.dispose();
  }
}
