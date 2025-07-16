import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'services/desktop_notification_service.dart';
import 'services/api_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'services/fcm_service.dart';
import 'services/firebase_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyRootApp());
}

class MyRootApp extends StatefulWidget {
  const MyRootApp({Key? key}) : super(key: key);

  @override
  State<MyRootApp> createState() => _MyRootAppState();
}

class _MyRootAppState extends State<MyRootApp> {
  bool _isLoading = true;
  bool _forceUpdate = false;
  String? _updateUrl;
  String? _initialRoute;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. เช็คเวอร์ชัน
    if (Platform.isAndroid) {
      final versionOk = await _checkAppVersion();
      if (!versionOk) {
        setState(() {
          _forceUpdate = true;
          _isLoading = false;
        });
        return;
      }
    }
    // 2. Init Firebase เฉพาะมือถือ
    if (Platform.isAndroid || Platform.isIOS) {
      await Firebase.initializeApp();
    }
    // 3. Init notification, memory, socket, etc.
    final notificationService = NotificationService();
    await notificationService.init();
    final unifiedSocketService = UnifiedSocketService();
    await unifiedSocketService.initialize();
    final memoryManager = MemoryManager();
    if (Platform.isAndroid || Platform.isIOS) {
      bool firebaseInitialized =
          await FirebaseTest.testFirebaseInitialization();
      if (firebaseInitialized) {
        try {
          await FCMService.initialize();
        } catch (e) {
          print('Error initializing FCM: $e');
        }
      }
    } else {
      final desktopNotificationService = DesktopNotificationService();
      await desktopNotificationService.initialize();
    }
    // 4. ตรวจสอบ user login
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user');
    setState(() {
      _initialRoute = userData != null ? '/main' : '/login';
      _isLoading = false;
    });
  }

  Future<bool> _checkAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final versionInfo = await ApiService.fetchAppVersionInfo();
      if (versionInfo != null) {
        final minVersion = versionInfo['min_version'];
        final updateUrl = versionInfo['update_url'];
        if (_compareVersion(currentVersion, minVersion) < 0) {
          _updateUrl = updateUrl;
          return false;
        }
      }
      return true;
    } catch (e) {
      print('Version check error: $e');
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (_forceUpdate) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00569D)),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFF6F8FB),
          body: Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00569D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.system_update_alt,
                      size: 40,
                      color: Color(0xFF00569D),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'กรุณาอัปเดตแอป',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00569D),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Description
                  const Text(
                    'แอปเวอร์ชันนี้ไม่รองรับ กรุณาอัปเดตเป็นเวอร์ชันล่าสุดเพื่อใช้งานได้อย่างสมบูรณ์',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Update Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_updateUrl != null &&
                            await canLaunch(_updateUrl!)) {
                          await launch(_updateUrl!);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00569D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'อัปเดตแอป',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // App Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00569D).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/logo-onetwo.png',
                          height: 20,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '12Chat',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF00569D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return MaterialApp(
      title: '12Chat',
      debugShowCheckedModeBanner: false,
      home:
          _initialRoute == '/main' ? const MainNavigation() : const LoginPage(),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00569D)),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }
}

int _compareVersion(String v1, String v2) {
  final v1Parts = v1.split('.').map(int.parse).toList();
  final v2Parts = v2.split('.').map(int.parse).toList();
  for (int i = 0; i < v1Parts.length; i++) {
    if (v1Parts[i] < v2Parts[i]) return -1;
    if (v1Parts[i] > v2Parts[i]) return 1;
  }
  return 0;
}

// สร้าง notification channel
Future<void> _createNotificationChannel() async {
  if (Platform.isAndroid) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    final androidPlugin =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

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

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
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
