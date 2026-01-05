import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/communitypost_service.dart';
import '../services/auth_service.dart';
import 'community_comments_sheet.dart';

class _CommunityPostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isOwnProfile;
  final VoidCallback onUpdate;

  const _CommunityPostCard({
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

  bool _isLiked = false;
  int _likesCount = 0;
  int _commentsCount = 0;
  bool _isPlayingAudio = false;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  int _currentImageIndex = 0;

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
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final result = await _communityService.togglePostLike(widget.post['id']);

    if (result != null && mounted) {
      setState(() {
        _isLiked = result['is_liked'] ?? false;
        _likesCount = result['likes_count'] ?? 0;
      });
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

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommunityCommentsSheet(
        postId: widget.post['id'],
        postTitle: 'Post',
        postAuthorId: widget.post['user']['id'],
      ),
    ).then((_) {
      _refreshCommentsCount();
    });
  }

  Future<void> _refreshCommentsCount() async {
    final result = await _communityService.getCommunityPostById(
      widget.post['id'],
    );
    if (result != null && mounted) {
      setState(() {
        _commentsCount = result['comments_count'] ?? 0;
      });
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

  @override
  Widget build(BuildContext context) {
    final user = widget.post['user'] as Map<String, dynamic>;
    final content = widget.post['content'] as String?;
    final images = widget.post['images'] as List? ?? [];
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
                    onPressed: _deletePost,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
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

          if (audioUrl != null)
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
                  onTap: _toggleLike,
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
