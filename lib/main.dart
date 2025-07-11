import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'pages/login_page.dart';
import 'pages/main_navigation.dart';
import 'pages/chat_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/notification_service.dart';
import 'services/unified_socket_service.dart';
import 'services/memory_manager.dart';
import 'services/socket_service.dart';
import 'services/noti_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'services/fcm_service.dart';
import 'services/firebase_test.dart';

class CustomDebugBanner extends StatelessWidget {
  const CustomDebugBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Banner(
      message: 'UAT-TEST',
      location: BannerLocation.topStart,
      color: Colors.red,
      child: Container(),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Test Firebase initialization first
  bool firebaseInitialized = await FirebaseTest.testFirebaseInitialization();
  
  if (firebaseInitialized) {
    try {
      // เริ่มต้น FCM Service
      await FCMService.initialize();
      print('FCM Service initialized successfully');
    } catch (e) {
      print('Error initializing FCM: $e');
      // Continue without FCM if it fails
    }
  } else {
    print('Firebase initialization failed, skipping FCM setup');
  }
  
  // Load .env file
  await dotenv.load(fileName: ".env");
  
  // เริ่มต้นการแจ้งเตือน
  final notificationService = NotificationService();
  await notificationService.init();
  
  // เริ่มต้น UnifiedSocketService
  final unifiedSocketService = UnifiedSocketService();
  await unifiedSocketService.initialize();
  
  // เริ่มต้น MemoryManager
  final memoryManager = MemoryManager();
  
  final prefs = await SharedPreferences.getInstance();
  final userData = prefs.getString('user');

  runApp(AppLifecycleManager(
    child: MyApp(initialRoute: userData != null ? '/main' : '/login'),
  ));
}

// สร้าง notification channel
Future<void> _createNotificationChannel() async {
  if (Platform.isAndroid) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'socket_service_channel',
          '12Chat Notifications',
          description: 'Used for app notifications.',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
          showBadge: true,
        ),
      );
      print('Notification channel created');
    }
  }
}



// Background notification tap handler
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  print('Notification tapped in background: ${notificationResponse.payload}');
}

class AppLifecycleManager extends StatefulWidget {
  final Widget child;
  
  const AppLifecycleManager({super.key, required this.child});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed');
        break;
      case AppLifecycleState.inactive:
        print('App inactive');
        break;
      case AppLifecycleState.paused:
        print('App paused');
        break;
      case AppLifecycleState.detached:
        print('App detached');
        break;
      case AppLifecycleState.hidden:
        print('App hidden');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '12Chat',
      debugShowCheckedModeBanner: false,
      home: _buildInitialWidget(),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00569D)),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }

  Widget _buildInitialWidget() {
    switch (initialRoute) {
      case '/login':
        return const LoginPage();
      case '/main':
        return const MainNavigation();
      default:
        return const LoginPage();
    }
  }
}