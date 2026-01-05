import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../services/download_tracking_service.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/like_service.dart';
import '../services/follow_service.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/room_card.dart';
import '../models/room.dart';
import 'profile_screen.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class DownloadHistoryScreen extends StatefulWidget {
  const DownloadHistoryScreen({super.key});

  @override
  State<DownloadHistoryScreen> createState() => _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends State<DownloadHistoryScreen> {
  final DownloadTrackingService _downloadService = DownloadTrackingService();
  final GlobalAudioService _audio = GlobalAudioService();
  final AuthService _authService = AuthService();
  final _storage = const FlutterSecureStorage();

  List<Map<String, dynamic>> downloadHistory = [];
  bool isLoading = false;

  int _page = 1;
  final int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDownloadHistory(reset: true);
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

  Future<void> _loadDownloadHistory({bool reset = false}) async {
    if (reset) {
      setState(() {
        isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _page = 1;
        downloadHistory = [];
      });
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final data = await _downloadService.getDownloadHistory(
        page: _page,
        limit: _pageSize,
      );

      if (data != null && data['downloads'] != null) {
        final downloadsList = data['downloads'] as List;

        final fetched = downloadsList.map((item) {
          return item as Map<String, dynamic>;
        }).toList();

        setState(() {
          if (reset) {
            downloadHistory = fetched;
          } else {
            downloadHistory.addAll(fetched);
          }

          if (data['has_more'] != null) {
            _hasMore = data['has_more'] == true;
          } else {
            _hasMore = fetched.length == _pageSize;
          }

          _page += 1;
          isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          isLoading = false;
          _isLoadingMore = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error loading download history: $e');
      setState(() {
        isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || isLoading) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadDownloadHistory(reset: false);
    }
  }

  Future<void> _deleteDownloadItem(int downloadId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove from download history?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove this entry from your download history. The downloaded file will remain on your device.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Color(0xFF7C3AED)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _downloadService.deleteDownloadHistory(downloadId);

      if (success) {
        setState(() {
          downloadHistory.removeWhere((item) => item['id'] == downloadId);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from download history'),
            backgroundColor: Color(0xFF7C3AED),
          ),
        );
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

  Future<void> _clearAllDownloads() async {
    if (downloadHistory.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear all download history?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will clear your entire download history. Downloaded files will remain on your device.',
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
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await _downloadService.clearAllDownloadHistory();

      if (success) {
        setState(() {
          downloadHistory.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download history cleared'),
            backgroundColor: Color(0xFF7C3AED),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear history'),
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

  Future<void> _downloadAgain(Map<String, dynamic> downloadItem) async {
    final room = downloadItem['room'] as Map<String, dynamic>?;
    if (room == null) return;

    final audioUrl = room['audio_url'] as String?;
    final title = room['title'] as String? ?? 'audio';

    if (audioUrl == null || audioUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio URL found'),
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
          ScaffoldMessenger.of(context).showSnackBar(
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
            await _downloadService.trackDownload(
              roomId: room['id'] as int,
              fileName: fileName,
              downloadPath: '$savedDir/$fileName',
            );

            ScaffoldMessenger.of(context).showSnackBar(
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
          ScaffoldMessenger.of(context).showSnackBar(
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

      await _downloadService.trackDownload(
        roomId: room['id'] as int,
        fileName: fileName,
        downloadPath: '$savedDir/$fileName',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download started'),
          backgroundColor: Color(0xFF7C3AED),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDownloadDate(String? downloadedAt) {
    if (downloadedAt == null) return '';
    
    try {
      final dt = DateTime.parse(downloadedAt).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inDays == 0) {
        return 'Downloaded today at ${DateFormat('h:mm a').format(dt)}';
      }
      else if (diff.inDays == 1) {
        return 'Downloaded yesterday at ${DateFormat('h:mm a').format(dt)}';
      }
      else if (diff.inDays < 7) {
        return 'Downloaded ${DateFormat('EEEE').format(dt)} at ${DateFormat('h:mm a').format(dt)}';
      }
      else {
        return 'Downloaded ${DateFormat('MMM d, yyyy').format(dt)}';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Download History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          if (downloadHistory.isNotEmpty)
            IconButton(
              onPressed: _clearAllDownloads,
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : downloadHistory.isEmpty
          ? RefreshIndicator(
              onRefresh: () => _loadDownloadHistory(reset: true),
              child: ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.download_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No downloads yet',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadDownloadHistory(reset: true),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: downloadHistory.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == downloadHistory.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _buildDownloadCard(downloadHistory[index]);
                },
              ),
            ),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

 Widget _buildDownloadCard(Map<String, dynamic> downloadItem) {
  final room = downloadItem['room'] as Map<String, dynamic>?;
  if (room == null) return const SizedBox.shrink();

  final downloadId = downloadItem['id'] as int;
  final fileName = downloadItem['file_name'] as String? ?? 'Unknown';
  final downloadedAt = downloadItem['created_at'] as String?;
  
  final host = room['host'] as Map<String, dynamic>?;
  final hostName = host?['full_name'] as String? ?? 'Unknown';
  final hostAvatar = host?['profile_pic'] as String?;
  final hostId = host?['id'] as int?;
  
  final currentUserId = _authService.currentUser?['id'] as int?;
  final isOwnAudio = hostId != null && currentUserId != null && hostId == currentUserId;

  final title = room['title'] as String? ?? 'Untitled';
  final topic = room['topic'] as String? ?? '';
  final thumbUrl = room['thumbnail_url'] as String?;
  final duration = (room['duration'] ?? 0) as int;
  final minutes = duration ~/ 60;
  final seconds = duration % 60;

  final downloadDateText = _formatDownloadDate(downloadedAt);

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          errorBuilder: (context, error, stackTrace) =>
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
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const Divider(color: Colors.grey, height: 1),
        
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
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
                          radius: 16,
                          backgroundColor: const Color(0xFF0F0F1E),
                          backgroundImage:
                              (hostAvatar != null && hostAvatar.isNotEmpty)
                                  ? NetworkImage(hostAvatar)
                                  : null,
                          child: (hostAvatar == null || hostAvatar.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white70,
                                  size: 16,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hostName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteDownloadItem(downloadId),
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      label: const Text('Remove', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadAgain(downloadItem),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7C3AED),
                        side: const BorderSide(color: Color(0xFF7C3AED)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              if (downloadDateText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.download_done_rounded,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        downloadDateText,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
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
            const Icon(
              Icons.check,
              color: Color(0xFF7C3AED),
              size: 18,
            ),
        ],
      ),
    );
  }

  void _updateHostFollowersInRooms(int hostId, bool isFollowing) {
    final homeScreenState = context
        .findAncestorStateOfType<_DownloadHistoryScreenState>();
    if (homeScreenState != null) {
      homeScreenState.setState(() {
        for (var i = 0; i < homeScreenState.downloadHistory.length; i++) {
          final room = homeScreenState.downloadHistory[i]['room'] as Map<String, dynamic>?;
          if (room == null) continue;
          final host = room['host'] as Map<String, dynamic>?;
          if (host == null) continue;
          if (host['id'] == hostId) {
            final current = host['followers_count'] is int
                ? host['followers_count']
                : int.tryParse(host['followers_count']?.toString() ?? '0') ?? 0;
            host['followers_count'] = current + (isFollowing ? 1 : -1);
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
                        horizontal: 16, vertical: 12),
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
                                horizontal: 12, vertical: 6),
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
