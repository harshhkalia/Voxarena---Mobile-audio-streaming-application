import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/room.dart';
import '../services/follow_service.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/like_service.dart';
import '../widgets/room_card.dart';
import '../widgets/comments_sheet.dart';
import 'profile_screen.dart';
import '../services/download_tracking_service.dart';
import '../services/room_report_service.dart';

class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  final _followService = FollowService();
  final _authService = AuthService();
  final _audio = GlobalAudioService();

  List<Map<String, dynamic>> _followingUsers = [];
  List<Room> _followingRooms = [];
  bool _isLoading = true;
  int? _selectedUserId;
  int _followingPage = 1;
  bool _followingHasMore = true;
  int _roomsPage = 1;
  bool _roomsHasMore = true;

  final _reportService = RoomReportService();
  final Map<int, bool> _reportedRooms = {};

  @override
  void initState() {
    super.initState();
    _loadFollowingData();
    _audio.addListener(_onAudioChanged);
  }

  @override
  void dispose() {
    _audio.removeListener(_onAudioChanged);
    super.dispose();
  }

  void _onAudioChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadReportStatuses() async {
    for (var room in _followingRooms) {
      final roomId = room.id;
      final status = await _reportService.checkReportStatus(roomId);

      if (status != null && mounted) {
        setState(() {
          _reportedRooms[roomId] = status['has_reported'] ?? false;
        });
      }
    }
  }

  Future<void> _loadFollowingData({bool reset = true}) async {
    if (reset) {
      _followingPage = 1;
      _roomsPage = 1;
      _followingHasMore = true;
      _roomsHasMore = true;
    }

    setState(() => _isLoading = true);

    final currentUserId = _authService.currentUser?['id'];
    if (currentUserId == null) {
      setState(() => _isLoading = false);
      return;
    }

    final followingRes = await _followService.getFollowing(
      currentUserId,
      page: _followingPage,
    );

    final roomsRes = await _followService.getFollowingRooms(page: _roomsPage);

    if (!mounted) return;

    setState(() {
      if (followingRes != null) {
        final users = List<Map<String, dynamic>>.from(
          followingRes['following'],
        );

        if (reset) {
          _followingUsers = users;
        } else {
          _followingUsers.addAll(users);
        }

        _followingHasMore = followingRes['has_more'] == true;
        _followingPage++;
      }

      if (roomsRes != null) {
        final rooms = (roomsRes['rooms'] as List)
            .map((e) => Room.fromJson(e))
            .toList();

        if (reset) {
          _followingRooms = rooms;
        } else {
          _followingRooms.addAll(rooms);
        }

        _roomsHasMore = roomsRes['has_more'] == true;
        _roomsPage++;
      }

      _isLoading = false;
    });
    await _loadReportStatuses();
  }

  List<Room> get _filteredRooms {
    if (_selectedUserId == null) {
      return _followingRooms;
    }
    return _followingRooms
        .where((room) => room.hostId == _selectedUserId)
        .toList();
  }

  Future<void> _playRoom(Room room) async {
    if (room.audioUrl == null || room.audioUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio URL found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final roomData = {
        'id': room.id,
        'title': room.title,
        'audio_url': room.audioUrl,
        'thumbnail_url': room.thumbnail,
        'topic': room.topic,
        'likes_count': room.likesCount ?? 0,
        'host_name': room.hostName,
        'host_avatar': room.hostAvatar,
        'host_followers_count': room.listenerCount,
        'host_id': room.hostId,
        'host': {
          'id': room.hostId,
          'full_name': room.hostName,
          'profile_pic': room.hostAvatar,
          'followers_count': room.hostFollowersCount,
        },
      };

      final queueData = _filteredRooms.map((r) {
        return {
          'id': r.id,
          'title': r.title,
          'audio_url': r.audioUrl,
          'thumbnail_url': r.thumbnail,
          'topic': r.topic,
          'likes_count': r.likesCount ?? 0,
          'host_name': r.hostName,
          'host_avatar': r.hostAvatar,
          'host_followers_count': r.listenerCount,
          'host_id': r.hostId,
          'host': {
            'id': r.hostId,
            'full_name': r.hostName,
            'profile_pic': r.hostAvatar,
            'followers_count': r.hostFollowersCount,
          },
        };
      }).toList();

      final currentIndex = _filteredRooms.indexWhere((r) => r.id == room.id);

      if (currentIndex >= 0 && _audio.isAutoplayEnabled) {
        _audio.setAutoplayQueue(queueData, currentIndex);
      }

      // setState(() {
      //   final index = _followingRooms.indexWhere((r) => r.id == room.id);
      //   if (index != -1) {
      //     _followingRooms[index] = _followingRooms[index].copyWith(
      //       totalListens: (_followingRooms[index].totalListens ?? 0) + 1,
      //     );
      //   }
      // });

      await _audio.playRoom(roomData, fromUser: false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error playing audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleReportRoom(Room room, int index) async {
    if (_reportedRooms[room.id] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already reported this room'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final reason = await _showReportDialog();
    if (reason == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
        ),
      ),
    );

    try {
      final result = await _reportService.reportRoom(
        roomId: room.id,
        reason: reason,
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (result != null && result['success'] == true) {
        final wasHidden = result['room_hidden'] == true;

        setState(() {
          _reportedRooms[room.id] = true;

          if (wasHidden) {
            _followingRooms.removeAt(index);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasHidden
                  ? 'Room reported and hidden due to multiple reports'
                  : 'Room reported successfully',
            ),
            backgroundColor: wasHidden ? Colors.red : const Color(0xFF7C3AED),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result?['error'] ?? 'Failed to report room'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _showReportDialog() async {
    final reasons = [
      'Spam',
      'Inappropriate Content',
      'Harassment',
      'Misinformation',
      'Copyright Violation',
      'Violence',
      'Hate Speech',
      'Other',
    ];

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Report Room',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Why are you reporting this room?',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ...reasons.map(
              (reason) => ListTile(
                title: Text(
                  reason,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, reason),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showRoomOptions(BuildContext context, Room room, int index) {
    final currentUserId = _authService.currentUser?['id'];
    final isOwnRoom = currentUserId != null && room.hostId == currentUserId;

    final rootContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    room.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.grey, height: 1),
                const SizedBox(height: 10),
                _buildOption(
                  icon: Icons.repeat,
                  label: 'Loop',
                  showCheckmark:
                      _audio.isLooping &&
                      _audio.currentRoom != null &&
                      _audio.currentRoom!['id'] == room.id,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _handleLoop(room, rootContext);
                  },
                ),
                _buildOption(
                  icon: Icons.download,
                  label: 'Download',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleDownload(room, rootContext);
                  },
                ),
                if (!isOwnRoom)
                  _buildOption(
                    icon: Icons.flag_outlined,
                    label: _reportedRooms[room.id] == true
                        ? 'Already Reported'
                        : 'Report Room',
                    iconColor: _reportedRooms[room.id] == true
                        ? Colors.amber
                        : Colors.red,
                    labelColor: _reportedRooms[room.id] == true
                        ? Colors.amber
                        : Colors.white,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _handleReportRoom(room, index);
                    },
                  ),
                _buildOption(
                  icon: Icons.info_outline,
                  label: 'Show Description',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showRoomDescription(room);
                  },
                ),
                _buildOption(
                  icon: Icons.playlist_play,
                  label: 'Enable Autoplay',
                  showCheckmark:
                      _audio.isAutoplayEnabled &&
                      _audio.currentRoom != null &&
                      _audio.currentRoom!['id'] == room.id,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleAutoplay(room, index);
                  },
                ),
                if (isOwnRoom) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Colors.grey, height: 1),
                  const SizedBox(height: 10),
                  _buildOption(
                    icon: Icons.edit,
                    label: 'Edit & More Actions',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute(
                          builder: (context) =>
                              ProfileScreen(scrollToRoomId: room.id),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white70,
    Color labelColor = Colors.white,
    bool showCheckmark = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (showCheckmark)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF7C3AED),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLoop(Room room, BuildContext rootContext) async {
    final wasLooping = _audio.isLooping;
    final isCurrentRoom =
        _audio.currentRoom != null && _audio.currentRoom!['id'] == room.id;

    await _audio.toggleLoop();
    if (!mounted) return;
    setState(() {});

    if (!wasLooping && _audio.isLooping && !isCurrentRoom) {
      try {
        await _playRoom(room);
      } catch (e) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(_audio.isLooping ? 'Loop enabled' : 'Loop disabled'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF7C3AED),
        ),
      );
    }
  }

  Future<bool> _ensureDownloadPermissions() async {
    if (!Platform.isAndroid) return true;
    var notifStatus = await Permission.notification.status;
    if (notifStatus.isDenied) {
      notifStatus = await Permission.notification.request();
    }
    if (notifStatus.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return true;
  }

  Future<void> _handleDownload(Room room, BuildContext rootContext) async {
    final audioUrl = room.audioUrl;
    final title = room.title;

    if (audioUrl == null || audioUrl.isEmpty) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text('No audio URL found for this upload'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final safeTitle = title.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final fileName = '$safeTitle.mp3';

    try {
      if (Platform.isAndroid) {
        final hasPermission = await _ensureDownloadPermissions();
        if (!hasPermission) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            const SnackBar(
              content: Text('Permission required for download'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        final baseDir = await getExternalStorageDirectory();
        final savedDir = baseDir?.path ?? '/sdcard/Download';

        try {
          final taskId = await FlutterDownloader.enqueue(
            url: audioUrl,
            fileName: fileName,
            savedDir: savedDir,
            showNotification: true,
            openFileFromNotification: true,
            saveInPublicStorage: true,
          );

          if (taskId != null) {
            final downloadService = DownloadTrackingService();
            await downloadService.trackDownload(
              roomId: room.id,
              fileName: fileName,
              downloadPath: '$savedDir/$fileName',
            );

            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text('$fileName download started!'),
                backgroundColor: const Color(0xFF7C3AED),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(rootContext).showSnackBar(
            SnackBar(
              content: Text('Failed to start download: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final savedDir = dir.path;

      await FlutterDownloader.enqueue(
        url: audioUrl,
        fileName: fileName,
        savedDir: savedDir,
        showNotification: true,
        openFileFromNotification: true,
      );

      final downloadService = DownloadTrackingService();
      await downloadService.trackDownload(
        roomId: room.id,
        fileName: fileName,
        downloadPath: '$savedDir/$fileName',
      );

      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          content: Text('Download started'),
          backgroundColor: Color(0xFF7C3AED),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showRoomDescription(Room room) {
    final createdAtRaw = room.createdAt;
    String uploadedText = 'Uploaded date unknown';

    try {
      final dt = createdAtRaw.toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year.toString();
      uploadedText = 'Uploaded on $day-$month-$year';
    } catch (_) {}

    final description =
        room.description != null && room.description!.trim().isNotEmpty
        ? room.description!.trim()
        : 'No description added for this audio.';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            room.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                uploadedText,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  void _handleAutoplay(Room room, int index) async {
    final isCurrentRoom =
        _audio.currentRoom != null && _audio.currentRoom!['id'] == room.id;

    if (_audio.isAutoplayEnabled && isCurrentRoom) {
      _audio.disableAutoplay();
      if (!mounted) return;

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Autoplay disabled'),
          backgroundColor: Color(0xFF7C3AED),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final queueData = _filteredRooms.map((r) {
      return {
        'id': r.id,
        'title': r.title,
        'audio_url': r.audioUrl,
        'thumbnail_url': r.thumbnail,
        'topic': r.topic,
        'likes_count': r.likesCount ?? 0,
        'host_name': r.hostName,
        'host_avatar': r.hostAvatar,
        'host_followers_count': r.listenerCount,
        'host_id': r.hostId,
        'host': {
          'id': r.hostId,
          'full_name': r.hostName,
          'profile_pic': r.hostAvatar,
          'followers_count': r.hostFollowersCount,
        },
      };
    }).toList();

    _audio.setAutoplayQueue(queueData, index);

    if (!isCurrentRoom) {
      try {
        await _playRoom(room);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Autoplay enabled'),
        backgroundColor: Color(0xFF7C3AED),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleFollowChange(int hostId, bool isFollowing) async {
    if (!mounted) return;

    if (isFollowing) {
      final currentUserId = _authService.currentUser?['id'];
      if (currentUserId == null) return;

      final res = await _followService.getFollowing(
        currentUserId,
        page: 1,
        limit: 1,
      );

      if (res == null) return;

      final newUser = Map<String, dynamic>.from(res['following'][0]);

      setState(() {
        _followingUsers.removeWhere((u) => u['id'] == hostId);
        _followingUsers.insert(0, newUser);
        _selectedUserId = null;
      });

      _roomsPage = 1;
      final roomsRes = await _followService.getFollowingRooms(page: 1);

      if (roomsRes != null && mounted) {
        setState(() {
          _followingRooms = (roomsRes['rooms'] as List)
              .map((e) => Room.fromJson(e))
              .toList();
          _roomsHasMore = roomsRes['has_more'] == true;
        });
      }
    } else {
      setState(() {
        _followingUsers.removeWhere((u) => u['id'] == hostId);
        _followingRooms.removeWhere((r) => r.hostId == hostId);
        if (_selectedUserId == hostId) {
          _selectedUserId = null;
        }
      });
    }
  }

  void _openFullPlayer() {
    if (_audio.currentRoom == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FullPlayerSheet(
        audio: _audio,
        currentUser: _authService.currentUser,
        onFollowChanged: _handleFollowChange,
      ),
    );
  }

  Widget _buildMiniPlayer() {
    if (_audio.currentUrl == null) {
      return const SizedBox.shrink();
    }

    final totalSecs = _audio.duration.inSeconds;
    final posSecs = _audio.position.inSeconds.clamp(
      0,
      totalSecs > 0 ? totalSecs : 1,
    );

    String formatDuration(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openFullPlayer,
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -8) {
          _openFullPlayer();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF11111F),
          border: Border(
            top: BorderSide(
              color: const Color(0xFF7C3AED).withOpacity(0.4),
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _audio.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: const Color(0xFF7C3AED),
                    size: 32,
                  ),
                  onPressed: () async {
                    await _audio.togglePlayPause();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _audio.currentTitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
                  onPressed: _openFullPlayer,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  formatDuration(_audio.position),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: posSecs.toDouble(),
                      max: (totalSecs > 0 ? totalSecs : 1).toDouble(),
                      onChanged: (value) async {
                        final newPos = Duration(seconds: value.toInt());
                        await _audio.player.seek(newPos);
                      },
                      activeColor: const Color(0xFF7C3AED),
                      inactiveColor: Colors.white24,
                    ),
                  ),
                ),
                Text(
                  formatDuration(_audio.duration),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unfollowSelectedUser() async {
    final hostId = _selectedUserId;
    if (hostId == null) return;

    final user = _followingUsers.firstWhere(
      (u) => u['id'] == hostId,
      orElse: () => {},
    );

    final username = user['full_name'] ?? 'this user';

    final shouldUnfollow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Unfollow user?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Do you want to remove $username from your following list?',
            style: const TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF7C3AED),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Unfollow'),
            ),
          ],
        );
      },
    );

    if (shouldUnfollow != true) return;

    final result = await _followService.toggleFollow(hostId);
    if (result == null) return;

    final isFollowing = result['is_following'] ?? true;
    if (isFollowing) return;

    setState(() {
      _followingUsers.removeWhere((u) => u['id'] == hostId);
      _followingRooms.removeWhere((r) => r.hostId == hostId);
      _selectedUserId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('User unfollowed'),
        backgroundColor: Color(0xFF7C3AED),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showSelectedUserActions() {
    if (_selectedUserId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Actions', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Colors.white),
              title: const Text(
                'Visit Profile',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: _selectedUserId!),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: const Text(
                'Unfollow',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _unfollowSelectedUser();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Following',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedUserId == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadFollowingData,
            )
          else
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showSelectedUserActions,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _followingUsers.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                _buildFollowingUsersSection(),
                const Divider(height: 1, color: Colors.grey),
                Expanded(child: _buildRoomsSection()),
              ],
            ),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[600]),
          const SizedBox(height: 16),
          const Text(
            'Not following anyone yet',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Follow creators to see their latest content here',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingUsersSection() {
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _followingUsers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildUserChip(null, 'All', null, _selectedUserId == null);
          }

          final user = _followingUsers[index - 1];
          final userId = user['id'] is int
              ? user['id']
              : int.tryParse(user['id']?.toString() ?? '0') ?? 0;

          return _buildUserChip(
            userId,
            user['full_name'] ?? 'Unknown',
            user['profile_pic'],
            _selectedUserId == userId,
          );
        },
      ),
    );
  }

  Widget _buildUserChip(
    int? userId,
    String name,
    String? profilePic,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedUserId = userId;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 80,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7C3AED)
                      : Colors.grey[800]!,
                  width: 3,
                ),
                color: const Color(0xFF1A1A2E),
              ),
              child: ClipOval(
                child: profilePic != null && profilePic.isNotEmpty
                    ? Image.network(
                        profilePic,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildAvatarFallback(name),
                      )
                    : _buildAvatarFallback(name),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                color: isSelected ? const Color(0xFF7C3AED) : Colors.white,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Container(
      color: const Color(0xFF7C3AED),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildRoomsSection() {
    final rooms = _filteredRooms;

    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.audiotrack_outlined, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              _selectedUserId == null
                  ? 'No content from followed creators'
                  : 'This creator hasn\'t uploaded anything yet',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFollowingData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RoomCard(
              room: room,
              onTap: () => _playRoom(room),
              onLongPress: () => _showRoomOptions(context, room, index),
            ),
          );
        },
      ),
    );
  }
}

class _FullPlayerSheet extends StatefulWidget {
  final GlobalAudioService audio;
  final Map<String, dynamic>? currentUser;
  final Function(int hostId, bool isFollowing) onFollowChanged;

  const _FullPlayerSheet({
    required this.audio,
    this.currentUser,
    required this.onFollowChanged,
  });

  @override
  State<_FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<_FullPlayerSheet> {
  bool _isLiked = false;
  int _likesCount = 0;
  final _likeService = LikeService();
  bool _isTogglingLike = false;
  int? _lastRoomId;

  @override
  void initState() {
    super.initState();
    widget.audio.addListener(_onAudioChanged);

    if (widget.audio.currentRoom != null) {
      final roomId = widget.audio.currentRoom!['id'] as int?;
      _lastRoomId = roomId;

      final likes = widget.audio.currentRoom!['likes_count'] ?? 0;
      _likesCount = likes is int ? likes : int.tryParse(likes.toString()) ?? 0;
    }

    _loadLikeStatus();
  }

  @override
  void dispose() {
    widget.audio.removeListener(_onAudioChanged);
    super.dispose();
  }

  void _onAudioChanged() {
    final currentRoom = widget.audio.currentRoom;
    if (currentRoom == null) return;

    final roomId = currentRoom['id'] as int?;
    if (roomId == null) return;
    if (roomId == _lastRoomId) return;

    _lastRoomId = roomId;

    if (!mounted) return;

    setState(() {
      _isLiked = false;

      _likesCount = currentRoom['likes_count'] is int
          ? currentRoom['likes_count']
          : 0;
    });

    _loadLikeStatus();
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _loadLikeStatus() async {
    final roomId = widget.audio.currentRoom?['id'];
    if (roomId == null) return;

    final result = await _likeService.checkLikeStatus(roomId);
    if (result != null && mounted) {
      setState(() {
        _isLiked = result['is_liked'] ?? false;
        _likesCount = result['likes_count'] ?? 0;
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_isTogglingLike) return;

    final roomId = widget.audio.currentRoom?['id'];
    if (roomId == null) return;

    setState(() {
      _isTogglingLike = true;
    });

    final result = await _likeService.toggleLike(roomId);

    if (result != null && mounted) {
      setState(() {
        _isLiked = result['is_liked'] ?? false;
        _likesCount = result['likes_count'] ?? 0;
        _isTogglingLike = false;
      });
    } else {
      setState(() {
        _isTogglingLike = false;
      });
    }
  }

  PopupMenuItem<double> _buildSpeedMenuItem(double speed) {
    final isSelected = speed == widget.audio.playbackSpeed;
    return PopupMenuItem<double>(
      value: speed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${speed}x',
            style: TextStyle(
              color: isSelected ? const Color(0xFF7C3AED) : Colors.white,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (isSelected)
            const Icon(Icons.check, color: Color(0xFF7C3AED), size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.audio.currentRoom;
    if (room == null) return const SizedBox.shrink();

    final thumbUrl = room['thumbnail_url'] as String?;
    final topic = room['topic'] as String? ?? '';
    final title = widget.audio.currentTitle ?? 'Untitled';
    final host = room['host'] as Map<String, dynamic>?;

    final String hostName =
        host?['full_name'] as String? ??
        room['host_name'] as String? ??
        'Unknown';

    final String? hostAvatar =
        host?['profile_pic'] as String? ?? room['host_avatar'] as String?;

    int? hostId;
    final hostIdFromHost = host?['id'];
    final hostIdFromRoom = room['host_id'];

    if (hostIdFromHost != null) {
      hostId = hostIdFromHost is int
          ? hostIdFromHost
          : int.tryParse(hostIdFromHost.toString());
    } else if (hostIdFromRoom != null) {
      hostId = hostIdFromRoom is int
          ? hostIdFromRoom
          : int.tryParse(hostIdFromRoom.toString());
    }

    int? currentUserId;
    if (widget.currentUser != null) {
      final userId = widget.currentUser!['id'];
      currentUserId = userId is int
          ? userId
          : int.tryParse(userId?.toString() ?? '');
    }

    final bool isOwnAudio =
        hostId != null && currentUserId != null && hostId == currentUserId;

    int followers = 0;
    final fromHost = host?['followers_count'];
    final fromFlat = room['host_followers_count'];

    if (fromHost != null) {
      followers = int.tryParse(fromHost.toString()) ?? 0;
    } else if (fromFlat != null) {
      followers = int.tryParse(fromFlat.toString()) ?? 0;
    }

    final totalSecs = widget.audio.duration.inSeconds;
    final safeMax = totalSecs > 0 ? totalSecs : 1;
    final posSecs = widget.audio.position.inSeconds.clamp(0, safeMax);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F0F1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: thumbUrl != null && thumbUrl.isNotEmpty
                          ? Image.network(
                              thumbUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: const Color(0xFF1A1A2E),
                                    child: const Icon(
                                      Icons.audiotrack,
                                      color: Color(0xFF7C3AED),
                                      size: 64,
                                    ),
                                  ),
                            )
                          : Container(
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(
                                Icons.audiotrack,
                                color: Color(0xFF7C3AED),
                                size: 64,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      topic,
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 13,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          widget.audio.disableAutoplay();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => isOwnAudio
                                  ? const ProfileScreen()
                                  : ProfileScreen(userId: hostId),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF1A1A2E),
                              backgroundImage:
                                  (hostAvatar != null && hostAvatar.isNotEmpty)
                                  ? NetworkImage(hostAvatar)
                                  : null,
                              child: (hostAvatar == null || hostAvatar.isEmpty)
                                  ? const Icon(
                                      Icons.person,
                                      color: Colors.white70,
                                      size: 20,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hostName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Text(
                                //   '${_formatCount(followers)} followers',
                                //   style: const TextStyle(
                                //     color: Colors.grey,
                                //     fontSize: 12,
                                //   ),
                                // ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (isOwnAudio)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.audio.disableAutoplay();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF1A1A2E),
                            side: const BorderSide(color: Color(0xFF7C3AED)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          child: const Text(
                            'Visit Channel',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        _FollowButton(
                          hostId: hostId!,
                          onFollowChanged: (hostId, isFollowing) {
                            if (widget.audio.currentRoom != null) {
                              final room = widget.audio.currentRoom!;
                              final host =
                                  room['host'] as Map<String, dynamic>?;

                              if (host != null) {
                                final currentFollowers =
                                    host['followers_count'] is int
                                    ? host['followers_count']
                                    : int.tryParse(
                                            host['followers_count']
                                                    ?.toString() ??
                                                '0',
                                          ) ??
                                          0;

                                host['followers_count'] =
                                    currentFollowers + (isFollowing ? 1 : -1);

                                room['host_followers_count'] =
                                    host['followers_count'];

                                setState(() {
                                  followers = host['followers_count'];
                                });
                              }
                            }

                            widget.onFollowChanged(hostId, isFollowing);
                          },
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: posSecs.toDouble(),
                          max: safeMax.toDouble(),
                          onChanged: (value) async {
                            final newPos = Duration(seconds: value.toInt());
                            await widget.audio.player.seek(newPos);
                          },
                          activeColor: const Color(0xFF7C3AED),
                          inactiveColor: Colors.white24,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(widget.audio.position),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatDuration(widget.audio.duration),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          color:
                              widget.audio.hasPrevious ||
                                  widget.audio.position.inSeconds > 0
                              ? Colors.white
                              : Colors.white54,
                          size: 32,
                        ),
                        onPressed:
                            widget.audio.hasPrevious ||
                                widget.audio.position.inSeconds > 0
                            ? () async {
                                await widget.audio.skipToPrevious();
                              }
                            : null,
                      ),
                      const SizedBox(width: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () async {
                          await widget.audio.togglePlayPause();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF7C3AED),
                          ),
                          child: Icon(
                            widget.audio.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: widget.audio.hasNext
                              ? Colors.white
                              : Colors.white54,
                          size: 32,
                        ),
                        onPressed: widget.audio.hasNext
                            ? () async {
                                await widget.audio.skipToNext();
                              }
                            : null,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF7C3AED).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Playback Speed',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        PopupMenuButton<double>(
                          initialValue: widget.audio.playbackSpeed,
                          color: const Color(0xFF1A1A2E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: const Color(0xFF7C3AED).withOpacity(0.3),
                            ),
                          ),
                          onSelected: (speed) async {
                            await widget.audio.setPlaybackSpeed(speed);
                          },
                          itemBuilder: (context) => [
                            _buildSpeedMenuItem(0.25),
                            _buildSpeedMenuItem(0.5),
                            _buildSpeedMenuItem(0.75),
                            _buildSpeedMenuItem(1.0),
                            _buildSpeedMenuItem(1.25),
                            _buildSpeedMenuItem(1.5),
                            _buildSpeedMenuItem(1.75),
                            _buildSpeedMenuItem(2.0),
                            _buildSpeedMenuItem(2.5),
                            _buildSpeedMenuItem(3.0),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${widget.audio.playbackSpeed}x',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: _isTogglingLike ? null : _toggleLike,
                        icon: Icon(
                          _isLiked ? Icons.favorite : Icons.favorite_border,
                          color: _isLiked
                              ? const Color(0xFFEB5757)
                              : Colors.white70,
                        ),
                        label: Text(
                          _formatCount(_likesCount),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          // Navigator.pop(context);
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => CommentsSheet(
                              roomId: room['id'],
                              roomTitle: title,
                              roomAuthorId: room['host_id'] ?? 0,
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.comment_outlined,
                          color: Colors.white70,
                        ),
                        label: const Text(
                          'Comments',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(
                          Icons.share_outlined,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FollowButton extends StatefulWidget {
  final int hostId;
  final Function(int hostId, bool isFollowing)? onFollowChanged;
  // final VoidCallback? onUnfollow;

  const _FollowButton({
    required this.hostId,
    this.onFollowChanged,
    // this.onUnfollow,
  });

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _isFollowing = false;
  bool _isLoading = true;
  final _followService = FollowService();

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    final status = await _followService.checkFollowStatus(widget.hostId);
    if (mounted) {
      setState(() {
        _isFollowing = status;
        _isLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostId != widget.hostId) {
      _isLoading = true;
      _checkFollowStatus();
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _isLoading = true);

    final result = await _followService.toggleFollow(widget.hostId);

    if (result != null && mounted) {
      final newFollowStatus = result['is_following'] ?? false;

      setState(() {
        _isFollowing = newFollowStatus;
        _isLoading = false;
      });

      widget.onFollowChanged?.call(widget.hostId, newFollowStatus);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newFollowStatus ? 'Following user!' : 'Unfollowed user',
          ),
          backgroundColor: const Color(0xFF7C3AED),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update follow status'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return TextButton(
      onPressed: _toggleFollow,
      style: TextButton.styleFrom(
        foregroundColor: _isFollowing ? const Color(0xFF7C3AED) : Colors.white,
        backgroundColor: _isFollowing
            ? Colors.transparent
            : const Color(0xFF7C3AED),
        side: _isFollowing ? const BorderSide(color: Color(0xFF7C3AED)) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Text(
        _isFollowing ? 'Following' : 'Follow',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
