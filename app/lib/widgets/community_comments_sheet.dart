import 'package:app/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import '../services/communitypost_service.dart';
import '../services/auth_service.dart';

class CommunityCommentsSheet extends StatefulWidget {
  final int postId;
  final String postTitle;
  final int postAuthorId;
  final Function(int)? onCommentCountChanged;

  const CommunityCommentsSheet({
    super.key,
    required this.postId,
    required this.postTitle,
    required this.postAuthorId,
    this.onCommentCountChanged,
  });

  @override
  State<CommunityCommentsSheet> createState() => _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<CommunityCommentsSheet> {
  final _communityService = CommunityService();
  final _authService = AuthService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  Map<String, dynamic>? _replyingTo;

  // Track ongoing like operations to prevent race conditions
  final Set<int> _likingComments = {};

  @override
  void initState() {
    super.initState();
    _loadComments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreComments();
      }
    }
  }

  bool get _isPostOwner {
    final currentUserId = _authService.currentUser?['id'];
    if (currentUserId == null) return false;

    final int? currentId = currentUserId is int
        ? currentUserId
        : int.tryParse(currentUserId.toString());

    return currentId != null && currentId == widget.postAuthorId;
  }

  Future<void> _loadComments({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _page = 1;
        _comments = [];
        _hasMore = true;
      });
    }

    final result = await _communityService.getPostComments(
      widget.postId,
      page: _page,
    );

    if (result != null && mounted) {
      setState(() {
        _comments = List<Map<String, dynamic>>.from(
          (result['comments'] ?? []).map((c) {
            final comment = Map<String, dynamic>.from(c as Map);
            final previewReplies = List<Map<String, dynamic>>.from(
              (comment['replies'] ?? []).map(
                (r) => Map<String, dynamic>.from(r as Map),
              ),
            );
            return {
              ...comment,
              'preview_replies': previewReplies,
              'replies': previewReplies,
              'expanded': false,
              'replies_page': 0,
              'replies_loading': false,
              'replies_has_more':
                  (comment['replies_count'] ?? 0) > previewReplies.length,
            };
          }),
        );
        _hasMore = result['has_more'] ?? false;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final nextPage = _page + 1;
    final result = await _communityService.getPostComments(
      widget.postId,
      page: nextPage,
    );

    if (!mounted) return;

    if (result != null) {
      final newComments = List<Map<String, dynamic>>.from(
        (result['comments'] ?? []).map((c) {
          final comment = Map<String, dynamic>.from(c as Map);
          final previewReplies = List<Map<String, dynamic>>.from(
            (comment['replies'] ?? []).map(
              (r) => Map<String, dynamic>.from(r as Map),
            ),
          );
          return {
            ...comment,
            'preview_replies': previewReplies,
            'replies': previewReplies,
            'expanded': false,
            'replies_page': 0,
            'replies_loading': false,
            'replies_has_more':
                (comment['replies_count'] ?? 0) > previewReplies.length,
          };
        }),
      );

      setState(() {
        _page = nextPage;
        _comments.addAll(newComments);
        _hasMore = result['has_more'] ?? false;
        _isLoadingMore = false;
      });
    } else {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadReplies(int commentIndex) async {
    final comment = _comments[commentIndex];
    if (comment['id'] == null) return;

    if (comment['replies_loading'] == true ||
        comment['replies_has_more'] == false) {
      return;
    }

    final int currentPage = (comment['replies_page'] is int)
        ? comment['replies_page']
        : 0;
    final int nextPage = currentPage + 1;

    setState(() {
      comment['replies_loading'] = true;
    });

    final result = await _communityService.getCommentReplies(
      comment['id'] as int,
      page: nextPage,
    );

    if (!mounted) return;

    if (result != null) {
      final allReplies = List<Map<String, dynamic>>.from(
        (result['replies'] ?? []).map(
          (r) => Map<String, dynamic>.from(r as Map),
        ),
      );

      List<Map<String, dynamic>> newReplies = allReplies;

      if (nextPage == 1) {
        final existingIds = (comment['replies'] as List)
            .map((r) => r['id'])
            .toSet();
        newReplies = allReplies
            .where((r) => !existingIds.contains(r['id']))
            .toList();
      }

      setState(() {
        comment['expanded'] = true;
        comment['replies'] = [...(comment['replies'] as List), ...newReplies];
        comment['replies_page'] = nextPage;
        comment['replies_has_more'] = result['has_more'] ?? false;
        comment['replies_loading'] = false;
      });
    } else {
      setState(() {
        comment['replies_loading'] = false;
      });
    }
  }

  void _collapseReplies(int index) {
    final comment = _comments[index];
    setState(() {
      comment['expanded'] = false;
      final preview = comment['preview_replies'];
      comment['replies'] = preview is List
          ? List<Map<String, dynamic>>.from(
              preview.map((r) => Map<String, dynamic>.from(r as Map)),
            )
          : [];
      comment['replies_page'] = 0;
      comment['replies_has_more'] =
          (comment['replies_count'] ?? 0) > (comment['replies'] as List).length;
    });
  }

  Future<void> _postComment() async {
    String content = _textController.text.trim();
    if (content.isEmpty) return;

    if (_replyingTo != null && _replyingTo!['parent_id'] != null) {
      final username = _replyingTo!['user']['username'];
      final mention = '@$username ';
      if (content.startsWith(mention)) {
        content = content.substring(mention.length).trim();
      }
    }

    _textController.clear();
    FocusScope.of(context).unfocus();

    final int? parentId;
    final int? replyToUserId;

    if (_replyingTo != null) {
      if (_replyingTo!['parent_id'] != null) {
        parentId = _replyingTo!['parent_id'];
        replyToUserId = _replyingTo!['user']['id'];
      } else {
        parentId = _replyingTo!['id'];
        replyToUserId = null;
      }
    } else {
      parentId = null;
      replyToUserId = null;
    }

    final result = await _communityService.createComment(
      widget.postId,
      content,
      parentId: parentId,
      replyToUserId: replyToUserId,
    );

    if (result != null && mounted) {
      setState(() => _replyingTo = null);
      await _loadComments(reset: true);

      if (widget.onCommentCountChanged != null) {
        widget.onCommentCountChanged!(_comments.length);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment posted!'),
          backgroundColor: Color(0xFF7C3AED),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _toggleCommentLike(int commentId, int index, {bool isReply = false, int? replyIndex, int? parentIndex}) async {
    if (_likingComments.contains(commentId)) return;
    
    _likingComments.add(commentId);

    try {
      final comment = isReply 
          ? (_comments[parentIndex!]['replies'] as List)[replyIndex!]
          : _comments[index];
      
      final previousLiked = comment['is_liked'] ?? false;
      final previousCount = comment['likes_count'] ?? 0;
      
      setState(() {
        comment['is_liked'] = !previousLiked;
        comment['likes_count'] = previousLiked ? previousCount - 1 : previousCount + 1;
      });

      final result = await _communityService.toggleCommentLike(commentId);

      if (result != null && mounted) {
        setState(() {
          comment['is_liked'] = result['liked'] ?? previousLiked;
          comment['likes_count'] = result['likes_count'] ?? previousCount;
        });
      } else {
        if (mounted) {
          setState(() {
            comment['is_liked'] = previousLiked;
            comment['likes_count'] = previousCount;
          });
        }
      }
    } finally {
      _likingComments.remove(commentId);
    }
  }

  Future<void> _deleteComment(int commentId, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Comment?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This comment will be permanently deleted.',
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
      final success = await _communityService.deleteComment(commentId);
      if (success != null && mounted) {
        await _loadComments(reset: true);
        
        if (widget.onCommentCountChanged != null) {
          widget.onCommentCountChanged!(_comments.length);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment deleted')),
        );
      }
    }
  }

  void _navigateToUserProfile(dynamic userId) {
    if (userId == null) return;

    final int? userIdInt = userId is int
        ? userId
        : int.tryParse(userId.toString());

    if (userIdInt == null) return;

    final currentUserId = _authService.currentUser?['id'];
    final int? currentUserIdInt = currentUserId is int
        ? currentUserId
        : int.tryParse(currentUserId?.toString() ?? '');

    final bool isOwnProfile =
        currentUserIdInt != null && currentUserIdInt == userIdInt;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isOwnProfile
            ? const ProfileScreen()
            : ProfileScreen(userId: userIdInt),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return AnimatedPadding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          duration: const Duration(milliseconds: 100),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Comments',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _comments.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.comment_outlined, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No comments yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                              SizedBox(height: 8),
                              Text('Be the first to comment!', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: _comments.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _comments.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final comment = _comments[index];
                            return _buildCommentItem(comment, index);
                          },
                        ),
                ),

                if (_replyingTo != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFF1A1A2E),
                    child: Row(
                      children: [
                        const Icon(Icons.reply, color: Color(0xFF7C3AED), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Replying to ${_replyingTo!['user']['full_name']}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _replyingTo = null),
                          icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: 16 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    border: Border(top: BorderSide(color: Colors.grey[800]!)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF7C3AED),
                        backgroundImage: _authService.currentUser?['profile_pic'] != null
                            ? NetworkImage(_authService.currentUser!['profile_pic'])
                            : null,
                        child: _authService.currentUser?['profile_pic'] == null
                            ? const Icon(Icons.person, size: 20)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: 1,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F0F1E),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _postComment,
                        icon: const Icon(Icons.send, color: Color(0xFF7C3AED)),
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

  Widget _buildCommentItem(Map<String, dynamic> comment, int index) {
    final user = comment['user'] as Map<String, dynamic>;
    final currentUserId = _authService.currentUser?['id'];
    final isOwnComment = currentUserId == user['id'];
    final isLiked = comment['is_liked'] ?? false;
    final likesCount = comment['likes_count'] ?? 0;
    final repliesCount = comment['replies_count'] ?? 0;
    final replies = comment['replies'] as List? ?? [];
    final canDelete = isOwnComment || _isPostOwner;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _navigateToUserProfile(user['id']),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF7C3AED),
                  backgroundImage: user['profile_pic'] != null
                      ? NetworkImage(user['profile_pic'])
                      : null,
                  child: user['profile_pic'] == null
                      ? Text(user['full_name'][0].toUpperCase(), style: const TextStyle(color: Colors.white))
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _navigateToUserProfile(user['id']),
                          child: Text(
                            user['full_name'] ?? 'Unknown',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(comment['created_at']),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(comment['content'], style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => _toggleCommentLike(comment['id'], index),
                          child: Row(
                            children: [
                              Icon(
                                isLiked ? Icons.favorite : Icons.favorite_border,
                                size: 16,
                                color: isLiked ? const Color(0xFFEB5757) : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text('$likesCount', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _replyingTo = comment;
                              _textController.clear();
                            });
                          },
                          child: const Text('Reply', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        if (canDelete) ...[
                          const SizedBox(width: 16),
                          InkWell(
                            onTap: () => _deleteComment(comment['id'], index),
                            child: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (replies.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...replies.asMap().entries.map((entry) => _buildReplyPreview(entry.value, index, entry.key)),
          ],

          if (comment['expanded'] == true && repliesCount > replies.length)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 8),
              child: InkWell(
                onTap: () => _loadReplies(index),
                child: Text(
                  'View ${repliesCount - replies.length} more replies',
                  style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else if (comment['expanded'] == true)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 8),
              child: InkWell(
                onTap: () => _collapseReplies(index),
                child: const Text('Hide replies', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            )
          else if (repliesCount > replies.length)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 8),
              child: InkWell(
                onTap: () => _loadReplies(index),
                child: Text(
                  'View ${repliesCount - replies.length} more replies',
                  style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(Map<String, dynamic> reply, int parentIndex, int replyIndex) {
    final user = reply['user'] as Map<String, dynamic>;
    final currentUserId = _authService.currentUser?['id'];
    final isOwnReply = currentUserId == user['id'];
    final isLiked = reply['is_liked'] ?? false;
    final likesCount = reply['likes_count'] ?? 0;
    final canDelete = isOwnReply || _isPostOwner;
    final replyToUser = reply['reply_to_user'] as Map<String, dynamic>?;
    final replyToUserId = replyToUser?['id'];

    return Padding(
      padding: const EdgeInsets.only(left: 48, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _navigateToUserProfile(user['id']),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFF7C3AED),
              backgroundImage: user['profile_pic'] != null ? NetworkImage(user['profile_pic']) : null,
              child: user['profile_pic'] == null
                  ? Text(user['full_name'][0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10))
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: () => _navigateToUserProfile(user['id']),
                          child: Text(
                            user['full_name'],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' '),
                      if (replyToUser != null) ...[
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () => _navigateToUserProfile(replyToUserId),
                            child: Text(
                              '@${replyToUser['username']} ',
                              style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                      TextSpan(text: reply['content']),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _toggleCommentLike(
                        reply['id'],
                        parentIndex,
                        isReply: true,
                        replyIndex: replyIndex,
                        parentIndex: parentIndex,
                      ),
                      child: Row(
                        children: [
                          Icon(isLiked ? Icons.favorite : Icons.favorite_border, size: 14, color: isLiked ? const Color(0xFFEB5757) : Colors.grey),
                          const SizedBox(width: 4),
                          Text('$likesCount', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _replyingTo = reply;
                          final mention = '@${reply['user']['username']} ';
                          _textController.text = mention;
                        });
                      },
                      child: const Text('Reply', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    if (canDelete) ...[
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A2E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Text('Delete Reply?', style: TextStyle(color: Colors.white)),
                              content: const Text('This reply will be permanently deleted.', style: TextStyle(color: Colors.grey)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            final success = await _communityService.deleteComment(reply['id']);
                            if (success != null && mounted) {
                              await _loadComments(reset: true);
                              
                              if (widget.onCommentCountChanged != null) {
                                widget.onCommentCountChanged!(_comments.length);
                              }
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reply deleted')),
                              );
                            }
                          }
                        },
                        child: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}