class AppNotification {
  final int id;
  final int userId;
  final int actorId;
  final String type;
  final String title;
  final String? message;
  final String? extraData;  // Original comment content for replies
  final int? referenceId;
  final String? referenceType;
  final String? imageUrl;
  final String? actionUrl;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  final NotificationActor? actor;

  AppNotification({
    required this.id,
    required this.userId,
    required this.actorId,
    required this.type,
    required this.title,
    this.message,
    this.extraData,
    this.referenceId,
    this.referenceType,
    this.imageUrl,
    this.actionUrl,
    required this.isRead,
    this.readAt,
    required this.createdAt,
    this.actor,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      actorId: json['actor_id'] ?? 0,
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'],
      extraData: json['extra_data'],
      referenceId: json['reference_id'],
      referenceType: json['reference_type'],
      imageUrl: json['image_url'],
      actionUrl: json['action_url'],
      isRead: json['is_read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      actor: json['actor'] != null 
          ? NotificationActor.fromJson(json['actor']) 
          : null,
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class NotificationActor {
  final int id;
  final String? fullName;
  final String? username;
  final String? profilePic;

  NotificationActor({
    required this.id,
    this.fullName,
    this.username,
    this.profilePic,
  });

  factory NotificationActor.fromJson(Map<String, dynamic> json) {
    return NotificationActor(
      id: json['id'] ?? 0,
      fullName: json['full_name'],
      username: json['username'],
      profilePic: json['profile_pic'],
    );
  }
}
