class UserSearchResult {
  final int id;
  final String username;
  final String fullName;
  final String? profilePic;
  final String? bio;
  final bool isVerified;
  final int followersCount;
  final int totalAudios;
  final int totalListeners;
  final bool isFollowing;

  UserSearchResult({
    required this.id,
    required this.username,
    required this.fullName,
    this.profilePic,
    this.bio,
    required this.isVerified,
    required this.followersCount,
    required this.totalAudios,
    required this.totalListeners,
    required this.isFollowing,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String? ?? 'Unknown',
      profilePic: json['profile_pic'] as String?,
      bio: json['bio'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      followersCount: json['followers_count'] as int? ?? 0,
      totalAudios: json['total_audios'] as int? ?? 0,
      totalListeners: json['total_listeners'] as int? ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
    );
  }

  UserSearchResult copyWith({
    bool? isFollowing,
    int? followersCount,
  }) {
    return UserSearchResult(
      id: id,
      username: username,
      fullName: fullName,
      profilePic: profilePic,
      bio: bio,
      isVerified: isVerified,
      followersCount: followersCount ?? this.followersCount,
      totalAudios: totalAudios,
      totalListeners: totalListeners,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }

  String formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}