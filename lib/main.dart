import 'dart:io' show Platform; // Import để kiểm tra nền tảng
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Import các màn hình
import 'screens/login_screen.dart'; // Màn hình đăng nhập cho mobile
import 'screens/nurse_chatbot_screen.dart'; // Màn hình mới cho y tá trên Windows

void main() {
  runApp(const HealthApp());
}

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});

  // Hàm helper để quyết định màn hình chính
  Widget _getHomeScreen() {
    // Nếu không phải web VÀ đang chạy trên Windows
    if (!kIsWeb && Platform.isWindows) {
      // Chạy ứng dụng của y tá
      return const NurseChatbotScreen();
    }
    // Ngược lại, chạy ứng dụng của gia đình
    else {
      return LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Healthcare App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Gọi hàm để xác định màn hình chính
      home: _getHomeScreen(),
    );
  }
}
