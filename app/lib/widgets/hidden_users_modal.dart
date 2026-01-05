import 'package:flutter/material.dart';
import 'package:app/screens/profile_screen.dart';
import 'package:app/services/hide_service.dart';

class HiddenUsersModal extends StatefulWidget {
  final VoidCallback? onUserUnhidden;

  const HiddenUsersModal({
    super.key,
    this.onUserUnhidden,
  });

  @override
  State<HiddenUsersModal> createState() => _HiddenUsersModalState();
}

class _HiddenUsersModalState extends State<HiddenUsersModal> {
  final TextEditingController _searchController = TextEditingController();
  final _hideService = HideService();
  int _page = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isFetchingMore = false;

  List<Map<String, dynamic>> _allHiddenUsers = [];
  List<Map<String, dynamic>> _filteredHiddenUsers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<int> _unhidingUsers = {};

  @override
  void initState() {
    super.initState();
    _loadHiddenUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHiddenUsers({bool loadMore = false}) async {
    if (_isFetchingMore || (!_hasMore && loadMore)) return;

    setState(() {
      _isFetchingMore = true;
      if (!loadMore) _isLoading = true;
    });

    try {
      final response = await _hideService.getHiddenUsers(
        page: _page,
        limit: _limit,
      );

      if (!mounted || response == null) return;

      final List hiddenUsers = response['hidden_users'] ?? [];

      setState(() {
        if (loadMore) {
          _allHiddenUsers.addAll(
            hiddenUsers.map((e) => Map<String, dynamic>.from(e)),
          );
        } else {
          _allHiddenUsers =
              hiddenUsers.map((e) => Map<String, dynamic>.from(e)).toList();
        }

        _filteredHiddenUsers = List.from(_allHiddenUsers);
        _hasMore = response['has_more'] ?? false;
        _page++;
        _isLoading = false;
        _isFetchingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isFetchingMore = false;
      });
    }
  }

  void _filterHiddenUsers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredHiddenUsers = _allHiddenUsers;
      } else {
        _filteredHiddenUsers = _allHiddenUsers.where((user) {
          final username = (user['username'] ?? '').toString().toLowerCase();
          final fullName = (user['full_name'] ?? '').toString().toLowerCase();
          return username.contains(_searchQuery) ||
              fullName.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _unhideUser(int userId) async {
    if (_unhidingUsers.contains(userId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Unhide User?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This user will be able to see your content again.',
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
              backgroundColor: const Color(0xFF7C3AED),
            ),
            child: const Text('Unhide'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _unhidingUsers.add(userId);
    });

    try {
      final response = await _hideService.toggleHideUser(userId);

      if (response == null || response['is_hidden'] != false) {
        throw Exception('Failed to unhide user');
      }

      if (!mounted) return;

      setState(() {
        _allHiddenUsers.removeWhere((u) => u['id'] == userId);
        _filteredHiddenUsers.removeWhere((u) => u['id'] == userId);
        _unhidingUsers.remove(userId);
      });

      widget.onUserUnhidden?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User unhidden successfully'),
            backgroundColor: Color(0xFF7C3AED),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _unhidingUsers.remove(userId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to unhide user'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
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
        return '${date.year}';
      }
    } catch (e) {
      return 'Unknown';
    }
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Hidden Users',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_filteredHiddenUsers.length}',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                    onChanged: _filterHiddenUsers,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search hidden users...',
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
                                _filterHiddenUsers('');
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
                    : _filteredHiddenUsers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.visibility_off_outlined
                                      : Icons.search_off,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No hidden users'
                                      : 'No users found',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                                if (_searchQuery.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Users you hide won\'t see your content',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount:
                                _filteredHiddenUsers.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredHiddenUsers.length) {
                                _loadHiddenUsers(loadMore: true);
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                                );
                              }

                              final user = _filteredHiddenUsers[index];
                              final userId = user['id'] as int;
                              final username =
                                  user['username'] as String? ?? 'unknown';
                              final fullName = user['full_name'] as String? ??
                                  'Unknown User';
                              final profilePic = user['profile_pic'] as String?;
                              final hiddenAt = user['hidden_at'] as String?;
                              final isUnhiding = _unhidingUsers.contains(userId);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A2E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFF7C3AED)
                                        .withOpacity(0.2),
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
                                            builder: (_) =>
                                                ProfileScreen(userId: userId),
                                          ),
                                        );
                                      },
                                      child: CircleAvatar(
                                        radius: 28,
                                        backgroundColor: const Color(0xFF7C3AED)
                                            .withOpacity(0.2),
                                        backgroundImage: profilePic != null &&
                                                profilePic.isNotEmpty
                                            ? NetworkImage(profilePic)
                                            : null,
                                        child: profilePic == null ||
                                                profilePic.isEmpty
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
                                              builder: (_) => ProfileScreen(
                                                  userId: userId),
                                            ),
                                          );
                                        },
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                            Text(
                                              'Hidden ${_formatDate(hiddenAt)}',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    isUnhiding
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF7C3AED),
                                            ),
                                          )
                                        : ElevatedButton(
                                            onPressed: () => _unhideUser(userId),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF7C3AED),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            child: const Text(
                                              'Unhide',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
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