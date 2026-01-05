import 'package:flutter/material.dart';
import '../models/room.dart';

class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: room.isLive ? _buildLiveCard() : _buildRecordedCard(),
        ),
      ),
    );
  }

  Widget _buildLiveCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildHostAvatar(size: 48),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.hostName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    room.topic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Text(
          room.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            const Icon(Icons.people, size: 18, color: Colors.grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _formatListenerCount(room.listenerCount, suffix: 'listening'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.headset, size: 18),
              label: const Text('Join'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordedCard() {
    final thumbUrl = room.thumbnail;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 120,
            height: 90,
            color: Colors.grey[850],
            child: Stack(
              children: [
                if (thumbUrl != null && thumbUrl.isNotEmpty)
                  Positioned.fill(
                    child: Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _thumbFallback(),
                    ),
                  )
                else
                  _thumbFallback(),

                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      room.formattedDuration,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              Row(
                children: [
                  _buildHostAvatar(size: 24),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      room.hostName,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Row(
                children: [
                  Flexible(
                    child: Text(
                      _formatListenerCount(
                        room.totalListens ?? 0,
                        suffix: 'play',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const Text(' • ', style: TextStyle(color: Colors.grey)),
                  Flexible(
                    child: Text(
                      _formatTimeAgo(room.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbFallback() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Icon(Icons.audiotrack, size: 40, color: Colors.grey[600]),
    );
  }

  Widget _buildHostAvatar({double size = 40}) {
    final avatarUrl = room.hostAvatar;

    if (avatarUrl.isNotEmpty && avatarUrl.startsWith('http')) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: const Color(0xFF2A2A3E),
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    final initial = room.hostName.isNotEmpty
        ? room.hostName[0].toUpperCase()
        : '?';

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF7C3AED),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size / 2,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatListenerCount(int count, {String suffix = 'play'}) {
    final isPluralForm = suffix.endsWith('s') && suffix.length > 1;
    final singularForm = isPluralForm
        ? suffix.substring(0, suffix.length - 1)
        : suffix;
    final pluralForm = isPluralForm ? suffix : '${suffix}s';

    final full = count == 1 ? singularForm : pluralForm;

    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M $full';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K $full';
    }

    return '$count $full';
  }

  String _pluralize(int value, String unit) {
    return value == 1 ? '$value $unit ago' : '$value ${unit}s ago';
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);

    if (diff.inDays >= 365) {
      final years = (diff.inDays / 365).floor();
      return _pluralize(years, 'year');
    }

    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return _pluralize(months, 'month');
    }

    if (diff.inDays > 0) {
      return _pluralize(diff.inDays, 'day');
    }

    if (diff.inHours > 0) {
      return _pluralize(diff.inHours, 'hour');
    }

    if (diff.inMinutes > 0) {
      return _pluralize(diff.inMinutes, 'minute');
    }

    return 'Just now';
  }
}
