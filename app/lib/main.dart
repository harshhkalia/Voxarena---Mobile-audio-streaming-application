import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/guest_home_screen.dart';
import 'services/auth_service.dart';
import 'services/audio_service.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await AuthService().init();
  GlobalAudioService().initListeners();

  await FlutterDownloader.initialize(debug: true, ignoreSsl: false);

  runApp(const VoxArenaApp());
}

class VoxArenaApp extends StatelessWidget {
  const VoxArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = GlobalAudioService();

    return AnimatedBuilder(
      animation: audio,
      builder: (context, _) {
        return MaterialApp(
          title: 'VoxArena',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF7C3AED),
            scaffoldBackgroundColor: const Color(0xFF0F0F1E),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1A1A2E),
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF1A1A2E),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF7C3AED)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF7C3AED),
                  width: 2,
                ),
              ),
              hintStyle: const TextStyle(color: Colors.grey),
            ),
          ),
          home: const GuestHomeScreen(),
        );
      },
    );
  }
}
