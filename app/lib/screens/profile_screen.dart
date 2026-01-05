import 'package:app/services/audio_service.dart';
import 'package:app/services/follow_service.dart';
import 'package:app/services/like_service.dart';
import 'package:app/widgets/comments_sheet.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'edit_profile_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'edit_room_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import '../services/auth_service.dart';
import 'package:app/widgets/followers_modal.dart';
import '../config/api_config.dart';
import '../services/hide_service.dart';
import '../services/download_tracking_service.dart';
import 'create_community_post_screen.dart';
import 'package:app/widgets/community_comments_sheet.dart';
import '../services/communitypost_service.dart';
import 'edit_community_post_screen.dart';
import '../services/room_report_service.dart';

class ProfileScreen extends StatefulWidget {
  final int? userId;
  final int? scrollToRoomId;
  final int? scrollToPostId;

  const ProfileScreen({
    super.key,
    this.userId,
    this.scrollToRoomId,
    this.scrollToPostId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _pageScrollController = ScrollController();
  final _storage = const FlutterSecureStorage();
  Map<String, dynamic>? userData;
  List<dynamic> userRooms = [];
  bool isLoading = true;
  bool isLoadingRooms = true;
  bool isOwnProfile = false;
  bool isFollowing = false;
  int _roomsPage = 1;
  final int _roomsLimit = 20;
  bool _isLoadingMoreRooms = false;
  bool _hasMoreRooms = true;
  bool _hasScrolledToTargetRoom = false;
  final Map<int, GlobalKey> _roomKeys = {};
  bool _hasScrolledToTargetPost = false;
  final Map<int, GlobalKey> _postKeys = {};
  final Map<int, bool> _followStatusCache = {};
  final Map<int, int> _followersCountCache = {};
  final _followService = FollowService();

  bool _lastAudioPlayingState = false;
  String? _lastAudioUrl;
  bool _lastLoopingState = false;
  bool _lastAutoplayState = false;

  final _hideService = HideService();
  bool _isUserHidden = false;
  bool _isCheckingHideStatus = true;

  final _authService = AuthService();
  final GlobalAudioService _audio = GlobalAudioService();

  int? _currentlyPlayingIndex;

  final _communityService = CommunityService();
  List<Map<String, dynamic>> _communityPosts = [];
  bool _isLoadingPosts = false;

  bool _isLoadingCommunityPosts = false;
  bool _hasCommunityPostsError = false;

  final _reportService = RoomReportService();
  final Map<int, bool> _reportedRooms = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.scrollToPostId != null ? 1 : 0,
    );
    _loadProfile();
    _loadUserRooms(reset: true);
    _loadHideStatus();
    _loadCommunityPosts();
    _scrollController.addListener(_onRoomsScroll);

    // _audio.addListener(_onAudioChanged);

    _lastAudioPlayingState = _audio.isPlaying;
    _lastAudioUrl = _audio.currentUrl;
    _lastLoopingState = _audio.isLooping;
    _lastAutoplayState = _audio.isAutoplayEnabled;
  }

  // void _onAudioChanged() {
  //   if (!mounted) return;
  //   setState(() {});
  // }

  void _onRoomsScroll() {
    if (!_hasMoreRooms || _isLoadingMoreRooms || isLoadingRooms) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadUserRooms(reset: false);
    }
  }

  @override
  void dispose() {
    // _audio.removeListener(_onAudioChanged);
    _tabController.dispose();
    super.dispose();
    _scrollController.dispose();
    _pageScrollController.dispose();
  }

  Future<void> _checkIfOwnProfile() async {
    if (widget.userId == null) {
      setState(() => isOwnProfile = true);
      return;
    }

    final currentUser = _authService.currentUser;
    final currentUserId = currentUser?['id'];

    setState(() {
      isOwnProfile = (currentUserId == widget.userId);
    });

    if (widget.userId != null) {
      _followStatusCache[widget.userId!] = isFollowing;
      _followersCountCache[widget.userId!] = userData?['followers_count'] ?? 0;
    }
  }

  Future<void> _loadReportStatuses() async {
    if (isOwnProfile) return;

    for (var room in userRooms) {
      final roomId = room['id'] as int;
      final status = await _reportService.checkReportStatus(roomId);

      if (status != null && mounted) {
        setState(() {
          _reportedRooms[roomId] = status['has_reported'] ?? false;
        });
      }
    }
  }

  Future<void> _loadCommunityPosts() async {
    if (_isLoadingCommunityPosts) return;

    setState(() {
      _isLoadingCommunityPosts = true;
      _hasCommunityPostsError = false;
    });

    try {
      final result = await _communityService.getUserCommunityPosts(
        widget.userId ?? _authService.currentUser?['id'],
      );

      if (result != null && mounted) {
        setState(() {
          _communityPosts = List<Map<String, dynamic>>.from(
            result['posts'] ?? [],
          );
          _isLoadingCommunityPosts = false;
        });

        if (widget.scrollToPostId != null && !_hasScrolledToTargetPost) {
          final index = _communityPosts.indexWhere(
            (p) => p['id'] == widget.scrollToPostId,
          );

          if (index != -1) {
            _hasScrolledToTargetPost = true;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scrollToTargetPost();
              }
            });
          }
        }
      } else {
        setState(() {
          _hasCommunityPostsError = true;
          _isLoadingCommunityPosts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasCommunityPostsError = true;
          _isLoadingCommunityPosts = false;
        });
      }
    }
  }

  Future<void> _loadHideStatus() async {
    if (widget.userId == null || isOwnProfile) {
      setState(() => _isCheckingHideStatus = false);
      return;
    }

    try {
      final isHidden = await _hideService.checkHideStatus(widget.userId!);
      if (!mounted) return;

      setState(() {
        _isUserHidden = isHidden;
        _isCheckingHideStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCheckingHideStatus = false);
    }
  }

  Future<void> _loadFollowStatus() async {
    if (widget.userId == null) return;

    try {
      final isFollowingResult = await _followService.checkFollowStatus(
        widget.userId!,
      );

      if (!mounted) return;

      setState(() {
        isFollowing = isFollowingResult;
      });
    } catch (_) {}
  }

  void _updateFollowStatus(
    int userId,
    bool isFollowingUser,
    int followersCount,
  ) {
    if (userId == widget.userId) {
      setState(() {
        isFollowing = isFollowingUser;
        if (userData != null) {
          userData!['followers_count'] = followersCount;
        }
      });
    }

    _followStatusCache[userId] = isFollowingUser;
    _followersCountCache[userId] = followersCount;

    for (var i = 0; i < userRooms.length; i++) {
      final room = userRooms[i] as Map<String, dynamic>;
      final roomHostId = room['host_id'] is int
          ? room['host_id']
          : int.tryParse(room['host_id']?.toString() ?? '');

      if (roomHostId == userId) {
        final updatedRoom = Map<String, dynamic>.from(room);

        final host = updatedRoom['host'] as Map<String, dynamic>?;
        if (host != null) {
          host['followers_count'] = followersCount;
        }

        updatedRoom['host_followers_count'] = followersCount;

        userRooms[i] = updatedRoom;
      }
    }
  }

  Future<File?> _downloadToAndroidDownloads({
    required String url,
    required String fileName,
  }) async {
    try {
      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir == null) {
        debugPrint('Downloads directory is null');
        return null;
      }

      final savePath = '${downloadsDir.path}/$fileName';
      debugPrint('Saving to: $savePath');

      final dio = Dio();
      await dio.download(url, savePath);

      return File(savePath);
    } catch (e) {
      debugPrint('Download error: $e');
      return null;
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

  void _scrollToTargetRoom() {
    final roomId = widget.scrollToRoomId;
    if (roomId == null) return;

    final key = _roomKeys[roomId];
    if (key == null) return;

    final context = key.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  void _scrollToTargetPost() {
    final postId = widget.scrollToPostId;
    if (postId == null) return;

    final key = _postKeys[postId];
    if (key == null) return;

    final context = key.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  Future<void> _toggleHideUser() async {
    if (widget.userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _isUserHidden
              ? 'Show your content to this user?'
              : 'Hide your content from this user?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          _isUserHidden
              ? 'This user will be able to see your profile and content again.'
              : 'This user won\'t be able to see your profile or any of your content. They won\'t be notified.',
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _isUserHidden ? 'Show Content' : 'Hide Content',
              style: const TextStyle(color: Color(0xFF7C3AED)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final previousStatus = _isUserHidden;

    setState(() {
      _isUserHidden = !previousStatus;
    });

    try {
      final result = await _hideService.toggleHideUser(widget.userId!);

      if (result == null) {
        if (!mounted) return;
        setState(() {
          _isUserHidden = previousStatus;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _isUserHidden = result['is_hidden'] ?? _isUserHidden;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isUserHidden
                ? 'Your content is now hidden from this user'
                : 'This user can now see your content',
          ),
          backgroundColor: const Color(0xFF7C3AED),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUserHidden = previousStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadProfile() async {
    setState(() => isLoading = true);

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      final endpoint = widget.userId == null
          ? '/api/v1/profile'
          : '/api/v1/users/${widget.userId}';

      // final url = Uri.parse('http://$serverIP:$serverPort$endpoint');
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          userData = data['user'];
          isLoading = false;
          isFollowing = data['is_following'] ?? false;
        });

        await _checkIfOwnProfile();
        await _loadFollowStatus();
      } else if (response.statusCode == 403) {
        setState(() => isLoading = false);

        if (!mounted) return;

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Content Not Available',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: const Text(
              'This profile is not available to you.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'OK',
                  style: TextStyle(color: Color(0xFF7C3AED)),
                ),
              ),
            ],
          ),
        );

        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        throw Exception('Failed to load profile');
      }
    } catch (e) {
      setState(() => isLoading = false);

      if (!mounted) return;

      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(
      //     content: Text('Error loading profile: $e'),
      //     backgroundColor: Colors.red,
      //   ),
      // );
    }
  }

  Future<void> _loadUserRooms({bool reset = false}) async {
    if (reset) {
      setState(() {
        _roomsPage = 1;
        _hasMoreRooms = true;
        _hasScrolledToTargetRoom = false;
        userRooms = [];
        isLoadingRooms = true;
      });
    } else {
      if (!_hasMoreRooms || _isLoadingMoreRooms) return;
      setState(() {
        _isLoadingMoreRooms = true;
      });
    }

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      final endpoint = widget.userId == null
          ? '/api/v1/my-rooms'
          : '/api/v1/users/${widget.userId}/rooms';

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort$endpoint'
      //   '?page=$_roomsPage&limit=$_roomsLimit',
      // );

      final url = Uri.parse(
        '${ApiConfig.baseUrl}$endpoint'
        '?page=$_roomsPage&limit=$_roomsLimit',
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
        final List<dynamic> fetched = data['rooms'] ?? [];

        setState(() {
          userRooms.addAll(fetched);
          _hasMoreRooms = data['has_more'] == true;
          _roomsPage += 1;
          isLoadingRooms = false;
          _isLoadingMoreRooms = false;
        });

        if (!isOwnProfile) {
          await _loadReportStatuses();
        }

        if (widget.scrollToRoomId != null && !_hasScrolledToTargetRoom) {
          final index = userRooms.indexWhere(
            (r) => r['id'] == widget.scrollToRoomId,
          );

          if (index != -1) {
            _hasScrolledToTargetRoom = true;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scrollToTargetRoom();
              }
            });
          }
        }
      } else {
        throw Exception('Failed to load rooms');
      }
    } catch (e) {
      setState(() {
        isLoadingRooms = false;
        _isLoadingMoreRooms = false;
        _hasMoreRooms = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (widget.userId == null) return;

    final previousIsFollowing = isFollowing;
    final previousFollowers = userData!['followers_count'] ?? 0;

    setState(() {
      isFollowing = !previousIsFollowing;
      userData!['followers_count'] = previousIsFollowing
          ? previousFollowers - 1
          : previousFollowers + 1;
    });

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('No auth token');

      // final response = await http.post(
      //   Uri.parse(
      //     'http://$serverIP:$serverPort/api/v1/users/${widget.userId}/follow',
      //   ),
      //   headers: {
      //     'Content-Type': 'application/json',
      //     'Authorization': 'Bearer $token',
      //   },
      // );

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/users/${widget.userId}/follow',
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

        setState(() {
          isFollowing = data['is_following'] ?? isFollowing;
          userData!['followers_count'] =
              data['followers_count'] ?? userData!['followers_count'];
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFollowing
                  ? 'Following ${userData!['username']}'
                  : 'Unfollowed ${userData!['username']}',
            ),
            backgroundColor: const Color(0xFF7C3AED),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        throw Exception('Server rejected follow toggle');
      }
    } catch (e) {
      setState(() {
        isFollowing = previousIsFollowing;
        userData!['followers_count'] = previousFollowers;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update follow status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleReportRoom(int roomId, int index) async {
    if (_reportedRooms[roomId] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already reported this room'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final reason = await _showReportDialog();
    if (reason == null || !mounted) return;

    // Store the navigator and scaffold messenger to avoid context issues
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show loading
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
        roomId: roomId,
        reason: reason,
      );

      if (!mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }

      if (result != null && result['success'] == true) {
        final wasHidden = result['room_hidden'] == true;

        setState(() {
          _reportedRooms[roomId] = true;

          if (wasHidden) {
            userRooms.removeAt(index);
          }
        });

        scaffoldMessenger.showSnackBar(
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
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(result?['error'] ?? 'Failed to report room'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }

      scaffoldMessenger.showSnackBar(
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

  void _showProfilePicture() {
    if (userData!['profile_pic'] == null ||
        userData!['profile_pic'].toString().isEmpty) {
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black,
      useSafeArea: false,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(50),
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.network(
                  userData!['profile_pic'],
                  fit: BoxFit.contain,
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null,
                        color: const Color(0xFF7C3AED),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 80,
                            color: Colors.red,
                          ),
                          SizedBox(height: 20),
                          Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFollowersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FollowersModal(
        userId: widget.userId ?? _authService.currentUser?['id'],
        isOwnProfile: isOwnProfile,
        onFollowerRemoved: () async {
          await _loadProfile();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Profile'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (userData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text('Profile'),
        ),
        body: const Center(child: Text('Failed to load profile')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Profile'),
        actions: isOwnProfile
            ? [
                IconButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EditProfileScreen(userData: userData!),
                      ),
                    );
                    if (result == true) {
                      await _loadProfile();
                      await _loadUserRooms(reset: true);
                    }
                  },
                  icon: const Icon(Icons.edit),
                ),
              ]
            : [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  color: const Color(0xFF1A1A2E),
                  onSelected: (value) {
                    if (value == 'hide') {
                      _toggleHideUser();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'hide',
                      child: Row(
                        children: [
                          Icon(
                            _isUserHidden
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isUserHidden
                                ? 'Show My Content to Them'
                                : 'Hide My Content from Them',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadProfile();
          await _loadUserRooms(reset: true);
        },
        child: SingleChildScrollView(
          controller: _pageScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF0F0F1E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _showProfilePicture,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF7C3AED),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child:
                              userData!['profile_pic'] != null &&
                                  userData!['profile_pic'].toString().isNotEmpty
                              ? Image.network(
                                  userData!['profile_pic'],
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null)
                                          return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
                                            color: const Color(0xFF7C3AED),
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.grey,
                                      ),
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.grey,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      userData!['full_name'] ?? 'No name',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '@${userData!['username'] ?? 'username'}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        if (userData!['is_verified'] == true) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            size: 18,
                            color: Color(0xFF7C3AED),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (userData!['bio'] != null &&
                        userData!['bio'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          userData!['bio'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    GestureDetector(
                      onTap: _showFollowersModal,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF7C3AED).withOpacity(0.3),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isOwnProfile ? 'Your' : 'Their',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[400],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Followers',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            Container(
                              width: 2,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF7C3AED).withOpacity(0.2),
                                    const Color(0xFF7C3AED),
                                    const Color(0xFF7C3AED).withOpacity(0.2),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Text(
                              '${userData!['followers_count'] ?? 0}',
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF7C3AED),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (isOwnProfile)
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditProfileScreen(userData: userData!),
                            ),
                          );
                          if (result == true) {
                            await _loadProfile();
                            await _loadUserRooms(reset: true);
                          }
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _toggleFollow,
                        icon: Icon(
                          isFollowing ? Icons.person_remove : Icons.person_add,
                        ),
                        label: Text(isFollowing ? 'Following' : 'Follow'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFollowing
                              ? const Color(0xFF1A1A2E)
                              : const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          side: isFollowing
                              ? const BorderSide(color: Color(0xFF7C3AED))
                              : null,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF7C3AED),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey,
                    tabs: const [
                      Tab(text: '🎵 Uploads'),
                      Tab(text: '📝 Community'),
                    ],
                  ),
                  SizedBox(
                    height: 400,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildUploadsTab(),
                        _buildCommunityPostsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildMiniPlayer(),
      floatingActionButton: isOwnProfile
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateCommunityPostScreen(),
                  ),
                );
                if (result == true) {
                  await _loadCommunityPosts();
                }
              },
              backgroundColor: const Color(0xFF7C3AED),
              icon: const Icon(Icons.add),
              label: const Text('New Post'),
            )
          : null,
    );
  }

  void _applyLikeChange({
    required int roomId,
    required bool isLiked,
    required int likesCount,
  }) {
    setState(() {
      final idx = userRooms.indexWhere((r) => r['id'] == roomId);
      if (idx != -1) {
        final updated = Map<String, dynamic>.from(userRooms[idx]);
        updated['likes_count'] = likesCount;
        userRooms[idx] = updated;
      }

      if (_audio.currentRoom != null && _audio.currentRoom!['id'] == roomId) {
        _audio.currentRoom!['likes_count'] = likesCount;
      }
    });
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  Widget _buildUploadsTab() {
    if (isLoadingRooms) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
        ),
      );
    }

    if (userRooms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.audiotrack, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No uploads yet',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Start creating content!',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: userRooms.length,
      itemBuilder: (context, index) {
        final room = userRooms[index] as Map<String, dynamic>;
        final duration = (room['duration'] ?? 0) as int;
        final minutes = duration ~/ 60;
        final seconds = duration % 60;
        final thumbUrl = room['thumbnail_url'] as String?;
        final title = room['title'] as String? ?? 'Untitled';
        final topic = room['topic'] as String? ?? '';
        final isPrivate = room['is_private'] ?? false;
        final likesCount = room['likes_count'] ?? 0;
        final totalListens = room['total_listens'] ?? 0;
        final roomId = room['id'] as int;

        final isCurrentRoom =
            _audio.currentRoom != null &&
            _audio.currentRoom!['audio_url'] == room['audio_url'];

        _roomKeys.putIfAbsent(roomId, () => GlobalKey());

        return GestureDetector(
          key: _roomKeys[roomId],
          onLongPress: () => _showRoomOptions(context, room, index),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrentRoom
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF7C3AED).withOpacity(0.3),
                width: isCurrentRoom ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: const Color(0xFF7C3AED).withOpacity(0.2),
                            ),
                            child: (thumbUrl != null && thumbUrl.isNotEmpty)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      thumbUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
                                                Icons.audiotrack,
                                                color: Color(0xFF7C3AED),
                                              ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.audiotrack,
                                    color: Color(0xFF7C3AED),
                                  ),
                          ),
                          if (isPrivate)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.only(
                                    topRight: Radius.circular(8),
                                    bottomLeft: Radius.circular(8),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.lock,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),

                            Text(
                              topic,
                              style: const TextStyle(
                                color: Color(0xFF7C3AED),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),

                            Row(
                              children: [
                                const Icon(
                                  Icons.timer,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                if (isPrivate)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.amber,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.lock,
                                          size: 10,
                                          color: Colors.amber,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          'Private',
                                          style: TextStyle(
                                            color: Colors.amber,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.green,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.public,
                                          size: 10,
                                          color: Colors.green,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          'Public',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      AnimatedBuilder(
                        animation: _audio,
                        builder: (context, child) {
                          final isCurrentRoom =
                              _audio.currentRoom != null &&
                              _audio.currentRoom!['audio_url'] ==
                                  room['audio_url'];

                          return IconButton(
                            icon: Icon(
                              isCurrentRoom && _audio.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: const Color(0xFF7C3AED),
                              size: 32,
                            ),
                            onPressed: () async {
                              final audioUrl = room['audio_url'] as String?;

                              if (audioUrl == null || audioUrl.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No audio URL found for this upload',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              if (isCurrentRoom) {
                                await _audio.togglePlayPause();
                                return;
                              }

                              setState(() {
                                _currentlyPlayingIndex = index;
                              });

                              try {
                                final queueData = userRooms.map((r) {
                                  return {
                                    'id': r['id'],
                                    'title': r['title'],
                                    'audio_url': r['audio_url'],
                                    'thumbnail_url': r['thumbnail_url'],
                                    'topic': r['topic'],
                                    'likes_count': r['likes_count'] ?? 0,
                                    'host_name': userData!['full_name'],
                                    'host_avatar': userData!['profile_pic'],
                                    'host_followers_count':
                                        userData!['followers_count'],
                                    'host_id': userData!['id'],
                                    'host': {
                                      'id': userData!['id'],
                                      'full_name': userData!['full_name'],
                                      'profile_pic': userData!['profile_pic'],
                                      'followers_count':
                                          userData!['followers_count'],
                                    },
                                  };
                                }).toList();

                                _audio.setAutoplayQueue(queueData, index);

                                final roomData = {
                                  'id': room['id'],
                                  'title': room['title'],
                                  'audio_url': room['audio_url'],
                                  'thumbnail_url': room['thumbnail_url'],
                                  'topic': room['topic'],
                                  'likes_count': room['likes_count'] ?? 0,
                                  'host_name': userData!['full_name'],
                                  'host_avatar': userData!['profile_pic'],
                                  'host_followers_count':
                                      userData!['followers_count'],
                                  'host_id': userData!['id'],
                                  'host': {
                                    'id': userData!['id'],
                                    'full_name': userData!['full_name'],
                                    'profile_pic': userData!['profile_pic'],
                                    'followers_count':
                                        userData!['followers_count'],
                                  },
                                };

                                await _audio.playRoom(
                                  roomData,
                                  fromUser: false,
                                );
                                setState(() {});
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error playing audio: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F1E),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite_border,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatCount(likesCount),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'likes',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: Colors.grey.withOpacity(0.3),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatCount(totalListens),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'plays',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRoomOptions(
    BuildContext context,
    Map<String, dynamic> room,
    int index,
  ) {
    final isPrivate = room['is_private'] ?? false;
    final title = room['title'] ?? 'Untitled';
    final roomId = room['id'];

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
                    title,
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
                      _audio.currentRoom!['audio_url'] == room['audio_url'],
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    final wasLooping = _audio.isLooping;
                    final isCurrentRoom =
                        _audio.currentRoom != null &&
                        _audio.currentRoom!['audio_url'] == room['audio_url'];

                    await _audio.toggleLoop();
                    if (!mounted) return;
                    setModalState(() {});
                    setState(() {});

                    if (!wasLooping && _audio.isLooping && !isCurrentRoom) {
                      try {
                        final roomData = {
                          'id': room['id'],
                          'title': room['title'],
                          'audio_url': room['audio_url'],
                          'thumbnail_url': room['thumbnail_url'],
                          'topic': room['topic'],
                          'likes_count': room['likes_count'] ?? 0,
                          'host_name': userData!['full_name'],
                          'host_avatar': userData!['profile_pic'],
                          'host_followers_count': userData!['followers_count'],
                          'host_id': userData!['id'],
                          'host': {
                            'id': userData!['id'],
                            'full_name': userData!['full_name'],
                            'profile_pic': userData!['profile_pic'],
                            'followers_count': userData!['followers_count'],
                          },
                        };

                        await _audio.playRoom(roomData, resetLoop: false);
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

                if (isOwnProfile)
                  _buildOption(
                    icon: isPrivate ? Icons.public : Icons.lock,
                    label: isPrivate ? 'Make Public' : 'Make Private',
                    iconColor: isPrivate ? Colors.green : Colors.amber,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _confirmTogglePrivacy(room, index);
                    },
                  ),

                if (isOwnProfile)
                  _buildOption(
                    icon: Icons.edit,
                    label: 'Edit',
                    onTap: () async {
                      Navigator.pop(context);
                      await _handleEdit(room);
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

                if (!isOwnProfile)
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
                      _handleReportRoom(roomId, index);
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
                      _audio.currentRoom!['audio_url'] == room['audio_url'],
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleAutoplay(room, index);
                  },
                ),

                if (isOwnProfile) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Colors.grey, height: 1),
                  const SizedBox(height: 10),
                  _buildOption(
                    icon: Icons.delete,
                    label: 'Delete Audio',
                    iconColor: Colors.red,
                    labelColor: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      _handleDelete(roomId, index);
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

  void _handleLoop(int roomId) {
    _audio.toggleLoop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_audio.isLooping ? 'Loop enabled' : 'Loop disabled'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF7C3AED),
      ),
    );
  }

  void _showRoomDescription(Map<String, dynamic> room) {
    final title = room['title'] as String? ?? 'Untitled';
    final rawDescription = room['description'] as String?;
    final description =
        (rawDescription == null || rawDescription.trim().isEmpty)
        ? 'No description added for this audio.'
        : rawDescription.trim();

    final createdAtRaw = room['created_at'] as String?;
    String uploadedText = 'Uploaded date unknown';

    if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAtRaw).toLocal();
        final day = dt.day.toString().padLeft(2, '0');
        final month = dt.month.toString().padLeft(2, '0');
        final year = dt.year.toString();
        uploadedText = 'Uploaded on $day-$month-$year';
      } catch (_) {}
    }

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

  Future<void> _confirmTogglePrivacy(
    Map<String, dynamic> room,
    int index,
  ) async {
    final bool isPrivate = room['is_private'] ?? false;
    final int roomId = room['id'] as int;

    final titleText = isPrivate
        ? 'Make this audio Public?'
        : 'Make this audio Private?';

    final descriptionText = isPrivate
        ? 'If you make it public, anyone on the platform can see and listen to it.'
        : 'If you make it private, only you will be able to access it.';

    final confirmButtonText = isPrivate ? 'Make Public' : 'Make Private';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            titleText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            descriptionText,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(
                confirmButtonText,
                style: const TextStyle(color: Color(0xFF7C3AED)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _handleTogglePrivacy(roomId, isPrivate, index);
  }

  Future<void> _handleTogglePrivacy(
    int roomId,
    bool currentPrivacy,
    int index,
  ) async {
    final oldValue = currentPrivacy;
    final newValue = !currentPrivacy;

    setState(() {
      userRooms[index]['is_private'] = newValue;
    });

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId/privacy',
      // );

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/rooms/$roomId/privacy',
      );

      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_private': newValue}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        setState(() {
          userRooms[index] = data;
        });

        final current = _audio.currentRoom;
        if (current != null && current['id'] == data['id']) {
          _audio.currentRoom = data;
          _audio.notifyListeners();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['is_private'] == true
                  ? 'Audio is now Private'
                  : 'Audio is now Public',
            ),
            backgroundColor: const Color(0xFF7C3AED),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        setState(() {
          userRooms[index]['is_private'] = oldValue;
        });

        String message = 'Failed to update privacy';
        try {
          final body = json.decode(response.body);
          message = body['error'] ?? message;
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() {
        userRooms[index]['is_private'] = oldValue;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _handleEdit(Map<String, dynamic> room) async {
    final updatedRoom = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => EditRoomScreen(room: room)),
    );

    if (updatedRoom == null) return;

    final idx = userRooms.indexWhere((r) => r['id'] == updatedRoom['id']);

    if (idx != -1) {
      setState(() {
        userRooms[idx] = updatedRoom;
      });
    } else {
      await _loadUserRooms(reset: false);
      setState(() {});
    }

    final current = _audio.currentRoom;
    if (current != null && current['id'] == updatedRoom['id']) {
      _audio.currentRoom = updatedRoom;
      _audio.currentTitle = updatedRoom['title'] as String?;
      _audio.notifyListeners();
    }
  }

  Future<void> _handleDownload(
    Map<String, dynamic> room,
    BuildContext rootContext,
  ) async {
    final audioUrl = room['audio_url'] as String?;
    final title = (room['title'] as String?) ?? 'audio';
    final roomId = room['id'] as int;

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
              roomId: roomId,
              fileName: fileName,
              downloadPath: '$savedDir/$fileName',
            );

            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text(
                  '$fileName download started. It will be stored to downloads in your device!',
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
        roomId: roomId,
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

  void _handleAutoplay(Map<String, dynamic> room, int index) async {
    final isCurrentRoom =
        _audio.currentRoom != null &&
        _audio.currentRoom!['audio_url'] == room['audio_url'];

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

    final queueData = userRooms.map((r) {
      return {
        'id': r['id'],
        'title': r['title'],
        'audio_url': r['audio_url'],
        'thumbnail_url': r['thumbnail_url'],
        'topic': r['topic'],
        'likes_count': r['likes_count'] ?? 0,
        'host_name': userData!['full_name'],
        'host_avatar': userData!['profile_pic'],
        'host_followers_count': userData!['followers_count'],
        'host_id': userData!['id'],
        'host': {
          'id': userData!['id'],
          'full_name': userData!['full_name'],
          'profile_pic': userData!['profile_pic'],
          'followers_count': userData!['followers_count'],
        },
      };
    }).toList();

    _audio.setAutoplayQueue(queueData, index);

    if (!isCurrentRoom) {
      try {
        final roomData = {
          'id': room['id'],
          'title': room['title'],
          'audio_url': room['audio_url'],
          'thumbnail_url': room['thumbnail_url'],
          'topic': room['topic'],
          'likes_count': room['likes_count'] ?? 0,
          'host_name': userData!['full_name'],
          'host_avatar': userData!['profile_pic'],
          'host_followers_count': userData!['followers_count'],
          'host_id': userData!['id'],
          'host': {
            'id': userData!['id'],
            'full_name': userData!['full_name'],
            'profile_pic': userData!['profile_pic'],
            'followers_count': userData!['followers_count'],
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

  Future<void> _handleDelete(int roomId, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete audio?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently remove this audio from your account. '
          'This action cannot be undone. Are you sure?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      final token = await _storage.read(key: 'jwt_token');

      // final url = Uri.parse(
      //   'http://$serverIP:$serverPort/api/v1/rooms/$roomId',
      // );

      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/rooms/$roomId');

      final response = await http.delete(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        final current = _audio.currentRoom;
        if (current != null && current['id'] == roomId) {
          await _audio.player.stop();
          _audio.currentRoom = null;
          _audio.currentUrl = null;
          _audio.currentTitle = null;
          _audio.isPlaying = false;
          _audio.notifyListeners();
        }

        setState(() {
          if (index >= 0 && index < userRooms.length) {
            userRooms.removeAt(index);
          }
        });

        // Optional: if you prefer server truth instead:
        // await _loadUserRooms();
        // setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        String message = 'Failed to delete audio';
        try {
          final body = json.decode(response.body);
          message = body['error'] ?? message;
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildMiniPlayer() {
    if (_audio.currentUrl == null) {
      return const SizedBox.shrink();
    }

    return _MiniPlayerWidget(audio: _audio, openFullPlayer: _openFullPlayer);
  }

  void _openFullPlayer() {
    if (_audio.currentRoom == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FullPlayerSheet(
        audio: _audio,
        onLikeChange: _applyLikeChange,
        onFollowStatusChanged: () {
          _loadProfile();
        },
      ),
    );
  }

  Widget _buildCommunityPostsTab() {
    if (_isLoadingCommunityPosts) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
        ),
      );
    }

    if (_hasCommunityPostsError) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Failed to load posts',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_communityPosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.article_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No posts yet',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (isOwnProfile)
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateCommunityPostScreen(),
                    ),
                  );
                  if (result == true) {
                    await _loadCommunityPosts();
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Create your first post'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _communityPosts.length,
      itemBuilder: (context, index) {
        final post = _communityPosts[index];
        final postId = post['id'] as int;

        // Get or create key for this post (for auto-scroll functionality)
        _postKeys.putIfAbsent(postId, () => GlobalKey());

        return _CommunityPostCard(
          key: _postKeys[postId],
          post: post,
          isOwnProfile: isOwnProfile,
          onUpdate: () => _loadCommunityPosts(),
        );
      },
    );
  }
}

class _FullPlayerSheet extends StatefulWidget {
  final GlobalAudioService audio;
  final void Function({
    required int roomId,
    required bool isLiked,
    required int likesCount,
  })
  onLikeChange;
  final VoidCallback? onFollowStatusChanged;

  const _FullPlayerSheet({
    required this.audio,
    required this.onLikeChange,
    this.onFollowStatusChanged,
  });

  @override
  State<_FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<_FullPlayerSheet> {
  bool _isLiked = false;
  int _likesCount = 0;
  final _authService = AuthService();
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

    final room = widget.audio.currentRoom;
    if (room == null) return;

    final roomId = room['id'] as int;

    final prevLiked = _isLiked;
    final prevCount = _likesCount;

    setState(() {
      _isTogglingLike = true;
      _isLiked = !prevLiked;
      _likesCount = prevLiked ? prevCount - 1 : prevCount + 1;
    });

    widget.onLikeChange(
      roomId: roomId,
      isLiked: _isLiked,
      likesCount: _likesCount,
    );

    final result = await _likeService.toggleLike(roomId);

    if (result == null && mounted) {
      setState(() {
        _isLiked = prevLiked;
        _likesCount = prevCount;
        _isTogglingLike = false;
      });

      widget.onLikeChange(
        roomId: roomId,
        isLiked: prevLiked,
        likesCount: prevCount,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update like'),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    if (mounted) {
      setState(() {
        _isLiked = result?['is_liked'];
        _likesCount = result?['likes_count'];
        _isTogglingLike = false;
      });

      widget.onLikeChange(
        roomId: roomId,
        isLiked: result?['is_liked'] ?? false,
        likesCount: result?['likes_count'] ?? 0,
      );
    }
  }

  void _updateHostFollowersInRooms(int hostId, bool isFollowing) {
    final profileScreenState = context
        .findAncestorStateOfType<_ProfileScreenState>();

    if (profileScreenState != null) {
      profileScreenState.setState(() {
        for (var i = 0; i < profileScreenState.userRooms.length; i++) {
          final room = profileScreenState.userRooms[i] as Map<String, dynamic>;

          final roomHostId = room['host_id'] is int
              ? room['host_id']
              : int.tryParse(room['host_id']?.toString() ?? '');

          if (roomHostId == hostId) {
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

            profileScreenState.userRooms[i] = updatedRoom;
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

    final int? hostId = room['host_id'] is int
        ? room['host_id'] as int
        : int.tryParse(room['host_id']?.toString() ?? '');

    final dynamic rawUserId = _authService.currentUser?['id'];
    final int? currentUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');

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

                            widget.onFollowStatusChanged?.call();
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

class _CommunityPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isOwnProfile;
  final VoidCallback onUpdate;

  const _CommunityPostCard({
    super.key,
    required this.post,
    required this.isOwnProfile,
    required this.onUpdate,
  });

  @override
  State<_CommunityPostCard> createState() => _CommunityPostCardState();
}

class _CommunityPostCardState extends State<_CommunityPostCard> {
  final _communityService = CommunityService();
  final _authService = AuthService();
  final _audioPlayer = AudioPlayer();

  late bool _isLiked;
  late int _likesCount;
  late int _commentsCount;
  bool _isPlayingAudio = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  int _currentImageIndex = 0;
  bool _isLiking = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['is_liked'] ?? false;
    _likesCount = widget.post['likes_count'] ?? 0;
    _commentsCount = widget.post['comments_count'] ?? 0;

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _audioPosition = position;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _audioDuration = duration;
        });
      }
    });
  }

  @override
  void didUpdateWidget(_CommunityPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post['id'] == widget.post['id']) {
      if (oldWidget.post['is_liked'] != widget.post['is_liked']) {
        _isLiked = widget.post['is_liked'] ?? false;
      }
      if (oldWidget.post['likes_count'] != widget.post['likes_count']) {
        _likesCount = widget.post['likes_count'] ?? 0;
      }
      if (oldWidget.post['comments_count'] != widget.post['comments_count']) {
        _commentsCount = widget.post['comments_count'] ?? 0;
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    if (_isLiking) return;

    setState(() => _isLiking = true);

    final previousLiked = _isLiked;
    final previousCount = _likesCount;

    setState(() {
      _isLiked = !_isLiked;
      _likesCount = _isLiked ? _likesCount + 1 : _likesCount - 1;
    });

    final result = await _communityService.togglePostLike(widget.post['id']);

    if (result != null && mounted) {
      setState(() {
        _isLiked = result['liked'] ?? previousLiked;
        _likesCount = result['likes_count'] ?? previousCount;
        _isLiking = false;
      });
    } else {
      if (mounted) {
        setState(() {
          _isLiked = previousLiked;
          _likesCount = previousCount;
          _isLiking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update like'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _toggleAudioPlayback() async {
    final audioUrl = widget.post['audio_url'];
    if (audioUrl == null) return;

    if (_isPlayingAudio) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(audioUrl));
    }
  }

  void _showCommentsSheet() async {
    final initialCommentCount = _commentsCount;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommunityCommentsSheet(
        postId: widget.post['id'],
        postTitle: 'Post',
        postAuthorId: widget.post['user']['id'],
        onCommentCountChanged: (newCount) {
          if (mounted) {
            setState(() {
              _commentsCount = newCount;
            });
          }
        },
      ),
    );

    if (mounted && _commentsCount != initialCommentCount) {
      widget.onUpdate();
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Post?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This post will be permanently deleted.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _communityService.deleteCommunityPost(
        widget.post['id'],
      );
      if (result != null && mounted) {
        widget.onUpdate();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted'),
            backgroundColor: Color(0xFF7C3AED),
          ),
        );
      }
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';

    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${(diff.inDays / 7).floor()}w ago';
    } catch (e) {
      return '';
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF7C3AED)),
              title: const Text(
                'Edit Post',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _navigateToEditPost();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete Post',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _deletePost();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditPost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCommunityPostScreen(post: widget.post),
      ),
    );

    if (result == true) {
      widget.onUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.post['user'] as Map<String, dynamic>;
    final content = widget.post['content'] as String?;
    final images = (widget.post['images'] as List? ?? [])
        .map((img) => img['image_url'] as String)
        .toList();
    final audioUrl = widget.post['audio_url'] as String?;
    final audioDuration = widget.post['duration'] as int?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF7C3AED),
                  backgroundImage: user['profile_pic'] != null
                      ? NetworkImage(user['profile_pic'])
                      : null,
                  child: user['profile_pic'] == null
                      ? Text(
                          user['full_name'][0].toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['full_name'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _formatTime(widget.post['created_at']),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isOwnProfile)
                  IconButton(
                    onPressed: _showPostOptions,
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                  ),
              ],
            ),
          ),

          if (content != null && content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                content,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),

          if (content != null && content.isNotEmpty) const SizedBox(height: 12),

          if (images.isNotEmpty)
            SizedBox(
              height: 300,
              child: Stack(
                children: [
                  PageView.builder(
                    itemCount: images.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentImageIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            barrierColor: Colors.black,
                            builder: (context) => Scaffold(
                              backgroundColor: Colors.black,
                              body: Stack(
                                children: [
                                  Center(
                                    child: InteractiveViewer(
                                      child: Image.network(
                                        images[index],
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  SafeArea(
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Image.network(
                          images[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      );
                    },
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentImageIndex + 1}/${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          if (audioUrl != null &&
              audioUrl.isNotEmpty &&
              (audioDuration ?? 0) > 0)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _toggleAudioPlayback,
                        icon: Icon(
                          _isPlayingAudio ? Icons.pause : Icons.play_arrow,
                          color: const Color(0xFF7C3AED),
                          size: 32,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                              ),
                              child: Slider(
                                value: _audioPosition.inSeconds.toDouble(),
                                max:
                                    (_audioDuration.inSeconds > 0
                                            ? _audioDuration.inSeconds
                                            : 1)
                                        .toDouble(),
                                onChanged: (value) async {
                                  await _audioPlayer.seek(
                                    Duration(seconds: value.toInt()),
                                  );
                                },
                                activeColor: const Color(0xFF7C3AED),
                                inactiveColor: Colors.white24,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_audioPosition),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  _formatDuration(
                                    Duration(seconds: audioDuration ?? 0),
                                  ),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: _isLiking ? null : _toggleLike,
                  child: Row(
                    children: [
                      Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked
                            ? const Color(0xFFEB5757)
                            : Colors.white70,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCount(_likesCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                InkWell(
                  onTap: _showCommentsSheet,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.comment_outlined,
                        color: Colors.white70,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCount(_commentsCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.share_outlined,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayerWidget extends StatefulWidget {
  final GlobalAudioService audio;
  final VoidCallback openFullPlayer;

  const _MiniPlayerWidget({required this.audio, required this.openFullPlayer});

  @override
  State<_MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<_MiniPlayerWidget> {
  @override
  void initState() {
    super.initState();
    widget.audio.addListener(_onAudioChanged);
  }

  @override
  void dispose() {
    widget.audio.removeListener(_onAudioChanged);
    super.dispose();
  }

  void _onAudioChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final totalSecs = widget.audio.duration.inSeconds;
    final posSecs = widget.audio.position.inSeconds.clamp(
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
      onTap: widget.openFullPlayer,
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -8) {
          widget.openFullPlayer();
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
                    widget.audio.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: const Color(0xFF7C3AED),
                    size: 32,
                  ),
                  onPressed: () async {
                    await widget.audio.togglePlayPause();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.audio.currentTitle ?? '',
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
                  onPressed: widget.openFullPlayer,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  formatDuration(widget.audio.position),
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
                        await widget.audio.player.seek(newPos);
                      },
                      activeColor: const Color(0xFF7C3AED),
                      inactiveColor: Colors.white24,
                    ),
                  ),
                ),
                Text(
                  formatDuration(widget.audio.duration),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
