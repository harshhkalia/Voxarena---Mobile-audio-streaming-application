import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/like_service.dart';
import '../services/follow_service.dart';
import '../services/websocket_service.dart';
import '../widgets/comments_sheet.dart';
import 'profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _notificationService = NotificationService();
  final _authService = AuthService();
  final _audio = GlobalAudioService();
  final _webSocket = WebSocketService();
  final ScrollController _scrollController = ScrollController();

  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  final int _limit = 20;
  StreamSubscription<Map<String, dynamic>>? _removeNotificationsSubscription;

  @override
  void initState() {
    super.initState();
    _loadNotificationsAndMarkRead();
    _scrollController.addListener(_onScroll);
    _audio.addListener(_onAudioChanged);
    _setupRemoveNotificationsListener();
  }

  void _setupRemoveNotificationsListener() {
    _removeNotificationsSubscription = _webSocket.removeNotificationsStream
        .listen((data) {
          final type = data['type'] as String?;

          if (type == 'comment') {
            final actorId = data['actor_id'];
            final message = data['message'] as String?;
            final roomId = data['room_id'];

            if (actorId != null &&
                message != null &&
                roomId != null &&
                mounted) {
              final actorIdInt = actorId is int
                  ? actorId
                  : int.tryParse(actorId.toString());
              final roomIdInt = roomId is int
                  ? roomId
                  : int.tryParse(roomId.toString());

              if (actorIdInt != null && roomIdInt != null) {
                setState(() {
                  _notifications.removeWhere(
                    (n) =>
                        (n.type == 'comment' || n.type == 'mention') &&
                        n.actorId == actorIdInt &&
                        n.message == message &&
                        n.referenceId == roomIdInt,
                  );
                });
                print(
                  'Removed comment/mention notification from actor $actorIdInt',
                );
              }
            }
          } else if (type == 'comment_like') {
            final actorId = data['actor_id'];
            final message = data['message'] as String?;

            if (actorId != null && message != null && mounted) {
              final actorIdInt = actorId is int
                  ? actorId
                  : int.tryParse(actorId.toString());

              if (actorIdInt != null) {
                setState(() {
                  _notifications.removeWhere(
                    (n) =>
                        n.type == 'comment_like' &&
                        n.actorId == actorIdInt &&
                        n.message == message,
                  );
                });
                print(
                  'Removed comment like notification from actor $actorIdInt',
                );
              }
            }
          } else if (type == 'follow') {
            final actorId = data['actor_id'];

            if (actorId != null && mounted) {
              final actorIdInt = actorId is int
                  ? actorId
                  : int.tryParse(actorId.toString());

              if (actorIdInt != null) {
                setState(() {
                  _notifications.removeWhere(
                    (n) => n.type == 'follow' && n.actorId == actorIdInt,
                  );
                });
                print('Removed follow notification from actor $actorIdInt');
              }
            }
          } else {
            // Handle room notification removal
            final referenceType = data['reference_type'] as String?;
            final referenceId = data['reference_id'];

            if (referenceType == 'room' && referenceId != null) {
              final roomId = referenceId is int
                  ? referenceId
                  : int.tryParse(referenceId.toString());
              if (roomId != null && mounted) {
                setState(() {
                  _notifications.removeWhere(
                    (n) => n.referenceType == 'room' && n.referenceId == roomId,
                  );
                });
                print('Removed notifications for deleted room $roomId');
              }
            }
          }
        });
  }

  Future<void> _loadNotificationsAndMarkRead() async {
    await _loadNotifications(reset: true);
    _markAllAsReadSilently();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audio.removeListener(_onAudioChanged);
    _removeNotificationsSubscription?.cancel();
    super.dispose();
  }

  void _onAudioChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadNotifications(reset: false);
    }
  }

  Future<void> _loadNotifications({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _page = 1;
        _notifications = [];
        _hasMore = true;
      });
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final result = await _notificationService.getNotifications(
        page: _page,
        limit: _limit,
      );

      if (result != null && result['success'] == true) {
        final notificationsList = result['notifications'] as List? ?? [];
        final fetched = notificationsList
            .map(
              (json) => AppNotification.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        setState(() {
          if (reset) {
            _notifications = fetched;
          } else {
            _notifications.addAll(fetched);
          }

          _hasMore = result['has_more'] == true;
          _page += 1;
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _markAllAsReadSilently() async {
    final hasUnread = _notifications.any((n) => !n.isRead);
    if (!hasUnread) return;

    final success = await _notificationService.markAllAsRead();
    if (success && mounted) {
      setState(() {
        _notifications = _notifications.map((n) {
          return AppNotification(
            id: n.id,
            userId: n.userId,
            actorId: n.actorId,
            type: n.type,
            title: n.title,
            message: n.message,
            referenceId: n.referenceId,
            referenceType: n.referenceType,
            imageUrl: n.imageUrl,
            actionUrl: n.actionUrl,
            isRead: true,
            readAt: DateTime.now(),
            createdAt: n.createdAt,
            actor: n.actor,
          );
        }).toList();
      });
    }
  }

  Future<void> _deleteNotification(
    AppNotification notification,
    int index,
  ) async {
    final removedNotification = notification;
    final removedIndex = index;

    setState(() {
      _notifications.removeAt(index);
    });

    final success = await _notificationService.deleteNotification(
      notification.id,
    );

    if (!success && mounted) {
      setState(() {
        _notifications.insert(removedIndex, removedNotification);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete notification'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleNotificationTap(AppNotification notification) {
    if ((notification.type == 'comment' || notification.type == 'mention') &&
        notification.referenceId != null) {
      _showCommentNotificationSheet(notification);
      return;
    }

    if (notification.type == 'comment_like' &&
        notification.referenceId != null) {
      _showCommentLikeNotificationSheet(notification);
      return;
    }

    if (notification.type == 'follow' && notification.actor != null) {
      _showFollowNotificationSheet(notification);
      return;
    }

    if (notification.type == 'community_post' &&
        notification.referenceType == 'post' &&
        notification.referenceId != null) {
      if (notification.actor != null) {
        final currentUserId = _authService.currentUser?['id'];
        final isOwnProfile =
            currentUserId != null && notification.actor!.id == currentUserId;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => isOwnProfile
                ? ProfileScreen(scrollToPostId: notification.referenceId)
                : ProfileScreen(
                    userId: notification.actor!.id,
                    scrollToPostId: notification.referenceId,
                  ),
          ),
        );
      }
      return;
    }

    // Handle community post comments and mentions
    if (notification.type == 'community_comment' &&
        notification.referenceType == 'post' &&
        notification.referenceId != null) {
      if (notification.actor != null) {
        final currentUserId = _authService.currentUser?['id'];
        final isOwnProfile =
            currentUserId != null && notification.actor!.id == currentUserId;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => isOwnProfile
                ? ProfileScreen(scrollToPostId: notification.referenceId)
                : ProfileScreen(
                    userId: notification.actor!.id,
                    scrollToPostId: notification.referenceId,
                  ),
          ),
        );
      }
      return;
    }

    if (notification.referenceType == 'room' &&
        notification.referenceId != null) {
      if (notification.actor != null) {
        final currentUserId = _authService.currentUser?['id'];
        final isOwnProfile =
            currentUserId != null && notification.actor!.id == currentUserId;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => isOwnProfile
                ? ProfileScreen(scrollToRoomId: notification.referenceId)
                : ProfileScreen(
                    userId: notification.actor!.id,
                    scrollToRoomId: notification.referenceId,
                  ),
          ),
        );
      }
    } else if (notification.actor != null) {
      final currentUserId = _authService.currentUser?['id'];
      final isOwnProfile =
          currentUserId != null && notification.actor!.id == currentUserId;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => isOwnProfile
              ? const ProfileScreen()
              : ProfileScreen(userId: notification.actor!.id),
        ),
      );
    }
  }

  void _showCommentNotificationSheet(AppNotification notification) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentNotificationSheet(
        notification: notification,
        onViewAllComments: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => CommentsSheet(
              roomId: notification.referenceId!,
              roomTitle: notification.title,
              roomAuthorId: notification.actor?.id ?? 0,
            ),
          );
        },
      ),
    );
  }

  void _showCommentLikeNotificationSheet(AppNotification notification) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentLikeNotificationSheet(
        notification: notification,
        onViewAllComments: () {
          Navigator.pop(context);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => CommentsSheet(
              roomId: notification.referenceId!,
              roomTitle: notification.title,
              roomAuthorId: notification.actor?.id ?? 0,
            ),
          );
        },
      ),
    );
  }

  void _showFollowNotificationSheet(AppNotification notification) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FollowNotificationSheet(
        notification: notification,
        onViewProfile: () {
          Navigator.pop(context);
          if (notification.actor != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: notification.actor!.id),
              ),
            );
          }
        },
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'follow':
        return Icons.person_add;
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      case 'comment_like':
        return Icons.thumb_up;
      case 'new_room':
        return Icons.audiotrack;
      case 'room_live':
        return Icons.live_tv;
      case 'community_post':
        return Icons.post_add;
      case 'community_post_like':
        return Icons.favorite_border;
      case 'community_comment':
        return Icons.chat_bubble;
      case 'gift':
        return Icons.card_giftcard;
      case 'mention':
        return Icons.alternate_email;
      case 'system':
        return Icons.notifications;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'follow':
        return const Color(0xFF5B8CFF);
      case 'like':
      case 'community_post_like':
        return const Color(0xFFEB5757);
      case 'comment':
      case 'community_comment':
        return const Color(0xFF00C2A8);
      case 'comment_like':
        return const Color(0xFFFF6B6B);
      case 'new_room':
        return const Color(0xFF7C3AED);
      case 'room_live':
        return const Color(0xFFEF6CFF);
      case 'community_post':
        return const Color(0xFFFFC857);
      case 'gift':
        return const Color(0xFFFFD700);
      case 'mention':
        return const Color(0xFF00D4FF);
      case 'system':
        return const Color(0xFF8E6FFF);
      default:
        return const Color(0xFF7C3AED);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1E),
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildMiniPlayer(),
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
      builder: (context) => _NotificationFullPlayerSheet(
        audio: _audio,
        currentUser: _authService.currentUser,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadNotifications(reset: true),
      color: const Color(0xFF7C3AED),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _notifications.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                ),
              ),
            );
          }

          final notification = _notifications[index];
          return Dismissible(
            key: Key('notification_${notification.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: const Color(0xFFEB5757),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.white,
                size: 28,
              ),
            ),
            onDismissed: (_) => _deleteNotification(notification, index),
            child: _buildNotificationItem(notification),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: Colors.grey.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No notifications yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When you get notifications,\nthey\'ll show up here',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.withOpacity(0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(AppNotification notification) {
    final iconColor = _getNotificationColor(notification.type);
    final icon = _getNotificationIcon(notification.type);

    return InkWell(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.transparent
              : const Color(0xFF7C3AED).withOpacity(0.08),
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                if (notification.actor != null) {
                  final currentUserId = _authService.currentUser?['id'];
                  final isOwnProfile =
                      currentUserId != null &&
                      notification.actor!.id == currentUserId;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => isOwnProfile
                          ? const ProfileScreen()
                          : ProfileScreen(userId: notification.actor!.id),
                    ),
                  );
                }
              },
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF1A1A2E),
                    backgroundImage:
                        notification.actor?.profilePic != null &&
                            notification.actor!.profilePic!.isNotEmpty
                        ? CachedNetworkImageProvider(
                            notification.actor!.profilePic!,
                          )
                        : null,
                    child:
                        notification.actor?.profilePic == null ||
                            notification.actor!.profilePic!.isEmpty
                        ? const Icon(
                            Icons.person,
                            color: Colors.white54,
                            size: 24,
                          )
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: iconColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0F0F1E),
                          width: 2,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 10),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      children: [
                        if (notification.actor?.fullName != null)
                          TextSpan(
                            text: notification.actor!.fullName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        TextSpan(
                          text: notification.actor?.fullName != null
                              ? ' ${_getActionText(notification.type)}'
                              : notification.title,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (notification.message != null &&
                      notification.message!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        notification.message!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    notification.timeAgo,
                    style: TextStyle(
                      color: Colors.grey.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (notification.imageUrl != null &&
                notification.imageUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: notification.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: const Color(0xFF1A1A2E),
                      child: const Icon(
                        Icons.audiotrack,
                        color: Colors.white24,
                        size: 20,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: const Color(0xFF1A1A2E),
                      child: const Icon(
                        Icons.audiotrack,
                        color: Colors.white24,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            if (!notification.isRead)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF7C3AED),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getActionText(String type) {
    switch (type) {
      case 'follow':
        return 'started following you';
      case 'like':
        return 'liked your audio';
      case 'comment':
        return 'commented on your audio';
      case 'comment_like':
        return 'liked your comment';
      case 'new_room':
        return 'uploaded a new audio';
      case 'room_live':
        return 'went live';
      case 'community_post':
        return 'created a new post';
      case 'community_post_like':
        return 'liked your post';
      case 'community_comment':
        return 'commented on your post';
      case 'gift':
        return 'sent you a gift';
      case 'mention':
        return 'mentioned you';
      default:
        return '';
    }
  }
}

class _NotificationFullPlayerSheet extends StatefulWidget {
  final GlobalAudioService audio;
  final Map<String, dynamic>? currentUser;

  const _NotificationFullPlayerSheet({required this.audio, this.currentUser});

  @override
  State<_NotificationFullPlayerSheet> createState() =>
      _NotificationFullPlayerSheetState();
}

class _NotificationFullPlayerSheetState
    extends State<_NotificationFullPlayerSheet> {
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
                      else if (hostId != null)
                        _NotificationFollowButton(hostId: hostId),
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
                            _buildSpeedMenuItem(0.5),
                            _buildSpeedMenuItem(0.75),
                            _buildSpeedMenuItem(1.0),
                            _buildSpeedMenuItem(1.25),
                            _buildSpeedMenuItem(1.5),
                            _buildSpeedMenuItem(1.75),
                            _buildSpeedMenuItem(2.0),
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

class _NotificationFollowButton extends StatefulWidget {
  final int hostId;

  const _NotificationFollowButton({required this.hostId});

  @override
  State<_NotificationFollowButton> createState() =>
      _NotificationFollowButtonState();
}

class _NotificationFollowButtonState extends State<_NotificationFollowButton> {
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

class _CommentNotificationSheet extends StatefulWidget {
  final AppNotification notification;
  final VoidCallback onViewAllComments;

  const _CommentNotificationSheet({
    required this.notification,
    required this.onViewAllComments,
  });

  @override
  State<_CommentNotificationSheet> createState() =>
      _CommentNotificationSheetState();
}

class _CommentNotificationSheetState extends State<_CommentNotificationSheet> {
  final _audio = GlobalAudioService();
  bool _isLoadingAudio = false;

  Future<void> _playAudio() async {
    if (widget.notification.referenceId == null) return;

    setState(() => _isLoadingAudio = true);

    try {
      final token = await const FlutterSecureStorage().read(key: 'jwt_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/rooms/${widget.notification.referenceId}',
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
        final room = data['room'];

        if (room != null && room['audio_url'] != null) {
          final roomData = {
            'id': room['id'],
            'title': room['title'],
            'audio_url': room['audio_url'],
            'thumbnail_url': room['thumbnail_url'],
            'topic': room['topic'],
            'likes_count': room['likes_count'] ?? 0,
            'host_name': room['host']?['full_name'] ?? 'Unknown',
            'host_avatar': room['host']?['profile_pic'],
            'host_id': room['host_id'],
            'host': room['host'],
          };

          Navigator.pop(context);
          await _audio.playRoom(roomData, fromUser: true);
        } else {
          throw Exception('Audio not available');
        }
      } else {
        throw Exception('Failed to fetch room');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAudio = false);
      }
    }
  }

  bool get _isReply {
    final title = widget.notification.title.toLowerCase();
    return title.contains('replied') || title.contains('mentioned');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      widget.notification.imageUrl != null &&
                          widget.notification.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.notification.imageUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(
                              Icons.audiotrack,
                              color: Colors.white24,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(
                              Icons.audiotrack,
                              color: Colors.white24,
                            ),
                          ),
                        )
                      : Container(
                          width: 60,
                          height: 60,
                          color: const Color(0xFF1A1A2E),
                          child: const Icon(
                            Icons.audiotrack,
                            color: Colors.white24,
                            size: 28,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isReply
                            ? 'Reply to your comment'
                            : 'Comment on your audio',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Audio Room',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Container(height: 1, color: Colors.white.withOpacity(0.1)),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (_isReply
                                    ? const Color(0xFF00C2A8)
                                    : const Color(0xFF7C3AED))
                                .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _isReply ? 'NEW REPLY' : 'NEW COMMENT',
                        style: TextStyle(
                          color: _isReply
                              ? const Color(0xFF00C2A8)
                              : const Color(0xFF7C3AED),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Show original comment for replies
                if (_isReply &&
                    widget.notification.extraData != null &&
                    widget.notification.extraData!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.format_quote,
                              color: Colors.grey,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Posted comment',
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.notification.extraData!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                            height: 1.3,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C2A8).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.subdirectory_arrow_right,
                          size: 12,
                          color: Color(0xFF00C2A8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.notification.actor?.fullName ?? 'Someone'} replied:',
                        style: TextStyle(
                          color: Colors.grey.withOpacity(0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          (_isReply
                                  ? const Color(0xFF00C2A8)
                                  : const Color(0xFF7C3AED))
                              .withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF2A2A3E),
                            backgroundImage:
                                widget.notification.actor?.profilePic != null &&
                                    widget
                                        .notification
                                        .actor!
                                        .profilePic!
                                        .isNotEmpty
                                ? CachedNetworkImageProvider(
                                    widget.notification.actor!.profilePic!,
                                  )
                                : null,
                            child:
                                widget.notification.actor?.profilePic == null ||
                                    widget
                                        .notification
                                        .actor!
                                        .profilePic!
                                        .isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white54,
                                    size: 20,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.notification.actor?.fullName ??
                                      'Unknown User',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.notification.timeAgo,
                                  style: TextStyle(
                                    color: Colors.grey.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.notification.message ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onViewAllComments,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'View All Comments',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoadingAudio ? null : _playAudio,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: const Color(0xFF7C3AED).withOpacity(0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoadingAudio
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_filled,
                            size: 22,
                            color: Color(0xFF7C3AED),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Play Audio',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

class _FollowNotificationSheet extends StatefulWidget {
  final AppNotification notification;
  final VoidCallback onViewProfile;

  const _FollowNotificationSheet({
    required this.notification,
    required this.onViewProfile,
  });

  @override
  State<_FollowNotificationSheet> createState() =>
      _FollowNotificationSheetState();
}

class _FollowNotificationSheetState extends State<_FollowNotificationSheet> {
  final _followService = FollowService();
  bool _isFollowing = false;
  bool _isLoading = true;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    if (widget.notification.actor == null) return;

    try {
      final isFollowing = await _followService.checkFollowStatus(
        widget.notification.actor!.id,
      );
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (widget.notification.actor == null || _isToggling) return;

    setState(() {
      _isToggling = true;
    });

    try {
      final result = await _followService.toggleFollow(
        widget.notification.actor!.id,
      );
      if (result != null && mounted) {
        setState(() {
          _isFollowing = result['is_following'] ?? !_isFollowing;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isToggling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF5B8CFF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add, color: Color(0xFF5B8CFF), size: 16),
                SizedBox(width: 6),
                Text(
                  'NEW FOLLOWER',
                  style: TextStyle(
                    color: Color(0xFF5B8CFF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          GestureDetector(
            onTap: widget.onViewProfile,
            child: CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF2A2A3E),
              backgroundImage:
                  widget.notification.actor?.profilePic != null &&
                      widget.notification.actor!.profilePic!.isNotEmpty
                  ? CachedNetworkImageProvider(
                      widget.notification.actor!.profilePic!,
                    )
                  : null,
              child:
                  widget.notification.actor?.profilePic == null ||
                      widget.notification.actor!.profilePic!.isEmpty
                  ? const Icon(Icons.person, color: Colors.white54, size: 40)
                  : null,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            widget.notification.actor?.fullName ?? 'New Follower',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            '@${widget.notification.actor?.username ?? 'user'}',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),

          const SizedBox(height: 8),

          Text(
            widget.notification.timeAgo,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _isToggling ? null : _toggleFollow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFollowing
                            ? const Color(0xFF1A1A2E)
                            : const Color(0xFF7C3AED),
                        foregroundColor: _isFollowing
                            ? const Color(0xFF7C3AED)
                            : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: _isFollowing
                              ? const BorderSide(color: Color(0xFF7C3AED))
                              : BorderSide.none,
                        ),
                      ),
                      child: _isToggling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF7C3AED),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isFollowing ? Icons.check : Icons.person_add,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isFollowing ? 'Following' : 'Follow Back',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // View Profile button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onViewProfile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_outline, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'View Profile',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

class _CommentLikeNotificationSheet extends StatefulWidget {
  final AppNotification notification;
  final VoidCallback onViewAllComments;

  const _CommentLikeNotificationSheet({
    required this.notification,
    required this.onViewAllComments,
  });

  @override
  State<_CommentLikeNotificationSheet> createState() =>
      _CommentLikeNotificationSheetState();
}

class _CommentLikeNotificationSheetState
    extends State<_CommentLikeNotificationSheet> {
  final _audio = GlobalAudioService();
  final _storage = const FlutterSecureStorage();
  bool _isLoadingAudio = false;

  Future<void> _playAudio() async {
    if (_isLoadingAudio) return;

    setState(() {
      _isLoadingAudio = true;
    });

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final roomId = widget.notification.referenceId;
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/rooms/$roomId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final room = data['room'];

        final roomData = {
          'id': room['id'],
          'title': room['title'] ?? 'Audio',
          'audio_url': room['audio_url'],
          'thumbnail_url': room['thumbnail_url'],
          'host': room['host'],
          'likes_count': room['likes_count'] ?? 0,
          'duration': room['duration'] ?? 0,
        };

        Navigator.pop(context);
        await _audio.playRoom(roomData);
      } else {
        throw Exception('Failed to load room');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAudio = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      widget.notification.imageUrl != null &&
                          widget.notification.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.notification.imageUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(
                              Icons.audiotrack,
                              color: Colors.white24,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: const Icon(
                              Icons.audiotrack,
                              color: Colors.white24,
                            ),
                          ),
                        )
                      : Container(
                          width: 60,
                          height: 60,
                          color: const Color(0xFF1A1A2E),
                          child: const Icon(
                            Icons.audiotrack,
                            color: Colors.white24,
                            size: 28,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your comment was liked',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.notification.extraData ?? 'Audio',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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

          const SizedBox(height: 20),

          Container(height: 1, color: Colors.white.withOpacity(0.1)),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF2A2A3E),
                      backgroundImage:
                          widget.notification.actor?.profilePic != null &&
                              widget.notification.actor!.profilePic!.isNotEmpty
                          ? CachedNetworkImageProvider(
                              widget.notification.actor!.profilePic!,
                            )
                          : null,
                      child:
                          widget.notification.actor?.profilePic == null ||
                              widget.notification.actor!.profilePic!.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 20,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.notification.actor?.fullName ??
                                    'Someone',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.favorite,
                                color: Color(0xFFFF6B6B),
                                size: 16,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.notification.timeAgo,
                            style: TextStyle(
                              color: Colors.grey.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF6B6B).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.favorite,
                                  color: Color(0xFFFF6B6B),
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'YOUR COMMENT',
                                  style: TextStyle(
                                    color: Color(0xFFFF6B6B),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.notification.message ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onViewAllComments,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.comment, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'View All Comments',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoadingAudio ? null : _playAudio,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFF7C3AED)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoadingAudio
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF7C3AED),
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_filled,
                            size: 18,
                            color: Color(0xFF7C3AED),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Play Audio',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}
