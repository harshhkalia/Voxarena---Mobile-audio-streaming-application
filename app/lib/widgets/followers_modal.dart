import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:app/services/follow_service.dart';
import 'package:app/screens/profile_screen.dart';

class FollowersModal extends StatefulWidget {
  final int userId;
  final bool isOwnProfile;
  final VoidCallback? onFollowerRemoved;

  const FollowersModal({
    super.key,
    required this.userId,
    required this.isOwnProfile,
    this.onFollowerRemoved,
  });

  @override
  State<FollowersModal> createState() => _FollowersModalState();
}

class _FollowersModalState extends State<FollowersModal> {
  final _storage = const FlutterSecureStorage();
  final TextEditingController _searchController = TextEditingController();
  final _followService = FollowService();
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  List<Map<String, dynamic>> _allFollowers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<int> _removingFollowers = {};

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers({bool loadMore = false}) async {
    if (_isFetchingMore || (!_hasMore && loadMore)) return;

    setState(() {
      _isFetchingMore = true;
      if (!loadMore) _isLoading = true;
    });

    try {
      final response = await _followService.getFollowers(
        widget.userId,
        page: _page,
        limit: _limit,
      );

      if (!mounted || response == null) return;

      final List followers = response['followers'] ?? [];

      setState(() {
        if (loadMore) {
          _allFollowers.addAll(
            followers.map((e) => Map<String, dynamic>.from(e)),
          );
        } else {
          _allFollowers =
              followers.map((e) => Map<String, dynamic>.from(e)).toList();
        }

        _filteredFollowers = List.from(_allFollowers);
        _hasMore = response['has_more'] ?? false;
        _page++;
        _isLoading = false;
        _isFetchingMore = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _isFetchingMore = false;
      });
    }
  }

  void _filterFollowers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredFollowers = _allFollowers;
      } else {
        _filteredFollowers = _allFollowers.where((follower) {
          final username = (follower['username'] ?? '').toString().toLowerCase();
          final fullName = (follower['full_name'] ?? '').toString().toLowerCase();
          return username.contains(_searchQuery) || fullName.contains(_searchQuery);
        }).toList();
      }
    });
  }

Future<void> _removeFollower(int followerId) async {
  if (_removingFollowers.contains(followerId)) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: const Text(
        'Remove Follower?',
        style: TextStyle(color: Colors.white),
      ),
      content: const Text(
        'Are you sure you want to remove this follower? They won\'t be notified.',
        style: TextStyle(color: Colors.grey),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final followerToRemove = _allFollowers.firstWhere(
    (f) => f['id'] == followerId,
    orElse: () => {},
  );
  final username = followerToRemove['username'] ?? 'this user';

  setState(() {
    _removingFollowers.add(followerId);
  });

  try {
    final response = await _followService.removeFollower(followerId);

    if (response == null || response['success'] != true) {
      throw Exception('Failed to remove follower');
    }

    final bool isStillFollowing = response['is_following'] == true;

    if (!mounted) return;

    setState(() {
      _allFollowers.removeWhere((f) => f['id'] == followerId);
      _filteredFollowers.removeWhere((f) => f['id'] == followerId);
      _removingFollowers.remove(followerId);
    });

    widget.onFollowerRemoved?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follower removed'),
          backgroundColor: Color(0xFF7C3AED),
          duration: Duration(seconds: 1),
        ),
      );
    }

    if (isStillFollowing) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        _showStillFollowingDialog(followerId, username);
      }
    }
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _removingFollowers.remove(followerId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to remove follower'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

Future<void> _showStillFollowingDialog(int followerId, String username) async {
  int countdown = 8;
  bool isUnfollowing = false;
  
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        if (countdown == 8) {
          Future.doWhile(() async {
            await Future.delayed(const Duration(seconds: 1));
            if (!context.mounted || countdown <= 0) return false;
            
            setDialogState(() {
              countdown--;
            });
            
            if (countdown <= 0) {
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              return false;
            }
            return true;
          });
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFF7C3AED),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Still Following',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${countdown}s',
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'You still follow @$username. Would you like to unfollow them?',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 15,
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUnfollowing
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isUnfollowing ? Colors.grey : Colors.white,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isUnfollowing
                  ? null
                  : () async {
                      setDialogState(() {
                        isUnfollowing = true;
                      });

                      try {
                        final result = await _followService.toggleFollow(
                          followerId,
                        );

                        if (!dialogContext.mounted) return;

                        Navigator.pop(dialogContext);

                        if (result != null &&
                            result['is_following'] == false) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Unfollowed successfully'),
                              backgroundColor: Color(0xFF7C3AED),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to unfollow'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        
                        Navigator.pop(dialogContext);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to unfollow'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: isUnfollowing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Unfollow'),
            ),
          ],
        );
      },
    ),
  );
}

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Unknown';
    
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays < 1) {
        if (difference.inHours < 1) {
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()}w ago';
      } else if (difference.inDays < 365) {
        return '${(difference.inDays / 30).floor()}mo ago';
      } else {
        return DateFormat('MMM d, y').format(date);
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatFollowerCount(int? count) {
    if (count == null || count == 0) return '0';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F0F1E),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Followers',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_filteredFollowers.length}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF7C3AED).withOpacity(0.3),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterFollowers,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search followers...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF7C3AED),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                _filterFollowers('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF7C3AED),
                        ),
                      )
                    : _filteredFollowers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.people_outline
                                      : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No followers yet'
                                      : 'No followers found',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredFollowers.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredFollowers.length) {
                                _loadFollowers(loadMore: true);
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                                );
                              }
                              
                              final follower = _filteredFollowers[index];
                              final followerId = follower['id'] as int;
                              final username = follower['username'] as String? ?? 'unknown';
                              final fullName = follower['full_name'] as String? ?? 'Unknown User';
                              final profilePic = follower['profile_pic'] as String?;
                              final followersCount = follower['followers_count'] as int? ?? 0;
                              final followedAt = follower['followed_at'] as String?;
                              final isRemoving = _removingFollowers.contains(followerId);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A2E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF7C3AED).withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pop(context); 
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ProfileScreen(userId: followerId),
                                          ),
                                        );
                                      },
                                      child: CircleAvatar(
                                        radius: 28,
                                        backgroundColor: const Color(0xFF7C3AED).withOpacity(0.2),
                                        backgroundImage: profilePic != null && profilePic.isNotEmpty
                                            ? NetworkImage(profilePic)
                                            : null,
                                        child: profilePic == null || profilePic.isEmpty
                                            ? const Icon(
                                                Icons.person,
                                                color: Color(0xFF7C3AED),
                                                size: 28,
                                              )
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.pop(context); 
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ProfileScreen(userId: followerId),
                                            ),
                                          );
                                        },
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fullName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '@$username',
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  '${_formatFollowerCount(followersCount)} followers',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '• ${_formatDate(followedAt)}',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    if (widget.isOwnProfile)
                                      isRemoving
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF7C3AED),
                                              ),
                                            )
                                          : IconButton(
                                              onPressed: () => _removeFollower(followerId),
                                              icon: const Icon(
                                                Icons.person_remove,
                                                color: Colors.red,
                                                size: 22,
                                              ),
                                              tooltip: 'Remove follower',
                                            ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}