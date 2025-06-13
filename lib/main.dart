import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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
  
  // Load .env file
  await dotenv.load(fileName: ".env");
  
  // เริ่มต้นการแจ้งเตือนก่อน (สำคัญ!)
  if (Platform.isAndroid || Platform.isIOS) {
    final notificationService = NotificationService();
    await notificationService.init();
    
    // สร้าง notification channel สำหรับ background service
    await _createServiceNotificationChannel();
    
    // เริ่มต้น Background Service หลังจากสร้าง channel แล้ว (เฉพาะ Android และ iOS)
    await initializeService();
    
    // ตรวจสอบและเริ่มต้น background service ถ้าจำเป็น
    await _ensureBackgroundServiceRunning();
    
    // เพิ่ม listener สำหรับ notification จาก background service
    _setupBackgroundServiceListener();
  } else {
    print('=== Platform not supported for background service: ${Platform.operatingSystem} ===');
    // สำหรับ Windows และ platform อื่นๆ ให้เริ่มต้น notification service แบบปกติ
    final notificationService = NotificationService();
    await notificationService.init();
  }
  
  // เริ่มต้น UnifiedSocketService
  final unifiedSocketService = UnifiedSocketService();
  await unifiedSocketService.initialize();
  
  // เริ่มต้น MemoryManager
  final memoryManager = MemoryManager();
  
  final prefs = await SharedPreferences.getInstance();
  final userData = prefs.getString('user');

  runApp(MyApp(initialRoute: userData != null ? '/main' : '/login'));
}

// เพิ่มฟังก์ชัน Background Service (แบบไม่ใช้ foreground)
Future<void> initializeService() async {
  // ตรวจสอบ platform ก่อน
  if (!Platform.isAndroid && !Platform.isIOS) {
    print('=== Background service not supported on ${Platform.operatingSystem} ===');
    return;
  }
  
  final service = FlutterBackgroundService();
  
  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true, // เปลี่ยนเป็น true เพื่อให้ service ทำงานต่อเนื่อง
      notificationChannelId: 'socket_service_channel',
      initialNotificationTitle: '12Chat Background Service',
      initialNotificationContent: 'กำลังทำงานในเบื้องหลัง',
      foregroundServiceNotificationId: 888,
    ),
  );
}

// สร้าง notification channel สำหรับ background service
Future<void> _createServiceNotificationChannel() async {
  if (Platform.isAndroid) {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'socket_service_channel',
          '12Chat Background Service',
          description: 'ช่องทางการแจ้งเตือนสำหรับ Background Service',
          importance: Importance.low, // ใช้ low สำหรับ background service
          enableVibration: false,
          playSound: false,
          showBadge: false,
        ),
      );
      print('Background service notification channel created');
    }
  }
}

// Background Service สำหรับ Android
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  print('=== Background Service Started ===');
  print('=== Background Service: Service Instance ID: ${service.hashCode} ===');
  print('=== Background Service: Platform: ${Platform.operatingSystem} ===');
  
  try {
    // Load .env file for background service
    await dotenv.load(fileName: ".env");
    print('=== Background Service: .env loaded ===');
    
    // เริ่มต้น SocketService ใน background
    final socketService = SocketService();
    print('=== Background Service: SocketService created ===');
    
    // รอให้ SocketService เตรียมพร้อม
    await Future.delayed(const Duration(seconds: 3));
    
    print('=== Background Service: Socket Service Ready ===');
    print('Socket connected: ${socketService.isConnected}');
    print('Socket ID: ${socketService.socketId}');
    
    // Subscribe to announcements for background notifications
    socketService.subscribeToAnnouncements();
    print('=== Background Service: Subscribed to announcements ===');
    
    // Subscribe to all notifications for background
    socketService.subscribeToAllNotifications();
    print('=== Background Service: Subscribed to all notifications ===');
    
    // ตั้งค่า announcement listener สำหรับ background
    socketService.onNewAnnouncement(
      (data) {
        print('=== Background Service: Announcement Received ===');
        print('Data: $data');
        
        // SocketService จะจัดการการแจ้งเตือนเอง
        // ไม่ต้องเรียก _showBackgroundNotification อีก
      },
      isInAnnouncementsPage: () => false, // Always false in background
      isAppInForeground: () => false,     // Always false in background
    );
    print('=== Background Service: Announcement listener set up ===');
    
    // Keep the service running
    service.on('stopService').listen((event) {
      print('=== Background Service: Stop Requested ===');
      // ไม่ต้อง dispose socket เพราะจะทำให้ไม่สามารถรับข้อมูลได้
      // socketService.dispose();
      service.stopSelf();
    });
    
    // รับคำสั่งทดสอบจากแอปหลัก
    service.on('test').listen((event) {
      print('=== Background Service: Test Command Received ===');
      print('Event: $event');
    });
    
    // รับคำสั่งแสดง notification จากแอปหลัก
    service.on('showNotification').listen((event) {
      print('=== Background Service: Show Notification Command ===');
      print('Event: $event');
      
      if (event != null && event is Map) {
        final title = event['title']?.toString() ?? 'ประกาศใหม่';
        final body = event['body']?.toString() ?? 'คุณมีประกาศใหม่';
        
        // ใช้ NotiService แทน BackgroundNotificationService
        try {
          final notiService = NotiService();
          notiService.showNotificationWithoutInit(
            title: title,
            body: body,
            payload: jsonEncode({
              'title': title,
              'content': body,
              'timestamp': event['timestamp'],
            }),
          );
          print('=== Background Service: Test notification shown successfully ===');
        } catch (e) {
          print('=== Background Service: Error showing test notification ===');
          print('Error: $e');
        }
      }
    });
    
    // รับคำสั่งทดสอบ socket จากแอปหลัก
    service.on('testSocket').listen((event) {
      print('=== Background Service: Test Socket Command ===');
      print('Event: $event');
      print('Socket connected: ${socketService.isConnected}');
      print('Socket ID: ${socketService.socketId}');
    });
    
    // รับคำสั่งส่งสถานะกลับไปยังแอปหลัก
    service.on('getStatus').listen((event) {
      print('=== Background Service: Get Status Command ===');
      
      service.invoke('status', {
        'socketConnected': socketService.isConnected,
        'socketId': socketService.socketId,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    
    // รับคำสั่งแสดง notification สำหรับแชทกลุ่ม
    service.on('showGroupChatNotification').listen((event) {
      print('=== Background Service: Show Group Chat Notification Command ===');
      print('Event: $event');
      
      if (event != null && event is Map) {
        final roomName = event['roomName']?.toString() ?? 'กลุ่ม';
        final senderName = event['senderName']?.toString() ?? 'ผู้ใช้';
        final message = event['message']?.toString() ?? 'ข้อความใหม่';
        final unreadCount = event['unreadCount'] ?? 1;
        
        final title = 'ข้อความใหม่ในกลุ่ม $roomName';
        final body = '$senderName: $message';
        
        try {
          final notiService = NotiService();
          notiService.showNotificationWithoutInit(
            title: title,
            body: body,
            payload: jsonEncode({
              'type': 'group_chat',
              'roomId': event['roomId'],
              'roomName': roomName,
              'senderName': senderName,
              'message': message,
              'unreadCount': unreadCount,
              'timestamp': event['timestamp'] ?? DateTime.now().toIso8601String(),
            }),
          );
          print('=== Background Service: Group chat notification shown successfully ===');
        } catch (e) {
          print('=== Background Service: Error showing group chat notification ===');
          print('Error: $e');
        }
      }
    });

    // รับคำสั่งแสดง notification สำหรับ direct message
    service.on('showDirectMessageNotification').listen((event) {
      print('=== Background Service: Show Direct Message Notification Command ===');
      print('Event: $event');
      
      if (event != null && event is Map) {
        final senderName = event['senderName']?.toString() ?? 'ผู้ใช้';
        final message = event['message']?.toString() ?? 'ข้อความใหม่';
        final unreadCount = event['unreadCount'] ?? 1;
        
        final title = 'ข้อความใหม่จาก $senderName';
        final body = message.length > 50 ? '${message.substring(0, 50)}...' : message;
        
        try {
          final notiService = NotiService();
          notiService.showNotificationWithoutInit(
            title: title,
            body: body,
            payload: jsonEncode({
              'type': 'direct_message',
              'senderId': event['senderId'],
              'senderName': senderName,
              'message': message,
              'unreadCount': unreadCount,
              'timestamp': event['timestamp'] ?? DateTime.now().toIso8601String(),
            }),
          );
          print('=== Background Service: Direct message notification shown successfully ===');
        } catch (e) {
          print('=== Background Service: Error showing direct message notification ===');
          print('Error: $e');
        }
      }
    });

    // รับคำสั่งแสดง notification สำหรับการแจ้งเตือนทั่วไป
    service.on('showGeneralNotification').listen((event) {
      print('=== Background Service: Show General Notification Command ===');
      print('Event: $event');
      
      if (event != null && event is Map) {
        final title = event['title']?.toString() ?? 'การแจ้งเตือน';
        final body = event['body']?.toString() ?? 'คุณมีการแจ้งเตือนใหม่';
        final notificationType = event['notificationType']?.toString() ?? 'general';
        
        try {
          final notiService = NotiService();
          notiService.showNotificationWithoutInit(
            title: title,
            body: body,
            payload: jsonEncode({
              'type': notificationType,
              'title': title,
              'content': body,
              'timestamp': event['timestamp'] ?? DateTime.now().toIso8601String(),
              'data': event['data'],
            }),
          );
          print('=== Background Service: General notification shown successfully ===');
        } catch (e) {
          print('=== Background Service: Error showing general notification ===');
          print('Error: $e');
        }
      }
    });
    
    // Keep service alive with periodic check
    Timer.periodic(const Duration(minutes: 1), (timer) {
      try {
        print('=== Background Service: Periodic Check ===');
        print('Socket connected: ${socketService.isConnected}');
        print('Socket ID: ${socketService.socketId}');
        
        // เช็คการเชื่อมต่อ ถ้าหลุดให้ reconnect
        if (!socketService.isConnected) {
          print('Socket disconnected, attempting to reconnect...');
          // พยายามเชื่อมต่อใหม่
          socketService.connect();
        }
        
        // ส่ง heartbeat เพื่อให้ service ทำงานต่อ
        service.invoke('heartbeat', {
          'timestamp': DateTime.now().toIso8601String(),
          'socketConnected': socketService.isConnected,
        });
        
      } catch (e) {
        print('Error in periodic check: $e');
      }
    });
    
    print('=== Background Service: Initialization completed successfully ===');
    
  } catch (e) {
    print('=== Background Service Error ===');
    print('Error: $e');
    print('Stack trace: ${StackTrace.current}');
    // ไม่ต้อง stop service ทันที ให้ลองทำงานต่อ
    // service.stopSelf();
  }
}

// ฟังก์ชันแสดง notification ใน background
@pragma('vm:entry-point')
void _showBackgroundNotification(dynamic data) async {
  // This function is no longer needed as notifications are handled in SocketService
  print('=== Background Service: Notification handling moved to SocketService ===');
}

// ฟังก์ชันทำความสะอาดข้อมูลสำหรับ JSON encoding
@pragma('vm:entry-point')
Map<String, dynamic> _cleanDataForJson(Map<String, dynamic> data) {
  // This function is no longer needed as data cleaning is handled in SocketService
  return data;
}

// ตั้งค่า listener สำหรับ background service
void _setupBackgroundServiceListener() {
  // ตรวจสอบ platform ก่อน
  if (!Platform.isAndroid && !Platform.isIOS) {
    print('=== Background service listeners not supported on ${Platform.operatingSystem} ===');
    return;
  }
  
  final service = FlutterBackgroundService();
  
  // Listener สำหรับ status จาก background service
  service.on('status').listen((event) async {
    print('=== Main App: Received status from background service ===');
    print('Event: $event');
  });
  
  // Listener สำหรับ heartbeat จาก background service
  service.on('heartbeat').listen((event) async {
    print('=== Main App: Received heartbeat from background service ===');
    print('Event: $event');
  });
  
  // Listener สำหรับ notification ปกติ
  service.on('showNotificationFromService').listen((event) async {
    print('=== Main App: Received notification request from background service ===');
    print('Event: $event');
    
    try {
      if (event != null && event is Map) {
        final title = event['title']?.toString() ?? 'ประกาศใหม่';
        final body = event['body']?.toString() ?? 'คุณมีประกาศใหม่';
        final payload = event['payload']?.toString();
        
        // ใช้ NotificationService ที่ initialize แล้วในแอปหลัก
        final notificationService = NotificationService();
        
        if (notificationService.isInitialized) {
          await notificationService.showNotification(
            title: title,
            body: body,
            payload: payload,
          );
          print('=== Main App: Notification shown successfully ===');
        } else {
          print('=== Main App: NotificationService not initialized ===');
        }
      }
    } catch (e) {
      print('=== Main App: Error showing notification from service ===');
      print('Error: $e');
    }
  });
  
  // Listener สำหรับ simple notification
  service.on('simpleNotification').listen((event) async {
    print('=== Main App: Received simple notification request ===');
    print('Event: $event');
    
    try {
      if (event != null && event is Map) {
        final title = event['title']?.toString() ?? 'ประกาศใหม่';
        final body = event['body']?.toString() ?? 'คุณมีประกาศใหม่';
        final payload = event['payload']?.toString();
        
        // ใช้ NotiService สำหรับ simple notification
        final notiService = NotiService();
        
        try {
          // ลองใช้ method ที่ไม่ต้อง initialize ใหม่
          await notiService.showNotificationWithoutInit(
            title: title,
            body: body,
            payload: payload,
          );
          print('=== Main App: Simple notification shown successfully ===');
        } catch (e) {
          print('=== Main App: Simple notification without init failed, trying normal ===');
          // ถ้าไม่สำเร็จ ให้ลองใช้ method ปกติ
          if (notiService.isInitialized) {
            await notiService.showNotification(
              title: title,
              body: body,
              payload: payload,
            );
            print('=== Main App: Simple notification shown with normal method ===');
          } else {
            print('=== Main App: NotiService not initialized for simple notification ===');
          }
        }
      }
    } catch (e) {
      print('=== Main App: Error showing simple notification ===');
      print('Error: $e');
    }
  });
  
  // Listener สำหรับ emergency notification
  service.on('emergencyNotification').listen((event) async {
    print('=== Main App: Received emergency notification request ===');
    print('Event: $event');
    
    try {
      if (event != null && event is Map) {
        final title = event['title']?.toString() ?? 'ประกาศใหม่';
        final body = event['body']?.toString() ?? 'คุณมีประกาศใหม่';
        final payload = event['payload']?.toString();
        final priority = event['priority']?.toString() ?? 'normal';
        
        // ใช้ NotificationService สำหรับ emergency notification
        final notificationService = NotificationService();
        
        if (notificationService.isInitialized) {
          await notificationService.showNotification(
            title: title,
            body: body,
            payload: payload,
          );
          print('=== Main App: Emergency notification shown successfully ===');
        } else {
          print('=== Main App: NotificationService not initialized for emergency notification ===');
        }
      }
    } catch (e) {
      print('=== Main App: Error showing emergency notification ===');
      print('Error: $e');
    }
  });
  
  print('=== Main App: Background service listeners setup completed ===');
}

// ตรวจสอบและเริ่มต้น background service
Future<void> _ensureBackgroundServiceRunning() async {
  // ตรวจสอบ platform ก่อน
  if (!Platform.isAndroid && !Platform.isIOS) {
    print('=== Background service not supported on ${Platform.operatingSystem} ===');
    return;
  }
  
  try {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    
    print('=== Main App: Background service status check ===');
    print('Background service is running: $isRunning');
    
    if (!isRunning) {
      print('=== Main App: Starting background service ===');
      await service.startService();
      
      // รอให้ service เริ่มต้น
      await Future.delayed(const Duration(seconds: 3));
      
      final isRunningAfter = await service.isRunning();
      print('=== Main App: Background service status after start ===');
      print('Background service is running: $isRunningAfter');
    }
  } catch (e) {
    print('=== Main App: Error ensuring background service running ===');
    print('Error: $e');
  }
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NotiOneTwo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF004B93)),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/main': (context) => const MainNavigation(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: Text(widget.title + ' 12Trading'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('user');
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Background Service สำหรับ iOS
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('=== iOS Background Service ===');
  return true;
}