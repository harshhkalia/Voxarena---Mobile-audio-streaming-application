import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app/screens/following_screen.dart';
import 'package:app/services/audio_service.dart';
import 'package:app/services/follow_service.dart';
import 'package:app/services/like_service.dart';
import 'package:app/widgets/comments_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/room.dart';
import '../widgets/room_card.dart';
import '../services/auth_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'search_screen.dart';
import 'create_screen.dart';
import 'signup_screen.dart';
import 'profile_screen.dart';
import 'history_screen.dart';
import 'download_history_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app/widgets/hidden_users_modal.dart';
import '../config/api_config.dart';
import 'package:http/http.dart' as http;
import '../services/download_tracking_service.dart';
import '../services/room_report_service.dart';
import '../services/notification_service.dart';
import '../services/websocket_service.dart';
import '../models/app_notification.dart';
import 'notifications_screen.dart';

class GuestHomeScreen extends StatefulWidget {
  const GuestHomeScreen({super.key});

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> {
  final _authService = AuthService();
  final _storage = const FlutterSecureStorage();
  final GlobalAudioService _audio = GlobalAudioService();

  List<Room> recordedContent = [];
  bool isLoading = false;
  bool isRefreshingProfile = false;
  String? _cachedProfilePicUrl;

  int _page = 1;
  final int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final _reportService = RoomReportService();
  final _notificationService = NotificationService();
  final Map<int, bool> _reportedRooms = {};
  int _unreadNotificationCount = 0;

  final ScrollController _discoverScrollController = ScrollController();

  String _selectedTopic = 'All';

  final _webSocketService = WebSocketService();
  StreamSubscription<AppNotification>? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _cachedProfilePicUrl = _authService.currentUser?['profile_pic'];
    _discoverScrollController.addListener(_onDiscoverScroll);
    _loadContent(reset: true);
    _loadUnreadNotificationCount();

    _audio.addListener(_onAudioChanged);
    _initWebSocket();
  }

  void _onAudioChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _discoverScrollController.dispose();
    _audio.removeListener(_onAudioChanged);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _initWebSocket() {
    if (!_authService.isLoggedIn) return;

    _webSocketService.connect();

    _notificationSubscription = _webSocketService.notificationStream.listen(
      (notification) {
        if (mounted) {
          setState(() {
            _unreadNotificationCount++;
          });

          _showNotificationSnackbar(notification);
        }
      },
    );
  }

  void _showNotificationSnackbar(AppNotification notification) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF1A1A2E),
              backgroundImage: notification.actor?.profilePic != null
                  ? NetworkImage(notification.actor!.profilePic!)
                  : null,
              child: notification.actor?.profilePic == null
                  ? const Icon(Icons.person, color: Colors.white54, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notification.message != null)
                    Text(
                      notification.message!,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          textColor: const Color(0xFF7C3AED),
          onPressed: _openNotifications,
        ),
      ),
    );
  }

  Future<void> _loadContent({bool reset = false}) async {
    if (reset) {
      setState(() {
        isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _page = 1;
        recordedContent = [];
      });
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');

      final token = await _storage.read(key: 'jwt_token');
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/discovery'
      //   '?topic=$_selectedTopic&page=$_page&limit=$_pageSize',
      // );

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/discovery'
        '?topic=$_selectedTopic&page=$_page&limit=$_pageSize',
      );

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final roomsList = data['rooms'] as List;

        final fetched = roomsList.map((json) {
          return Room.fromJson(json as Map<String, dynamic>);
        }).toList();

        setState(() {
          if (reset) {
            recordedContent = fetched;
          } else {
            recordedContent.addAll(fetched);
          }

          if (data is Map && data['has_more'] != null) {
            _hasMore = data['has_more'] == true;
          } else {
            _hasMore = fetched.length == _pageSize;
          }

          _page += 1;
          isLoading = false;
          _isLoadingMore = false;
        });

        if (_authService.isLoggedIn) {
          await _loadReportStatuses();
          await _loadUnreadNotificationCount();
        }
      } else {
        throw Exception('Failed to load content');
      }
    } catch (e) {
      print('Error loading content: $e');
      setState(() {
        if (reset) {
          recordedContent = Room.getDummyRecordedContent();
        }
        isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
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
            recordedContent.removeAt(index);
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

  Future<void> _loadUnreadNotificationCount() async {
    if (!_authService.isLoggedIn) return;
    
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() {
        _unreadNotificationCount = count;
      });
    }
  }

  void _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationsScreen()),
    );
    _loadUnreadNotificationCount();
  }

  Future<void> _loadReportStatuses() async {
    for (var room in recordedContent) {
      final roomId = room.id;
      final status = await _reportService.checkReportStatus(roomId);

      if (status != null && mounted) {
        setState(() {
          _reportedRooms[roomId] = status['has_reported'] ?? false;
        });
      }
    }
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen()),
    );
  }

  void _openCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateScreen()),
    );
  }

  void _onDiscoverScroll() {
    if (!_hasMore || _isLoadingMore || isLoading) return;

    final pos = _discoverScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadContent(reset: false);
    }
  }

  Future<void> _openSignUp() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignUpScreen()),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _showSignOutDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'We will sign you out. Are you sure?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.signOut();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed out successfully')),
        );
      }
    }
  }

  void _showAccountModal() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF5A2FA8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      backgroundImage:
                          (_authService.currentUser?['profile_pic'] != null &&
                              (_authService.currentUser?['profile_pic']
                                          as String?)
                                      ?.isNotEmpty ==
                                  true)
                          ? NetworkImage(
                              _authService.currentUser!['profile_pic']
                                  as String,
                            )
                          : null,
                      child:
                          (_authService.currentUser?['profile_pic'] == null ||
                              (_authService.currentUser?['profile_pic']
                                          as String?)
                                      ?.isEmpty ==
                                  true)
                          ? const Icon(
                              Icons.account_circle,
                              color: Colors.white,
                              size: 28,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _authService.currentUser?['full_name'] ?? 'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _authService.currentUser?['email'] ?? '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2A2A3E), height: 1),
              _buildModalMenuItem(
                icon: Icons.person,
                label: 'Profile',
                color: const Color(0xFF7C3AED),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
              ),
              _buildModalMenuItem(
                icon: Icons.history,
                label: 'History',
                color: const Color.fromARGB(255, 20, 176, 20),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HistoryScreen(),
                    ),
                  );
                },
              ),
              _buildModalMenuItem(
                icon: Icons.new_releases,
                label: 'Following',
                color: const Color.fromARGB(255, 20, 142, 176),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FollowingScreen(),
                    ),
                  );
                },
              ),
              _buildModalMenuItem(
                icon: Icons.download,
                label: 'Download History',
                color: const Color(0xFF7C3AED),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DownloadHistoryScreen(),
                    ),
                  );
                },
              ),
              _buildModalMenuItem(
                icon: Icons.visibility_off,
                label: 'Hidden Users',
                color: const Color.fromARGB(255, 176, 156, 20),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const HiddenUsersModal(),
                  );
                },
              ),
              const Divider(color: Color(0xFF2A2A3E), height: 1),
              _buildModalMenuItem(
                icon: Icons.logout,
                label: 'Sign Out',
                color: Colors.red,
                isDestructive: true,
                onTap: () {
                  Navigator.pop(context);
                  _showSignOutDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalMenuItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isDestructive ? Colors.red : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.withOpacity(0.5),
              size: 20,
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
        title: const Row(
          children: [
            SizedBox(width: 8),
            Text(
              'VoxArena',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _openSearch, icon: const Icon(Icons.search)),
          if (_authService.isLoggedIn)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: _openNotifications,
                ),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEB5757),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        _unreadNotificationCount > 99 ? '99+' : '$_unreadNotificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          if (_authService.isLoggedIn)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_circle,
                  color: Color(0xFF7C3AED),
                  size: 24,
                ),
              ),
              onPressed: _showAccountModal,
            )
          else
            TextButton(
              onPressed: _openSignUp,
              child: const Text(
                'Sign Up',
                style: TextStyle(
                  color: Color(0xFF7C3AED),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildDiscoverTab(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: const Color(0xFF7C3AED),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

  Widget _buildDiscoverTab() {
    return RefreshIndicator(
      onRefresh: () => _loadContent(reset: true),
      child: ListView.builder(
        controller: _discoverScrollController,
        padding: const EdgeInsets.symmetric(vertical: 0),
        itemCount: _calculateDiscoverItemCount(),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hey ${_authService.currentUser?['full_name']?.split(' ')[0] ?? 'there'}! 👋',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Discover amazing audio content',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withOpacity(0.1),
                      border: Border.all(
                        color: const Color(0xFF7C3AED).withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🎵 ${recordedContent.isEmpty ? 'Browse' : 'Explore'} ${recordedContent.length} ${recordedContent.length == 1 ? 'audio' : 'audios'}',
                      style: const TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          if (index == 1) {
            return SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  _buildTopicChip('All'),
                  _buildTopicChip('Technology'),
                  _buildTopicChip('Business'),
                  _buildTopicChip('Gaming'),
                  _buildTopicChip('Music'),
                  _buildTopicChip('Education'),
                  _buildTopicChip('Health'),
                  _buildTopicChip('Entertainment'),
                ],
              ),
            );
          }

          if (index == 2) {
            if (isLoading && recordedContent.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return const SizedBox(height: 8);
          }

          final roomIndex = index - 3;

          if (recordedContent.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(50),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.audiotrack,
                      size: 64,
                      color: Colors.grey.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No audio found',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Try exploring other topics',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }

          if (roomIndex < recordedContent.length) {
            final room = recordedContent[roomIndex];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: RoomCard(
                room: room,
                onTap: _authService.isLoggedIn
                    ? () => _playRoom(room)
                    : _openSignUp,
                onLongPress: _authService.isLoggedIn
                    ? () => _showRoomOptions(context, room, roomIndex)
                    : null,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _isLoadingMore
                  ? const CircularProgressIndicator()
                  : const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

  int _calculateDiscoverItemCount() {
    if (recordedContent.isEmpty) {
      return 4;
    }
    return 3 + recordedContent.length + 1;
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

      final queueData = recordedContent.map((r) {
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

      final currentIndex = recordedContent.indexWhere((r) => r.id == room.id);

      if (currentIndex >= 0 && _audio.isAutoplayEnabled) {
        _audio.setAutoplayQueue(queueData, currentIndex);
      }

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

  Widget _buildTopicChip(String label) {
    final isSelected = label == _selectedTopic;

    final Map<String, Map<String, dynamic>> topicMeta = {
      'All': {'icon': Icons.grid_view, 'color': const Color(0xFF7C3AED)},
      'Technology': {'icon': Icons.memory, 'color': const Color(0xFF5B8CFF)},
      'Business': {
        'icon': Icons.work_outline,
        'color': const Color(0xFF00C2A8),
      },
      'Gaming': {
        'icon': Icons.videogame_asset,
        'color': const Color(0xFFEF6CFF),
      },
      'Music': {'icon': Icons.music_note, 'color': const Color(0xFF00D4FF)},
      'Education': {'icon': Icons.school, 'color': const Color(0xFFFFC857)},
      'Health': {
        'icon': Icons.favorite_border,
        'color': const Color(0xFFFF6B6B),
      },
      'Entertainment': {
        'icon': Icons.movie_outlined,
        'color': const Color(0xFF8E6FFF),
      },
    };

    final meta =
        topicMeta[label] ??
        {'icon': Icons.label, 'color': const Color(0xFF7C3AED)};
    final Color accent = meta['color'] as Color;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          if (!isSelected) {
            setState(() {
              _selectedTopic = label;
            });
            _loadContent(reset: true);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [accent.withOpacity(0.95), accent.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? accent.withOpacity(0.9) : Colors.white10,
              width: isSelected ? 0 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                meta['icon'] as IconData,
                size: 16,
                color: isSelected ? Colors.white : accent.withOpacity(0.95),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
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

                if (!isOwnRoom && _authService.isLoggedIn)
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

  Future<void> _handleLoop(Room room) async {
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

    final queueData = recordedContent.map((r) {
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

  void _updateHostFollowersInRooms(int hostId, bool isFollowing) {
    final homeScreenState = context
        .findAncestorStateOfType<_GuestHomeScreenState>();
    if (homeScreenState != null) {
      homeScreenState.setState(() {
        for (var i = 0; i < homeScreenState.recordedContent.length; i++) {
          if (homeScreenState.recordedContent[i].hostId == hostId) {
            homeScreenState.recordedContent[i] = homeScreenState
                .recordedContent[i]
                .copyWith(
                  hostFollowersCount:
                      homeScreenState.recordedContent[i].hostFollowersCount +
                      (isFollowing ? 1 : -1),
                );
          }
        }
      });
    }
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
