import 'package:flutter/material.dart';
import '../models/user_search_result.dart';
import '../services/follow_service.dart';
import '../screens/profile_screen.dart';

class UserCard extends StatefulWidget {
  final UserSearchResult user;
  final bool isFollowing;
  final Function(bool) onFollowChanged;
    final int? currentUserId;

  const UserCard({
    super.key,
    required this.user,
    required this.isFollowing,
    required this.onFollowChanged,
      required this.currentUserId,
  });

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  final _followService = FollowService();
  bool _isLoading = false;

  bool get isOwnProfile =>
    widget.currentUserId != null &&
    widget.currentUserId == widget.user.id;

  Future<void> _toggleFollow() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final result = await _followService.toggleFollow(widget.user.id);

      if (result != null && mounted) {
        final newStatus = result['is_following'] as bool? ?? false;
        widget.onFollowChanged(newStatus);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newStatus ? 'Following!' : 'Unfollowed'),
              backgroundColor: const Color(0xFF7C3AED),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update follow status: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withOpacity(0.2),
        ),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(userId: widget.user.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildProfilePicture(),
              const SizedBox(width: 16),
              Expanded(child: _buildUserInfo()),

              const SizedBox(width: 12),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
  if (isOwnProfile) {
    return TextButton(
      onPressed: () {
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
          borderRadius: BorderRadius.circular(20),
        ),
        minimumSize: const Size(110, 36),
      ),
      child: const Text(
        'Visit Channel',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  if (_isLoading) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFF7C3AED),
      ),
    );
  }

  return TextButton(
    onPressed: _toggleFollow,
    style: TextButton.styleFrom(
      foregroundColor:
          widget.isFollowing ? const Color(0xFF7C3AED) : Colors.white,
      backgroundColor:
          widget.isFollowing ? Colors.transparent : const Color(0xFF7C3AED),
      side: widget.isFollowing
          ? const BorderSide(color: Color(0xFF7C3AED))
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 8,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      minimumSize: const Size(90, 36),
    ),
    child: Text(
      widget.isFollowing ? 'Following' : 'Follow',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

  Widget _buildProfilePicture() {
    return CircleAvatar(
      radius: 32,
      backgroundColor: const Color(0xFF7C3AED).withOpacity(0.2),
      backgroundImage: widget.user.profilePic != null &&
              widget.user.profilePic!.isNotEmpty
          ? NetworkImage(widget.user.profilePic!)
          : null,
      child: widget.user.profilePic == null || widget.user.profilePic!.isEmpty
          ? const Icon(
              Icons.person,
              color: Color(0xFF7C3AED),
              size: 32,
            )
          : null,
    );
  }

  Widget _buildUserInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                widget.user.fullName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.user.isVerified) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.verified,
                size: 16,
                color: Color(0xFF7C3AED),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),

        Text(
          '@${widget.user.username}',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        _buildStats(),

        if (widget.user.bio != null && widget.user.bio!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.user.bio!,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildStats() {
    return Wrap(
      spacing: 8,
      children: [
        Text(
          '${widget.user.formatCount(widget.user.followersCount)} followers',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        Text(
          '• ${widget.user.totalAudios} audios',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        Text(
          '• ${widget.user.formatCount(widget.user.totalListeners)} plays',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}