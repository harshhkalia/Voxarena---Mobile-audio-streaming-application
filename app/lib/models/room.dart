class Room {
  final int id;
  final String title;
  final String hostName;
  final String hostAvatar;
  final int hostId;
  final int listenerCount;
  final String topic;
  final bool isLive;
  final String? thumbnail;
  final int? duration;
  final DateTime createdAt;
  final String? audioUrl;
  final int? likesCount;
  final int? totalListens;
  final bool? isPrivate;
  final int hostFollowersCount;
  final String? description;
  final Map<String, dynamic>? host;

  Room({
    required this.id,
    required this.title,
    required this.hostName,
    required this.hostAvatar,
    required this.hostId,
    required this.listenerCount,
    required this.topic,
    this.isLive = true,
    this.thumbnail,
    this.duration,
    required this.createdAt,
    this.audioUrl,
    this.likesCount,
    this.totalListens,
    this.isPrivate,
    this.hostFollowersCount = 0,
    this.description,
    this.host,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    final hostObj = json['host'] as Map<String, dynamic>?;

    final hostName =
        hostObj?['full_name'] as String? ??
        (json['host_name'] as String?) ??
        'Unknown';

    final hostAvatar =
        hostObj?['profile_pic'] as String? ??
        (json['host_avatar'] as String?) ??
        '';

    final hostId = parseInt(hostObj?['id'] ?? json['host_id'], 0);

    int hostFollowers = 0;
    if (hostObj != null && hostObj['followers_count'] != null) {
      hostFollowers = parseInt(hostObj['followers_count'], 0);
    } else if (json['host_followers_count'] != null) {
      hostFollowers = parseInt(json['host_followers_count'], 0);
    }

    final thumbnailVal = json['thumbnail_url'];
    final thumbnail = thumbnailVal == null ? null : thumbnailVal.toString();

    final createdAtStr = json['created_at'] as String?;
    DateTime createdAt;
    try {
      createdAt = createdAtStr != null
          ? DateTime.parse(createdAtStr)
          : DateTime.now();
    } catch (_) {
      createdAt = DateTime.now();
    }

    return Room(
      id: parseInt(json['id']),
      title: json['title'] as String? ?? 'Untitled',
      hostName: hostName,
      hostAvatar: hostAvatar,
      hostId: hostId,
      listenerCount: parseInt(json['listener_count']),
      topic: json['topic'] as String? ?? '',
      isLive: json['is_live'] == true,
      thumbnail: thumbnail,
      duration: json['duration'] == null ? null : parseInt(json['duration']),
      createdAt: createdAt,
      audioUrl: json['audio_url'] as String?,
      likesCount: parseInt(json['likes_count']),
      totalListens: parseInt(json['total_listens']),
      isPrivate: (json['is_private'] == true),
      hostFollowersCount: hostFollowers,
      description: json['description'] as String?,
      host: hostObj,
    );
  }

  String get formattedDuration {
    if (duration == null) return '';
    final hours = duration! ~/ 3600;
    final minutes = (duration! % 3600) ~/ 60;
    final seconds = duration! % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Room copyWith({
    int? id,
    String? title,
    String? audioUrl,
    String? thumbnail,
    String? topic,
    int? likesCount,
    String? hostName,
    String? hostAvatar,
    int? listenerCount,
    int? hostId,
    int? hostFollowersCount,
    int? totalListens,
    DateTime? createdAt,
    bool? isLive,
    int? duration,
    String? description,
  }) {
    return Room(
      id: id ?? this.id,
      title: title ?? this.title,
      audioUrl: audioUrl ?? this.audioUrl,
      thumbnail: thumbnail ?? this.thumbnail,
      topic: topic ?? this.topic,
      likesCount: likesCount ?? this.likesCount,
      hostName: hostName ?? this.hostName,
      hostAvatar: hostAvatar ?? this.hostAvatar,
      listenerCount: listenerCount ?? this.listenerCount,
      hostId: hostId ?? this.hostId,
      hostFollowersCount: hostFollowersCount ?? this.hostFollowersCount,
      totalListens: totalListens ?? this.totalListens,
      createdAt: createdAt ?? this.createdAt,
      isLive: isLive ?? this.isLive,
      duration: duration ?? this.duration,
      description: description ?? this.description,
    );
  }

  factory Room.fromSearchJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      title: json['title'] ?? 'Untitled',
      hostName: json['host_name'] ?? 'Unknown',
      hostAvatar: json['host_avatar'] ?? '',
      topic: json['topic'] ?? '',
      listenerCount: json['listener_count'] ?? 0,
      isLive: json['is_live'] ?? false,
      thumbnail: json['thumbnail_url'],
      duration: json['duration'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      audioUrl: json['audio_url'],
      description: json['description'],
      hostId: json['host_id'],
      likesCount: json['likes_count'] ?? 0,
      totalListens: json['total_listens'] ?? 0,
      hostFollowersCount: json['host_followers_count'] ?? 0,
    );
  }

  static List<Room> getDummyLiveRooms() {
    return [
      Room(
        id: 1,
        title: 'Late Night Gaming Chat',
        hostName: 'ProGamer_XYZ',
        hostAvatar: '🎮',
        listenerCount: 2341,
        hostId: 1,
        topic: 'Gaming',
        isLive: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      Room(
        id: 2,
        title: 'Tech Talk: AI Revolution',
        hostName: 'TechGuru',
        hostAvatar: '💻',
        listenerCount: 1567,
        topic: 'Technology',
        hostId: 1,
        isLive: true,
        createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
      ),
      Room(
        id: 3,
        title: 'Chill Beats & Vibes',
        hostName: 'DJ_Mixer',
        hostAvatar: '🎵',
        listenerCount: 890,
        topic: 'Music',
        isLive: true,
        hostId: 1,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      Room(
        id: 4,
        title: 'Startup Founder Stories',
        hostName: 'EntrepreneurLife',
        hostAvatar: '💼',
        hostId: 1,
        listenerCount: 543,
        topic: 'Business',
        isLive: true,
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
    ];
  }

  static List<Room> getDummyRecordedContent() {
    return [
      Room(
        id: 101,
        title: 'How I Built a Million Dollar App',
        hostName: 'StartupSteve',
        hostAvatar: '💡',
        listenerCount: 45230,
        topic: 'Business',
        isLive: false,
        duration: 3420,
        hostId: 1,
        thumbnail: 'https://picsum.photos/seed/1/400/300',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Room(
        id: 102,
        title: 'The Future of AI in 2025',
        hostName: 'TechVisionary',
        hostAvatar: '🤖',
        listenerCount: 32100,
        topic: 'Technology',
        isLive: false,
        duration: 2580,
        hostId: 1,
        thumbnail: 'https://picsum.photos/seed/2/400/300',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Room(
        id: 103,
        title: 'Meditation & Mindfulness Guide',
        hostName: 'ZenMaster',
        hostAvatar: '🧘',
        listenerCount: 18900,
        topic: 'Health',
        isLive: false,
        hostId: 1,
        duration: 1800,
        thumbnail: 'https://picsum.photos/seed/3/400/300',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      Room(
        id: 104,
        title: 'Top 10 Gaming Moments of 2024',
        hostName: 'GameReviewer',
        hostAvatar: '🎮',
        listenerCount: 67800,
        topic: 'Gaming',
        isLive: false,
        hostId: 1,
        duration: 4200,
        thumbnail: 'https://picsum.photos/seed/4/400/300',
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      ),
      Room(
        id: 105,
        title: 'Learn Python in 1 Hour',
        hostName: 'CodeAcademy',
        hostAvatar: '🐍',
        listenerCount: 89400,
        topic: 'Education',
        hostId: 1,
        isLive: false,
        duration: 3600,
        thumbnail: 'https://picsum.photos/seed/5/400/300',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      Room(
        id: 106,
        title: 'Jazz Piano Improvisation',
        hostName: 'JazzPianist',
        hostAvatar: '🎹',
        listenerCount: 12300,
        topic: 'Music',
        hostId: 1,
        isLive: false,
        duration: 2700,
        thumbnail: 'https://picsum.photos/seed/6/400/300',
        createdAt: DateTime.now().subtract(const Duration(days: 4)),
      ),
    ];
  }
}
