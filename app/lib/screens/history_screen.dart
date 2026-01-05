import 'dart:convert';
import 'dart:io';
import 'package:app/services/follow_service.dart';
import 'package:app/services/like_service.dart';
import 'package:app/widgets/comments_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/room.dart';
import '../widgets/room_card.dart';
import '../services/listen_tracking_service.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import 'profile_screen.dart';
import '../config/api_config.dart';
import 'package:intl/intl.dart';
import '../services/download_tracking_service.dart';
import '../services/room_report_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ListenTrackingService _trackingService = ListenTrackingService();
  final GlobalAudioService _audio = GlobalAudioService();
  final AuthService _authService = AuthService();
  final _storage = const FlutterSecureStorage();

  List<Map<String, dynamic>> historyContent = [];
  Map<String, List<Map<String, dynamic>>> groupedHistory = {};
  bool isLoading = false;

  int _page = 1;
  final int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final _reportService = RoomReportService();
  final Map<int, bool> _reportedRooms = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory(reset: true);
    _audio.addListener(_onAudioChanged);
  }

  void _onAudioChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audio.removeListener(_onAudioChanged);
    super.dispose();
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (reset) {
      setState(() {
        isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _page = 1;
        historyContent = [];
        groupedHistory = {};
      });
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final data = await _trackingService.getListenHistory(
        page: _page,
        limit: _pageSize,
      );

      if (data != null && data['history'] != null) {
        final historyList = data['history'] as List;

        final fetched = historyList.map((item) {
          return item as Map<String, dynamic>;
        }).toList();

        setState(() {
          if (reset) {
            historyContent = fetched;
          } else {
            historyContent.addAll(fetched);
          }

          _groupHistoryByDate();

          if (data['has_more'] != null) {
            _hasMore = data['has_more'] == true;
          } else {
            _hasMore = fetched.length == _pageSize;
          }

          _page += 1;
          isLoading = false;
          _isLoadingMore = false;
        });
        await _loadReportStatuses();
      } else {
        setState(() {
          isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error loading history: $e');
      setState(() {
        isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _handleReportRoom(
    Room room,
    Map<String, dynamic> historyItem,
  ) async {
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
            // Remove the room from history content
            historyContent.removeWhere((item) {
              final roomData = item['room'] as Map<String, dynamic>?;
              return roomData?['id'] == room.id;
            });
            _groupHistoryByDate();
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

  Future<void> _loadReportStatuses() async {
    for (var item in historyContent) {
      final roomData = item['room'] as Map<String, dynamic>?;
      if (roomData == null) continue;

      final roomId = roomData['id'] as int?;
      if (roomId == null) continue;

      final status = await _reportService.checkReportStatus(roomId);

      if (status != null && mounted) {
        setState(() {
          _reportedRooms[roomId] = status['has_reported'] ?? false;
        });
      }
    }
  }

  void _groupHistoryByDate() {
    groupedHistory.clear();
    for (var item in historyContent) {
      final listenedAt = item['listened_at'] as String?;
      if (listenedAt == null) continue;

      final dateTime = DateTime.parse(listenedAt);
      final dateKey = DateFormat('yyyy-MM-dd').format(dateTime);

      if (!groupedHistory.containsKey(dateKey)) {
        groupedHistory[dateKey] = [];
      }
      groupedHistory[dateKey]!.add(item);
    }
  }

  String _formatDateLabel(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMMM dd, yyyy').format(date);
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || isLoading) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadHistory(reset: false);
    }
  }

  Future<void> _playRoom(Map<String, dynamic> historyItem) async {
    final roomData = historyItem['room'] as Map<String, dynamic>?;
    if (roomData == null) return;

    final audioUrl = roomData['audio_url'] as String?;
    if (audioUrl == null || audioUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio URL found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final host = roomData['host'] as Map<String, dynamic>?;
      final playData = {
        'id': roomData['id'],
        'title': roomData['title'],
        'audio_url': audioUrl,
        'thumbnail_url': roomData['thumbnail_url'],
        'topic': roomData['topic'],
        'likes_count': roomData['likes_count'] ?? 0,
        'host_name': host?['full_name'] ?? 'Unknown',
        'host_avatar': host?['profile_pic'],
        'host_followers_count': host?['followers_count'] ?? 0,
        'host_id': host?['id'],
        'host': host,
      };

      final queueData = historyContent
          .map((item) {
            final r = item['room'] as Map<String, dynamic>?;
            if (r == null) return null;
            final h = r['host'] as Map<String, dynamic>?;
            return {
              'id': r['id'],
              'title': r['title'],
              'audio_url': r['audio_url'],
              'thumbnail_url': r['thumbnail_url'],
              'topic': r['topic'],
              'likes_count': r['likes_count'] ?? 0,
              'host_name': h?['full_name'] ?? 'Unknown',
              'host_avatar': h?['profile_pic'],
              'host_followers_count': h?['followers_count'] ?? 0,
              'host_id': h?['id'],
              'host': h,
            };
          })
          .where((item) => item != null)
          .cast<Map<String, dynamic>>()
          .toList();

      final currentIndex = historyContent.indexWhere((item) {
        final r = item['room'] as Map<String, dynamic>?;
        return r?['id'] == roomData['id'];
      });

      if (currentIndex >= 0 && _audio.isAutoplayEnabled) {
        _audio.setAutoplayQueue(queueData, currentIndex);
      }

      setState(() {
        final idx = historyContent.indexWhere((item) {
          final r = item['room'] as Map<String, dynamic>?;
          return r?['id'] == roomData['id'];
        });

        if (idx != -1) {
          final updatedItem = Map<String, dynamic>.from(historyContent[idx]);
          final updatedRoom = Map<String, dynamic>.from(
            updatedItem['room'] as Map<String, dynamic>,
          );

          // final currentListens =
          //     (updatedRoom['total_listens'] ??
          //             updatedRoom['totalListens'] ??
          //             updatedRoom['total_listens_count'] ??
          //             0)
          //         as int;

          // updatedRoom['total_listens'] = currentListens + 1;
          updatedItem['room'] = updatedRoom;
          historyContent[idx] = updatedItem;

          _groupHistoryByDate();
        }
      });

      await _audio.playRoom(playData, fromUser: false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error playing audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Listen History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : historyContent.isEmpty
          ? RefreshIndicator(
              onRefresh: () => _loadHistory(reset: true),
              child: ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(
                      child: Text(
                        'No listening history yet',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadHistory(reset: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: _calculateItemCount(),
                itemBuilder: (context, index) {
                  return _buildListItem(index);
                },
              ),
            ),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

  int _calculateItemCount() {
    int count = 0;
    for (var dateKey in groupedHistory.keys) {
      count += 1;
      count += groupedHistory[dateKey]!.length;
    }
    count += 1;
    return count;
  }

  Widget _buildListItem(int index) {
    int currentIndex = 0;
    final sortedKeys = groupedHistory.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    for (var dateKey in sortedKeys) {
      if (currentIndex == index) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _formatDateLabel(dateKey),
            style: const TextStyle(
              color: Color(0xFF7C3AED),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }
      currentIndex++;

      final items = groupedHistory[dateKey]!;
      for (var item in items) {
        if (currentIndex == index) {
          final roomData = item['room'] as Map<String, dynamic>?;
          final historyId = item['id'];
          if (roomData == null) return const SizedBox.shrink();

          final room = Room.fromJson(roomData);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: RoomCard(
              room: room,
              onTap: () => _playRoom(item),
              onLongPress: () =>
                  _showRoomOptions(context, room, item, historyId),
            ),
          );
        }
        currentIndex++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMore
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _deleteHistoryItem(int historyId) async {
    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication required'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/listen-history/$historyId',
      // );

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/listen-history/$historyId',
      );

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        _removeHistoryFromUI(historyId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove from history'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _removeHistoryFromUI(int historyId) {
    setState(() {
      final keys = groupedHistory.keys.toList();

      for (final key in keys) {
        groupedHistory[key]!.removeWhere((item) => item['id'] == historyId);

        if (groupedHistory[key]!.isEmpty) {
          groupedHistory.remove(key);
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Removed from history'),
        backgroundColor: Color(0xFF7C3AED),
      ),
    );
  }

  void _showRoomOptions(
    BuildContext context,
    Room room,
    Map<String, dynamic> historyItem,
    int historyId,
  ) {
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

                    final wasLooping = _audio.isLooping;
                    final isCurrentRoom =
                        _audio.currentRoom != null &&
                        _audio.currentRoom!['id'] == room.id;

                    await _audio.toggleLoop();
                    if (!mounted) return;
                    setModalState(() {});
                    setState(() {});

                    if (!wasLooping && _audio.isLooping && !isCurrentRoom) {
                      try {
                        await _playRoom(historyItem);
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
                          content: Text(
                            _audio.isLooping ? 'Loop enabled' : 'Loop disabled',
                          ),
                          duration: const Duration(seconds: 1),
                          backgroundColor: const Color(0xFF7C3AED),
                        ),
                      );
                    }
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
                      _handleReportRoom(room, historyItem);
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
                    _handleAutoplay(room, historyItem);
                  },
                ),

                _buildOption(
                  icon: Icons.delete,
                  label: 'Remove from listen history',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _deleteHistoryItem(historyId);
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

  Future<void> _handleLoop(Map<String, dynamic> historyItem) async {
    final wasLooping = _audio.isLooping;
    final roomData = historyItem['room'] as Map<String, dynamic>?;
    final isCurrentRoom =
        _audio.currentRoom != null &&
        _audio.currentRoom!['id'] == roomData?['id'];

    await _audio.toggleLoop();
    if (!mounted) return;
    setState(() {});

    if (!wasLooping && _audio.isLooping && !isCurrentRoom) {
      try {
        await _playRoom(historyItem);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_audio.isLooping ? 'Loop enabled' : 'Loop disabled'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF7C3AED),
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

  void _handleAutoplay(Room room, Map<String, dynamic> historyItem) async {
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

    final queueData = historyContent
        .map((item) {
          final r = item['room'] as Map<String, dynamic>?;
          if (r == null) return null;
          final h = r['host'] as Map<String, dynamic>?;
          return {
            'id': r['id'],
            'title': r['title'],
            'audio_url': r['audio_url'],
            'thumbnail_url': r['thumbnail_url'],
            'topic': r['topic'],
            'likes_count': r['likes_count'] ?? 0,
            'host_name': h?['full_name'] ?? 'Unknown',
            'host_avatar': h?['profile_pic'],
            'host_followers_count': h?['followers_count'] ?? 0,
            'host_id': h?['id'],
            'host': h,
          };
        })
        .where((item) => item != null)
        .cast<Map<String, dynamic>>()
        .toList();

    final currentIndex = historyContent.indexWhere((item) {
      final r = item['room'] as Map<String, dynamic>?;
      return r?['id'] == room.id;
    });

    _audio.setAutoplayQueue(queueData, currentIndex >= 0 ? currentIndex : 0);

    if (!isCurrentRoom) {
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

        await _audio.playRoom(roomData, fromUser: false);
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
    final title = room.title ?? 'audio';

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
                content: Text(
                  '$fileName download started. It will be stored in your device!',
                ),
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
        SnackBar(
          content: Text('Download started'),
          backgroundColor: const Color(0xFF7C3AED),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

  void _openFullPlayer() {
    if (_audio.currentRoom == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FullPlayerSheet(
        audio: _audio,
        currentUser: _authService.currentUser,
      ),
    );
  }
}

class _FullPlayerSheet extends StatefulWidget {
  final GlobalAudioService audio;
  final Map<String, dynamic>? currentUser;

  const _FullPlayerSheet({required this.audio, this.currentUser});

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

      _loadLikeStatus();
    }
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

  void _updateHostFollowersInRooms(int hostId, bool isFollowing) {
    final historyScreenState = context
        .findAncestorStateOfType<_HistoryScreenState>();

    if (historyScreenState != null) {
      historyScreenState.setState(() {
        for (var i = 0; i < historyScreenState.historyContent.length; i++) {
          final historyItem = historyScreenState.historyContent[i];
          final room = historyItem['room'] as Map<String, dynamic>?;

          if (room == null) continue;

          final roomHostId = room['host_id'] is int
              ? room['host_id']
              : int.tryParse(room['host_id']?.toString() ?? '');

          if (roomHostId == hostId) {
            final updatedHistoryItem = Map<String, dynamic>.from(historyItem);
            final updatedRoom = Map<String, dynamic>.from(room);

            final host = updatedRoom['host'] as Map<String, dynamic>?;
            if (host != null) {
              final currentFollowers = host['followers_count'] is int
                  ? host['followers_count']
                  : int.tryParse(host['followers_count']?.toString() ?? '0') ??
                        0;

              host['followers_count'] =
                  currentFollowers + (isFollowing ? 1 : -1);
            }

            final currentFlatFollowers =
                updatedRoom['host_followers_count'] is int
                ? updatedRoom['host_followers_count']
                : int.tryParse(
                        updatedRoom['host_followers_count']?.toString() ?? '0',
                      ) ??
                      0;

            updatedRoom['host_followers_count'] =
                currentFlatFollowers + (isFollowing ? 1 : -1);

            updatedHistoryItem['room'] = updatedRoom;
            historyScreenState.historyContent[i] = updatedHistoryItem;
          }
        }

        historyScreenState._groupHistoryByDate();
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

                                setState(() {
                                  followers = host['followers_count'];
                                });
                              }
                            }

                            _updateHostFollowersInRooms(hostId, isFollowing);
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

  const _FollowButton({required this.hostId, this.onFollowChanged});

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

  Future<void> _toggleFollow() async {
    setState(() => _isLoading = true);

    final result = await _followService.toggleFollow(widget.hostId);

    if (result != null && mounted) {
      final newFollowStatus = result['is_following'] ?? false;

      setState(() {
        _isFollowing = newFollowStatus;
        _isLoading = false;
      });

      if (widget.onFollowChanged != null) {
        widget.onFollowChanged!(widget.hostId, newFollowStatus);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFollowing ? 'Following user!' : 'Unfollowed user'),
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
            duration: Duration(seconds: 1),
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
