import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'package:http_parser/http_parser.dart';

class CommunityService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> createCommunityPost({
    required String content,
    File? audioFile,
    int? audioDuration,
    List<File>? images,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/community-posts');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['content'] = content;

      if (audioFile != null && audioDuration != null) {
        if (audioDuration > 60) {
          throw Exception('Audio duration must not exceed 60 seconds');
        }
        
        final audioStream = http.ByteStream(audioFile.openRead());
        final audioLength = await audioFile.length();
        
        final multipartFile = http.MultipartFile(
          'audio',
          audioStream,
          audioLength,
          filename: audioFile.path.split('/').last,
          contentType: MediaType('audio', _getAudioType(audioFile.path)),
        );
        
        request.files.add(multipartFile);
        request.fields['duration'] = audioDuration.toString();
      }

      if (images != null && images.isNotEmpty) {
        if (images.length > 5) {
          throw Exception('Maximum 5 images allowed');
        }

        for (var image in images) {
          final imageStream = http.ByteStream(image.openRead());
          final imageLength = await image.length();
          
          final multipartFile = http.MultipartFile(
            'images',
            imageStream,
            imageLength,
            filename: image.path.split('/').last,
            contentType: MediaType('image', _getImageType(image.path)),
          );
          
          request.files.add(multipartFile);
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        print('Error creating post: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error creating community post: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCommunityPosts({
    int page = 1,
    int limit = 20,
    int? userId,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      String url = '${ApiConfig.baseUrl}/api/v1/community-posts?page=$page&limit=$limit';
      if (userId != null) {
        url += '&user_id=$userId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching community posts: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCommunityPostById(int postId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-posts/$postId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching post: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserCommunityPosts(
    int userId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/v1/users/$userId/community-posts?page=$page&limit=$limit',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching user posts: $e');
      return null;
    }
  }

Future<Map<String, dynamic>?> updateCommunityPost(
  int postId,
  String content, {
  List<int>? imagesToDelete,
  List<File>? newImages,
  bool removeAudio = false,
  File? newAudioFile,
  int? newAudioDuration,
}) async {
  try {
    final token = await _storage.read(key: 'jwt_token');

    final request = http.MultipartRequest(
      'PUT',
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/community-posts/$postId',
      ),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'multipart/form-data',
    });

    request.fields['content'] = content;

    if (removeAudio) {
      request.fields['remove_audio'] = 'true';
    }

    if (imagesToDelete != null && imagesToDelete.isNotEmpty) {
      request.fields['delete_image_indices'] =
          imagesToDelete.join(',');
    }

    if (newImages != null && newImages.isNotEmpty) {
      for (final image in newImages) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'new_images',
            image.path,
          ),
        );
      }
    }

    if (newAudioFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'new_audio',
          newAudioFile.path,
        ),
      );

      if (newAudioDuration != null) {
        request.fields['audio_duration'] =
            newAudioDuration.toString();
      }
    }

    final streamedResponse = await request.send();
    final responseBody =
        await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode == 200) {
      return json.decode(responseBody)
          as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update post: ${streamedResponse.statusCode} - $responseBody',
      );
    }
  } catch (e) {
    print('Error updating community post: $e');
    return null;
  }
}

  Future<Map<String, dynamic>?> deleteCommunityPost(int postId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-posts/$postId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error deleting post: $e');
      return null;
    }
  }
 
  Future<Map<String, dynamic>?> togglePostLike(int postId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-posts/$postId/like'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
      print('Toggle like response: $data'); 
      return data;
      }
      return null;
    } catch (e) {
      print('Error toggling like: $e');
      return null;
    }
  }

  Future<bool> checkPostLikeStatus(int postId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-posts/$postId/like-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['liked'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error checking like status: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> createComment(
    int postId,
    String content, {
    int? parentId,
    int? replyToUserId,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final body = {
        'content': content,
        if (parentId != null) 'parent_id': parentId,
        if (replyToUserId != null) 'reply_to_user_id': replyToUserId,
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-posts/$postId/comments'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error creating comment: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPostComments(
    int postId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/v1/community-posts/$postId/comments?page=$page&limit=$limit',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching comments: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCommentReplies(
    int commentId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/v1/community-comments/$commentId/replies?page=$page&limit=$limit',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching replies: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> deleteComment(int commentId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-comments/$commentId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error deleting comment: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> toggleCommentLike(int commentId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-comments/$commentId/like'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      print('Error toggling comment like: $e');
      return null;
    }
  }

  Future<bool> checkCommentLikeStatus(int commentId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return false;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/community-comments/$commentId/like-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['liked'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error checking comment like status: $e');
      return false;
    }
  }

  String _getAudioType(String path) {
    if (path.endsWith('.mp3')) return 'mpeg';
    if (path.endsWith('.wav')) return 'wav';
    if (path.endsWith('.m4a')) return 'm4a';
    return 'mpeg';
  }

  String _getImageType(String path) {
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'jpeg';
    if (path.endsWith('.gif')) return 'gif';
    return 'jpeg';
  }
}