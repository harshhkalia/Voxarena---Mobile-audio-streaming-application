import 'dart:convert';
import 'package:app/services/audio_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '432533816770-hohojkm5m2v66f5vkr88eih3grqdp4r7.apps.googleusercontent.com',
  );

  String? _token;
  Map<String, dynamic>? _user;

  bool get isLoggedIn => _token != null;
  Map<String, dynamic>? get currentUser => _user;
  String? get token => _token;

  Future<void> init() async {
    _token = await _storage.read(key: 'jwt_token');
    if (_token != null) {
      final userJson = await _storage.read(key: 'user_data');
      if (userJson != null) {
        _user = json.decode(userJson);
      }
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign in cancelled');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      print('DEBUG: ID Token: ${googleAuth.idToken}');
      print('DEBUG: Google ID: ${googleUser.id}');
      print('DEBUG: Email: ${googleUser.email}');

      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      // final url = Uri.parse('http://$serverIP:$serverPort/api/v1/auth/google');

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/auth/google',
);

      final requestBody = {
        'id_token': googleAuth.idToken ?? '',
        'email': googleUser.email,
        'full_name': googleUser.displayName ?? '',
        'profile_pic': googleUser.photoUrl ?? '',
        'google_id': googleUser.id,
      };

      print('DEBUG: Sending request to: $url');
      print('DEBUG: Request body: ${json.encode(requestBody)}');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _user = data['user'];

        await _storage.write(key: 'jwt_token', value: _token);
        await _storage.write(key: 'user_data', value: json.encode(_user));

        return {'success': true, 'user': _user};
      } else {
        throw Exception('Backend authentication failed: ${response.body}');
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Google sign out error: $e');
    }

    final audio = GlobalAudioService();
    await audio.player.stop();
    audio.isPlaying = false;
    audio.position = Duration.zero;
    audio.currentUrl = null;
    audio.currentRoom = null;
    audio.currentTitle = null;
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'user_data');
    _token = null;
    _user = null;
  }

  Future<void> clearAllAuthData() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Error during sign out: $e');
    }
    await _storage.deleteAll();
    _token = null;
    _user = null;
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (_token == null) return null;

    try {
      // final serverIP = dotenv.get('SERVER_IP');
      // final serverPort = dotenv.get('SERVER_PORT');
      // final url = Uri.parse('http://$serverIP:$serverPort/api/v1/me');

      final url = Uri.parse(
  '${ApiConfig.baseUrl}/api/v1/me',
);

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
      );

      if (response.statusCode == 200) {
        _user = json.decode(response.body);
        await _storage.write(key: 'user_data', value: json.encode(_user));
        return _user;
      }
    } catch (e) {
      print('Error fetching user: $e');
    }
    return null;
  }

  Future<void> reloadCurrentUser() async {
    try {
      final userData = await _storage.read(key: 'user_data');
      if (userData != null) {
        _user = json.decode(userData);
      }
    } catch (e) {
      print('Error reloading user data: $e');
    }
  }

  Future<void> updateStoredUser(Map<String, dynamic> updatedUser) async {
    try {
      _user = updatedUser;
      await _storage.write(key: 'user_data', value: json.encode(updatedUser));
    } catch (e) {
      print('Error updating stored user: $e');
    }
  }
}
