import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/api_service.dart';
import 'noti_service.dart';
import 'unified_socket_service.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  final NotiService _notiService = NotiService();
  final UnifiedSocketService _unifiedSocketService = UnifiedSocketService();
  bool _isAnnouncementSubscribed = false; // Track announcement subscription
  bool _isSocketSetup = false;

  factory SocketService() {
    return _instance;
  }

  SocketService._internal() {
    print('SocketService: Initializing with UnifiedSocketService');
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // เริ่มต้น UnifiedSocketService
      await _unifiedSocketService.initialize();
      
      // ตั้งค่า announcement listener
      _unifiedSocketService.onAnnouncement((data) {
        print('=== SocketService: New Announcement Received ===');
        print('Data: $data');
        
        // จัดการการแจ้งเตือนประกาศ
        _handleAnnouncementNotification(data);
      });
      
      print('SocketService: Initialization complete');
    } catch (e) {
      print('SocketService: Initialization error: $e');
      rethrow;
    }
  }

  /// ดึง Socket instance
  IO.Socket get socket => _unifiedSocketService.socket;

  /// ตรวจสอบสถานะการเชื่อมต่อ
  bool get isConnected => _unifiedSocketService.isConnected;

  /// ดึง Socket ID
  String? get socketId => _unifiedSocketService.socketId;

  /// จัดการการแจ้งเตือนประกาศ
  void _handleAnnouncementNotification(dynamic data) {
    try {
      dynamic announcementData;
      
      if (data is List && data.isNotEmpty) {
        // If data is a list, get the first item
        final firstItem = data[0];
        if (firstItem is Map<String, dynamic>) {
          if (firstItem['data'] != null) {
            // If data is nested under 'data' key
            announcementData = firstItem['data'];
          } else {
            // If data is directly available
            announcementData = firstItem;
          }
        } else {
          print('Invalid announcement data structure in list: ${data.runtimeType}');
          return;
        }
      } else if (data is Map<String, dynamic>) {
        if (data['data'] != null) {
          // If data is nested under 'data' key
          announcementData = data['data'];
        } else {
          // If data is directly available
          announcementData = data;
        }
      } else {
        print('Invalid announcement data format: ${data.runtimeType}');
        return;
      }
      
      // Handle different data structures
      Map<String, dynamic> formattedData;
      if (announcementData['createdByUser'] != null) {
        formattedData = {
          ...announcementData,
          'createdBy': {
            'fullNameThai': announcementData['createdByUser']['fullNameThai'] ?? 'Unknown',
            'department': announcementData['createdByUser']['department']?.toString(),
          }
        };
      } else {
        formattedData = {
          ...announcementData,
          'createdBy': {
            'fullNameThai': announcementData['createdBy']?.toString() ?? 'Unknown',
            'department': announcementData['department']?.toString(),
          }
        };
      }
      
      print('=== SocketService: Showing notification ===');
      print('Title: ${formattedData['title']}');
      print('Content: ${formattedData['content']}');
      
      // ตรวจสอบว่าเป็น background service หรือไม่
      bool isInBackgroundService = _isInBackgroundService();
      print('=== SocketService: Is in background service: $isInBackgroundService ===');
      
      if (isInBackgroundService) {
        // ถ้าเป็น background service ให้ใช้ background notification service
        print('=== SocketService: Using background notification service ===');
        _showBackgroundNotification(formattedData);
      } else {
        // ถ้าไม่ใช่ background service ให้ใช้ NotiService ปกติ
        print('=== SocketService: Using normal NotiService ===');
        _notiService.showNotification(
          title: 'ประกาศใหม่: ${formattedData['title']}',
          body: formattedData['content'],
          payload: json.encode(formattedData),
        );
      }
    } catch (e) {
      print('Error handling announcement notification: $e');
      print('Error details: ${e.toString()}');
    }
  }

  /// ตรวจสอบว่าเป็น background service หรือไม่
  bool _isInBackgroundService() {
    try {
      final stackTrace = StackTrace.current.toString();
      return stackTrace.contains('flutter_background_service') || 
             stackTrace.contains('BackgroundService') ||
             stackTrace.contains('onStart') ||
             stackTrace.contains('_showBackgroundNotification');
    } catch (e) {
      print('Error checking background service: $e');
      return false;
    }
  }

  /// แสดง notification ใน background service
  void _showBackgroundNotification(Map<String, dynamic> data) {
    try {
      print('=== SocketService: Showing background notification ===');
      
      // ใน background service เราไม่สามารถใช้ FlutterBackgroundService.invoke() ได้
      // ให้ใช้วิธีอื่นแทน เช่น การแสดง notification โดยตรงผ่าน NotiService
      // แต่ใช้ method ที่ไม่ต้อง initialize ใหม่
      
      try {
        // ลองใช้ showNotificationWithoutInit ก่อน
        _notiService.showNotificationWithoutInit(
          title: 'ประกาศใหม่: ${data['title']}',
          body: data['content'],
          payload: json.encode(data),
        );
        print('=== SocketService: Background notification shown with showNotificationWithoutInit ===');
      } catch (e) {
        print('=== SocketService: showNotificationWithoutInit failed, trying fallback ===');
        print('Error: $e');
        
        // ถ้าไม่สำเร็จ ให้ใช้วิธี fallback
        _showFallbackNotification(data);
      }
      
    } catch (e) {
      print('=== SocketService: Error showing background notification ===');
      print('Error: $e');
    }
  }

  /// Fallback notification method สำหรับ background service
  void _showFallbackNotification(Map<String, dynamic> data) {
    try {
      print('=== SocketService: Using fallback notification method ===');
      
      // ใช้ FlutterLocalNotificationsPlugin โดยตรง
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'socket_service_channel',
          '12Chat Background Service',
          channelDescription: 'ช่องทางการแจ้งเตือนสำหรับ Background Service',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
          playSound: true,
        ),
      );

      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      flutterLocalNotificationsPlugin.show(
        id,
        'ประกาศใหม่: ${data['title']}',
        data['content'],
        notificationDetails,
        payload: json.encode(data),
      );
      
      print('=== SocketService: Fallback notification shown successfully ===');
      
    } catch (e) {
      print('=== SocketService: Fallback notification failed ===');
      print('Error: $e');
    }
  }

  /// Subscribe ไปยังห้องแชท
  void subscribeToRoom(String roomId) {
    print('=== SocketService: Subscribing to Room ===');
    print('Room ID: $roomId');
    _unifiedSocketService.subscribeToRoom(roomId);
  }

  /// Unsubscribe จากห้องแชท
  void unsubscribeFromRoom(String roomId) {
    print('=== SocketService: Unsubscribing from Room ===');
    print('Room ID: $roomId');
    _unifiedSocketService.unsubscribeFromRoom(roomId);
  }

  /// Subscribe ไปยังแชทส่วนตัว
  void subscribeToDirectMessages(String senderId, String recipientId) {
    print('=== SocketService: Subscribing to Direct Messages ===');
    print('Sender ID: $senderId');
    print('Recipient ID: $recipientId');
    _unifiedSocketService.subscribeToDirectMessages(senderId, recipientId);
  }

  /// Unsubscribe จากแชทส่วนตัว
  void unsubscribeFromDirectMessages(String senderId, String recipientId) {
    print('=== SocketService: Unsubscribing from Direct Messages ===');
    print('Sender ID: $senderId');
    print('Recipient ID: $recipientId');
    _unifiedSocketService.unsubscribeFromDirectMessages(senderId, recipientId);
  }

  /// Subscribe ไปยังประกาศ
  void subscribeToAnnouncements() {
    print('=== SocketService: Subscribing to Announcements ===');
    _unifiedSocketService.subscribeToAnnouncements();
  }

  /// เพิ่ม listener สำหรับข้อความ
  void onMessage(String event, Function(dynamic) callback) {
    _unifiedSocketService.onMessage(event, callback);
  }

  /// เพิ่ม listener สำหรับการเชื่อมต่อ
  void onConnection(String event, Function(dynamic) callback) {
    _unifiedSocketService.onConnection(event, callback);
  }

  /// ลบ listener
  void offMessage(String event, Function(dynamic)? callback) {
    _unifiedSocketService.offMessage(event, callback);
  }

  void offConnection(String event, Function(dynamic)? callback) {
    _unifiedSocketService.offConnection(event, callback);
  }

  /// ส่งข้อความทดสอบ
  void sendTestMessage(String roomId, String message) {
    print('=== SocketService: Sending Test Message ===');
    print('Room ID: $roomId');
    print('Message: $message');
    
    if (_unifiedSocketService.isConnected) {
      _unifiedSocketService.sendMessage(
        roomId: roomId,
        message: message,
      );
      print('Test message sent');
    } else {
      print('Cannot send test message: Socket not connected');
    }
  }

  /// ส่งประกาศทดสอบ
  void sendTestAnnouncement(String title, String content) {
    print('=== SocketService: Sending Test Announcement ===');
    print('Title: $title');
    print('Content: $content');
    
    if (_unifiedSocketService.isConnected) {
      _unifiedSocketService.socket.emit('testAnnouncement', {
        'title': title,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('Test announcement sent');
    } else {
      print('Cannot send test announcement: Socket not connected');
    }
  }

  /// อัปเดต User ID
  void updateUserId(String? userId) {
    _unifiedSocketService.updateUserId(userId);
  }

  /// Cleanup resources
  void dispose() {
    print('=== SocketService: Disposing ===');
    
    // ตรวจสอบว่าเป็น background service หรือไม่
    // ถ้าเป็น background service ไม่ต้อง dispose socket
    try {
      // ตรวจสอบว่าเป็น background service โดยดูจาก stack trace
      final stackTrace = StackTrace.current.toString();
      if (stackTrace.contains('flutter_background_service') || 
          stackTrace.contains('BackgroundService')) {
        print('=== SocketService: Background service detected, skipping dispose ===');
        return;
      }
    } catch (e) {
      print('Error checking background service: $e');
    }
    
    // ถ้าไม่ใช่ background service ให้ dispose ปกติ
    _unifiedSocketService.dispose();
  }

  /// ตรวจสอบสถานะการ initialize
  bool get isInitialized => _unifiedSocketService.isInitialized;

  /// ดึงรายการห้องที่ subscribe อยู่
  Set<String> get subscribedRooms => _unifiedSocketService.subscribedRooms;

  /// ดึงรายการแชทส่วนตัวที่ subscribe อยู่
  Set<String> get subscribedDirectMessages => _unifiedSocketService.subscribedDirectMessages;

  /// Connect socket (for backward compatibility)
  Future<void> connect() async {
    if (!_unifiedSocketService.isInitialized) {
      await _unifiedSocketService.initialize();
    }
  }

  /// Disconnect socket (for backward compatibility)
  void disconnect() {
    print('=== SocketService: Disconnect called ===');
    // ไม่ต้องทำอะไร เพราะ UnifiedSocketService จัดการเอง
    print('SocketService: Disconnect completed');
  }

  /// onNewAnnouncement (for backward compatibility)
  void onNewAnnouncement(
    Function(dynamic) callback, {
    bool Function()? isInAnnouncementsPage,
    bool Function()? isAppInForeground,
  }) {
    print('=== SocketService: onNewAnnouncement called ===');
    
    // Check if already subscribed
    if (_isAnnouncementSubscribed) {
      print('=== SocketService: Already subscribed to announcements, skipping... ===');
      return;
    }
    
    // Subscribe to announcements
    _unifiedSocketService.subscribeToAnnouncements();
    _isAnnouncementSubscribed = true;
    
    // ตั้งค่า listener พร้อมเงื่อนไขการแจ้งเตือน
    _unifiedSocketService.onAnnouncement((data) {
      print('=== SocketService: Announcement received ===');
      print('Data: $data');
      
      // ตรวจสอบเงื่อนไขการแสดงการแจ้งเตือน
      final isInAnnouncements = isInAnnouncementsPage?.call() ?? false;
      final isInForeground = isAppInForeground?.call() ?? true;
      
      print('=== SocketService: Notification conditions ===');
      print('Is in announcements page: $isInAnnouncements');
      print('Is app in foreground: $isInForeground');
      
      // แสดงการแจ้งเตือนเสมอ ไม่ว่าจะอยู่หน้าไหนหรือแอปอยู่ในสถานะใด
      print('=== SocketService: Showing notification (ALWAYS) ===');
      _handleAnnouncementNotification(data);
      
      // เรียก callback เพื่ออัปเดต UI
      callback(data);
    });
  }

  /// offNewAnnouncement (for backward compatibility)
  void offNewAnnouncement() {
    print('=== SocketService: offNewAnnouncement called ===');
    _unifiedSocketService.offAnnouncement();
    _isAnnouncementSubscribed = false;
  }

  /// Test announcement notification (for debugging)
  Future<void> testAnnouncementNotification() async {
    print('=== SocketService: Testing announcement notification ===');
    
    final testData = {
      'id': 'test_${DateTime.now().millisecondsSinceEpoch}',
      'title': 'ประกาศทดสอบจาก SocketService',
      'content': 'นี่คือการทดสอบการแจ้งเตือนประกาศจาก SocketService',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': {
        'fullNameThai': 'ผู้ทดสอบระบบ',
        'department': 'IT',
      },
    };
    
    try {
      _handleAnnouncementNotification(testData);
      print('=== SocketService: Test announcement notification sent successfully ===');
    } catch (e) {
      print('=== SocketService: Error sending test announcement notification: $e ===');
    }
  }
} 