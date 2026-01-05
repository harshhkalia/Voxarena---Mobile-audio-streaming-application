import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../models/user_search_result.dart';
import '../models/room.dart';
import '../services/search_service.dart';
import '../services/queue_service.dart';
import '../widgets/user_card.dart';
import '../widgets/room_card.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/like_service.dart';
import '../services/follow_service.dart';
import '../widgets/comments_sheet.dart';
import 'profile_screen.dart';
import 'signup_screen.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/download_tracking_service.dart';
import '../services/room_report_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final _searchService = SearchService();
  final _authService = AuthService();
  final GlobalAudioService _audio = GlobalAudioService();

  late TabController _tabController;
  Timer? _debounceTimer;

  List<UserSearchResult> _searchedUsers = [];
  List<Room> _searchedRooms = [];
  bool _isSearching = false;
  bool _isLoading = false;
  String? _errorMessage;

  final _reportService = RoomReportService();
  final Map<int, bool> _reportedRooms = {};

  final Map<int, bool> _followStatusCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _audio.addListener(_onAudioChanged);
  }

  void _onAudioChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _debounceTimer?.cancel();
    _audio.removeListener(_onAudioChanged);
    super.dispose();
  }

  int? get _currentUserId {
    final id = _authService.currentUser?['id'];
    return id is int ? id : int.tryParse(id?.toString() ?? '');
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchedUsers = [];
        _searchedRooms = [];
        _isSearching = false;
        _errorMessage = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _errorMessage = 'Please enter at least 2 characters';
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _searchService.search(query, limit: 20);

      if (mounted) {
        setState(() {
          _searchedUsers = result.users;
          _searchedRooms = result.rooms;
          _isLoading = false;

          for (var user in _searchedUsers) {
            _followStatusCache[user.id] = user.isFollowing;
          }
        });

        if (_authService.isLoggedIn) {
          await _loadReportStatuses();
        }
      }
    } on SearchException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadReportStatuses() async {
    for (var room in _searchedRooms) {
      final status = await _reportService.checkReportStatus(room.id);

      if (status != null && mounted) {
        setState(() {
          _reportedRooms[room.id] = status['has_reported'] ?? false;
        });
      }
    }
  }

  void _updateFollowStatus(int userId, bool isFollowing) {
    setState(() {
      _followStatusCache[userId] = isFollowing;

      final index = _searchedUsers.indexWhere((u) => u.id == userId);
      if (index != -1) {
        _searchedUsers[index] = _searchedUsers[index].copyWith(
          isFollowing: isFollowing,
          followersCount:
              _searchedUsers[index].followersCount + (isFollowing ? 1 : -1),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A2E),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: const InputDecoration(
          hintText: 'Search users or rooms...',
          hintStyle: TextStyle(color: Colors.grey),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: const TextStyle(color: Colors.white, fontSize: 16),
        autofocus: true,
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _onSearchChanged('');
            },
          ),
      ],
      bottom: _isSearching && !_isLoading
          ? TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF7C3AED),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: 'Users (${_searchedUsers.length})'),
                Tab(text: 'Rooms (${_searchedRooms.length})'),
              ],
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorView();
    }

    if (_isSearching) {
      return TabBarView(
        controller: _tabController,
        children: [_buildUsersTab(), _buildRoomsTab()],
      );
    }

    return _buildRecentSearches();
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 18, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_searchController.text.isNotEmpty) {
                _performSearch(_searchController.text);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    final recentSearches = [
      'Gaming',
      'Tech Talk',
      'AI Revolution',
      'Music',
      'Business',
      'Python',
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Popular Searches',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        ...recentSearches.map((search) {
          return ListTile(
            leading: const Icon(Icons.search, color: Colors.grey),
            title: Text(search, style: const TextStyle(color: Colors.white)),
            onTap: () {
              _searchController.text = search;
              _performSearch(search);
            },
          );
        }),
      ],
    );
  }

  Widget _buildUsersTab() {
    if (_searchedUsers.isEmpty) {
      return _buildNoResults('No users found');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchedUsers.length,
      itemBuilder: (context, index) {
        final user = _searchedUsers[index];
        final isFollowing = _followStatusCache[user.id] ?? user.isFollowing;

        return UserCard(
          user: user,
          isFollowing: isFollowing,
          currentUserId: _currentUserId,
          onFollowChanged: (newStatus) {
            _updateFollowStatus(user.id, newStatus);
          },
        );
      },
    );
  }

  Widget _buildRoomsTab() {
    if (_searchedRooms.isEmpty) {
      return _buildNoResults('No rooms found');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchedRooms.length,
      itemBuilder: (context, index) {
        final room = _searchedRooms[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RoomCard(
            room: room,
            onTap: _authService.isLoggedIn
                ? () => _playRoom(room)
                : () => _showLoginPrompt(),
          ),
        );
      },
    );
  }

  void _showLoginPrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Please sign up to play audio'),
        backgroundColor: const Color(0xFF7C3AED),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Sign Up',
          textColor: Colors.white,
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SignUpScreen()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoResults(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 18, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching with different keywords',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
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
      final queueService = QueueService();

      final queueRooms = await queueService.fetchSmartQueue(
        currentRoomId: room.id,
        topic: room.topic,
        limit: 30,
      );

      final roomData = {
        'id': room.id,
        'title': room.title,
        'audio_url': room.audioUrl,
        'thumbnail_url': room.thumbnail,
        'topic': room.topic,
        'description': room.description,
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

      final queueData = queueRooms.map((r) {
        return {
          'id': r.id,
          'title': r.title,
          'audio_url': r.audioUrl,
          'thumbnail_url': r.thumbnail,
          'topic': r.topic,
          'description': r.description,
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

      final fullQueue = [roomData, ...queueData];

      final seen = <int>{};
      final deduplicatedQueue = <Map<String, dynamic>>[];
      for (final item in fullQueue) {
        final id = item['id'] as int?;
        if (id != null && !seen.contains(id)) {
          seen.add(id);
          deduplicatedQueue.add(item);
        }
      }

      if (deduplicatedQueue.isNotEmpty) {
        _audio.setAutoplayQueue(deduplicatedQueue, 0);
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
                    _audio.currentTitle ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
                      trackHeight: 2,
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

  final _reportService = RoomReportService();
  final Map<int, bool> _reportedRooms = {};

  List<Map<String, dynamic>> _queueItems = [];
  int _currentQueueIndex = 0;
  bool _isLoadingQueue = false;

  @override
  void initState() {
    super.initState();
    widget.audio.addListener(_onAudioChanged);

    if (widget.audio.currentRoom != null) {
      final roomId = widget.audio.currentRoom!['id'] as int?;
      _lastRoomId = roomId;

      final likes = widget.audio.currentRoom!['likes_count'] ?? 0;
      _likesCount = likes is int ? likes : int.tryParse(likes.toString()) ?? 0;

      final queue = widget.audio.autoplayQueue;
      final currentIndex = widget.audio.currentQueueIndex;

      if (queue.isNotEmpty) {
        _queueItems = queue;
        _currentQueueIndex = currentIndex >= 0 ? currentIndex : 0;
      }
    }

    _loadReportStatus();
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

    final queue = widget.audio.autoplayQueue;
    final currentIndex = widget.audio.currentQueueIndex;

    setState(() {
      _isLiked = false;
      _likesCount = currentRoom['likes_count'] is int
          ? currentRoom['likes_count']
          : 0;

      if (queue.isNotEmpty) {
        _queueItems = queue;
        _currentQueueIndex = currentIndex >= 0 ? currentIndex : 0;
      } else {
        _queueItems = [];
        _currentQueueIndex = 0;
      }
    });

    _loadLikeStatus();
    _loadReportStatus();
  }

  Future<void> _loadReportStatus() async {
    final roomId = widget.audio.currentRoom?['id'];
    if (roomId == null) return;

    final status = await _reportService.checkReportStatus(roomId);

    if (status != null && mounted) {
      setState(() {
        _reportedRooms[roomId] = status['has_reported'] ?? false;
      });
    }
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

  Future<void> _loadQueue() async {
    final currentQueue = widget.audio.autoplayQueue;
    if (currentQueue.isNotEmpty) {
      if (mounted) {
        setState(() {
          _queueItems = currentQueue;
          _currentQueueIndex = widget.audio.currentQueueIndex >= 0
              ? widget.audio.currentQueueIndex
              : 0;
        });
      }
      return;
    }

    final currentRoom = widget.audio.currentRoom;
    if (currentRoom == null) return;

    final roomId = currentRoom['id'] as int?;
    final topic = currentRoom['topic'] as String?;
    if (roomId == null || topic == null) return;

    try {
      setState(() {
        _isLoadingQueue = true;
      });

      final queueService = QueueService();
      final queueRooms = await queueService.fetchSmartQueue(
        currentRoomId: roomId,
        topic: topic,
        limit: 30,
      );

      final queueData = queueRooms.map((r) {
        return {
          'id': r.id,
          'title': r.title,
          'audio_url': r.audioUrl,
          'thumbnail_url': r.thumbnail,
          'topic': r.topic,
          'description': r.description,
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

      if (mounted) {
        setState(() {
          _queueItems = queueData;
          _currentQueueIndex = 0;
          _isLoadingQueue = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingQueue = false;
        });
      }
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

  Future<void> _handleReportRoom(int roomId, BuildContext rootContext) async {
    print('DEBUG: _handleReportRoom called with roomId: $roomId');

    if (widget.currentUser == null) {
      print('DEBUG: User not logged in');
      _showToast('Please log in to report rooms', bgColor: Colors.red);
      return;
    }

    if (_reportedRooms[roomId] == true) {
      print('DEBUG: Room already reported');
      if (!mounted) return;

      try {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          const SnackBar(
            content: Text('You have already reported this room'),
            backgroundColor: Colors.amber,
          ),
        );
      } catch (e) {
        print('DEBUG: ScaffoldMessenger failed, using toast: $e');
        _showToast(
          'You have already reported this room',
          bgColor: Colors.amber,
        );
      }
      return;
    }

    print('DEBUG: Showing report dialog');
    final reason = await _showReportDialog(rootContext);
    print('DEBUG: Report dialog returned: $reason');

    if (reason == null || !mounted) {
      print('DEBUG: Report cancelled or widget unmounted');
      return;
    }

    if (!rootContext.mounted) {
      print('DEBUG: Root context no longer mounted');
      return;
    }

    NavigatorState? navigator;
    ScaffoldMessengerState? scaffoldMessenger;

    try {
      navigator = Navigator.of(rootContext);
      scaffoldMessenger = ScaffoldMessenger.of(rootContext);
      print('DEBUG: Successfully got navigator and scaffoldMessenger');
    } catch (e) {
      print('DEBUG: Failed to get navigator/scaffoldMessenger: $e');
      _showToast(
        'Unable to report room. Please try again.',
        bgColor: Colors.red,
      );
      return;
    }

    bool isDialogShowing = true;
    navigator
        .push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black54,
            barrierDismissible: false,
            pageBuilder: (context, _, __) => PopScope(
              canPop: false,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                ),
              ),
            ),
          ),
        )
        .then((_) => isDialogShowing = false);

    try {
      print(
        'DEBUG: Calling reportRoom service with roomId: $roomId, reason: $reason',
      );
      final result = await _reportService.reportRoom(
        roomId: roomId,
        reason: reason,
      );
      print('DEBUG: Report service returned: $result');

      if (!mounted) return;

      if (isDialogShowing && navigator.canPop()) {
        try {
          navigator.pop();
          isDialogShowing = false;
        } catch (e) {
          // Ignore if navigation fails
        }
      }

      if (result != null && result['success'] == true) {
        final wasHidden = result['room_hidden'] == true;

        setState(() {
          _reportedRooms[roomId] = true;
        });

        if (!mounted) return;

        try {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                wasHidden
                    ? 'Room reported and hidden. Skipping to next audio...'
                    : 'Room reported successfully',
              ),
              backgroundColor: wasHidden ? Colors.red : const Color(0xFF7C3AED),
              duration: const Duration(seconds: 2),
            ),
          );
        } catch (e) {
          _showToast(
            wasHidden
                ? 'Room reported and hidden. Skipping to next audio...'
                : 'Room reported successfully',
            bgColor: wasHidden ? Colors.red : const Color(0xFF7C3AED),
          );
        }

        if (wasHidden) {
          if (_queueItems.isNotEmpty &&
              _currentQueueIndex < _queueItems.length - 1) {
            final nextIndex = _currentQueueIndex + 1;
            setState(() => _currentQueueIndex = nextIndex);

            if (!mounted) return;
            try {
              if (navigator.canPop()) {
                navigator.pop();
              }
            } catch (e) {
              // Ignore navigation errors
            }

            await Future.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;
            await widget.audio.playRoom(
              _queueItems[nextIndex],
              fromUser: false,
            );
          } else if (widget.audio.hasNext) {
            if (!mounted) return;
            try {
              if (navigator.canPop()) {
                navigator.pop();
              }
            } catch (e) {
              // Ignore navigation errors
            }
            await Future.delayed(const Duration(milliseconds: 500));
            if (!mounted) return;
            await widget.audio.skipToNext();
          } else {
            if (!mounted) return;
            // Close the full player sheet safely
            try {
              if (navigator.canPop()) {
                navigator.pop();
              }
            } catch (e) {
              // Ignore navigation errors
            }
            await widget.audio.player.stop();
            widget.audio.currentRoom = null;
            widget.audio.currentUrl = null;
            widget.audio.isPlaying = false;
          }
        }
      } else {
        if (!mounted) return;
        try {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(result?['error'] ?? 'Failed to report room'),
              backgroundColor: Colors.red,
            ),
          );
        } catch (e) {
          _showToast(
            result?['error'] ?? 'Failed to report room',
            bgColor: Colors.red,
          );
        }
      }
    } catch (e) {
      print('DEBUG: Exception in _handleReportRoom: $e');
      if (!mounted) return;

      if (isDialogShowing && navigator.canPop()) {
        try {
          navigator.pop();
          isDialogShowing = false;
        } catch (navError) {
          print('DEBUG: Navigation error: $navError');
        }
      }

      if (!mounted) return;
      try {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } catch (e) {
        print('DEBUG: ScaffoldMessenger error, using toast: $e');
        _showToast('Error: $e', bgColor: Colors.red);
      }
    }
  }

  Future<String?> _showReportDialog(BuildContext rootContext) async {
    print('DEBUG: _showReportDialog called');
    if (!rootContext.mounted) {
      print('DEBUG: rootContext not mounted');
      return null;
    }

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

    try {
      print('DEBUG: Showing dialog');
      final result = await showDialog<String>(
        context: rootContext,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                  onTap: () {
                    print('DEBUG: Selected reason: $reason');
                    Navigator.pop(dialogContext, reason);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('DEBUG: Report dialog cancelled');
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );
      print('DEBUG: Dialog result: $result');
      return result;
    } catch (e) {
      print('DEBUG: Dialog error: $e');
      return null;
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
                                if (_queueItems.isNotEmpty &&
                                    _currentQueueIndex > 0 &&
                                    widget.audio.position.inSeconds <= 3) {
                                  final prevIndex = _currentQueueIndex - 1;
                                  setState(
                                    () => _currentQueueIndex = prevIndex,
                                  );
                                  await widget.audio.playRoom(
                                    _queueItems[prevIndex],
                                    fromUser: false,
                                  );
                                } else {
                                  await widget.audio.skipToPrevious();
                                }
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
                                if (_queueItems.isNotEmpty &&
                                    _currentQueueIndex <
                                        _queueItems.length - 1) {
                                  final nextIndex = _currentQueueIndex + 1;
                                  setState(
                                    () => _currentQueueIndex = nextIndex,
                                  );
                                  await widget.audio.playRoom(
                                    _queueItems[nextIndex],
                                    fromUser: false,
                                  );
                                } else {
                                  await widget.audio.skipToNext();
                                }
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
                        onPressed: () {
                          _showRoomOptions(context, widget.audio.currentRoom!);
                        },
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (_queueItems.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Up Next',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 280,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _queueItems.length,
                            itemBuilder: (context, index) {
                              final queueItem = _queueItems[index];
                              final isCurrentlyPlaying =
                                  _currentQueueIndex == index;

                              return GestureDetector(
                                onTap: () async {
                                  if (_currentQueueIndex != index) {
                                    setState(() => _currentQueueIndex = index);
                                    await widget.audio.playRoom(
                                      queueItem,
                                      fromUser: false,
                                    );
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isCurrentlyPlaying
                                        ? const Color(
                                            0xFF7C3AED,
                                          ).withOpacity(0.2)
                                        : const Color(0xFF1A1A2E),
                                    borderRadius: BorderRadius.circular(12),
                                    border: isCurrentlyPlaying
                                        ? Border.all(
                                            color: const Color(0xFF7C3AED),
                                            width: 1,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          width: 50,
                                          height: 50,
                                          color: const Color(0xFF0F0F1E),
                                          child:
                                              (queueItem['thumbnail_url']
                                                          as String?)
                                                      ?.isNotEmpty ==
                                                  true
                                              ? Image.network(
                                                  queueItem['thumbnail_url'],
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(
                                                        Icons.audiotrack,
                                                        color: Color(
                                                          0xFF7C3AED,
                                                        ),
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.audiotrack,
                                                  color: Color(0xFF7C3AED),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (queueItem['title'] as String?) ??
                                                  'Untitled',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isCurrentlyPlaying
                                                    ? const Color(0xFF7C3AED)
                                                    : Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              (queueItem['host']?['full_name']
                                                      as String?) ??
                                                  'Unknown',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isCurrentlyPlaying)
                                        const Icon(
                                          Icons.play_circle_filled,
                                          color: Color(0xFF7C3AED),
                                          size: 24,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
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

  void _showRoomOptions(BuildContext context, Map<String, dynamic> room) {
    final roomId = room['id'] as int;

    int? currentUserId;
    if (widget.currentUser != null) {
      final userId = widget.currentUser!['id'];
      currentUserId = userId is int
          ? userId
          : int.tryParse(userId?.toString() ?? '');
    }

    int? hostId;
    final hostIdFromHost = room['host']?['id'];
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

    final bool isOwnAudio =
        hostId != null && currentUserId != null && hostId == currentUserId;

    // Store the original context for reporting
    final originalContext = context;

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
                    (room['title'] as String?) ?? 'Untitled',
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
                      widget.audio.isLooping &&
                      widget.audio.currentRoom != null &&
                      widget.audio.currentRoom!['id'] == room['id'],
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _handleLoop(room, sheetContext);
                    if (mounted) {
                      setModalState(() {});
                      setState(() {});
                    }
                  },
                ),

                _buildOption(
                  icon: Icons.download,
                  label: 'Download',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleDownload(room, originalContext);
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
                  label: 'Enable Autoplay Queue',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(originalContext).showSnackBar(
                      const SnackBar(
                        content: Text('Autoplay queue feature coming soon!'),
                        backgroundColor: Color(0xFF7C3AED),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),

                if (!isOwnAudio) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Colors.grey, height: 1),
                  const SizedBox(height: 10),
                  _buildOption(
                    icon: Icons.flag_outlined,
                    label: _reportedRooms[roomId] == true
                        ? 'Already Reported'
                        : 'Report Room',
                    iconColor: _reportedRooms[roomId] == true
                        ? Colors.amber
                        : Colors.red,
                    labelColor: _reportedRooms[roomId] == true
                        ? Colors.amber
                        : Colors.white,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _handleReportRoom(roomId, originalContext);
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

  Future<void> _handleDownload(
    Map<String, dynamic> room,
    BuildContext rootContext,
  ) async {
    final audioUrl = room['audio_url'] as String?;
    final title = room['title'] as String?;

    if (audioUrl == null || audioUrl.isEmpty) {
      _showToast('No audio URL found for this upload', bgColor: Colors.red);
      return;
    }

    final safeTitle = (title ?? 'audio').replaceAll(RegExp(r'[^\w\-]+'), '_');
    final fileName = '$safeTitle.mp3';

    try {
      if (Platform.isAndroid) {
        final hasPermission = await _ensureDownloadPermissions();
        if (!hasPermission) {
          _showToast('Permission required for download', bgColor: Colors.red);
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
              roomId: room['id'] as int,
              fileName: fileName,
              downloadPath: '$savedDir/$fileName',
            );

            _showToast(
              'Download started',
              bgColor: const Color(0xFF7C3AED),
              duration: const Duration(seconds: 4),
            );
          }
        } catch (e) {
          _showToast(
            'Failed to start download',
            bgColor: Colors.red,
            duration: const Duration(seconds: 4),
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
        roomId: room['id'] as int,
        fileName: fileName,
        downloadPath: '$savedDir/$fileName',
      );

      _showToast(
        'Download started',
        bgColor: const Color(0xFF7C3AED),
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      _showToast(
        'Download failed',
        bgColor: Colors.red,
        duration: const Duration(seconds: 4),
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

  Future<void> _handleLoop(
    Map<String, dynamic> room,
    BuildContext sheetContext,
  ) async {
    final wasLooping = widget.audio.isLooping;
    final isCurrentRoom =
        widget.audio.currentRoom != null &&
        widget.audio.currentRoom!['id'] == room['id'];

    await widget.audio.toggleLoop();

    if (!wasLooping && widget.audio.isLooping && !isCurrentRoom) {
      try {
        await widget.audio.playRoom(room, fromUser: false);
      } catch (e) {
        if (mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _showToast('Error playing audio', bgColor: Colors.red);
            }
          });
        }
      }
    }

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _showToast(
            widget.audio.isLooping ? 'Loop enabled' : 'Loop disabled',
            bgColor: const Color(0xFF7C3AED),
          );
        }
      });
    }
  }

  void _showRoomDescription(Map<String, dynamic> room) {
    final title = room['title'] as String? ?? 'Unknown';
    final description =
        room['description'] != null &&
            (room['description'] as String?)?.trim().isNotEmpty == true
        ? (room['description'] as String?)!.trim()
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
            title,
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

  void _showToast(
    String message, {
    Color bgColor = const Color(0xFF7C3AED),
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        right: 16,
        child: _ToastNotification(
          message: message,
          bgColor: bgColor,
          onDismiss: () {
            overlayEntry.remove();
          },
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(duration, () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}

class _ToastNotification extends StatefulWidget {
  final String message;
  final Color bgColor;
  final VoidCallback onDismiss;

  const _ToastNotification({
    required this.message,
    required this.bgColor,
    required this.onDismiss,
  });

  @override
  State<_ToastNotification> createState() => _ToastNotificationState();
}

class _ToastNotificationState extends State<_ToastNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.bgColor == Colors.red
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
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
