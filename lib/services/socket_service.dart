import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/api_service.dart';
import 'noti_service.dart';
import 'unified_socket_service.dart';
import 'desktop_notification_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  final NotiService _notiService = NotiService();
  final UnifiedSocketService _unifiedSocketService = UnifiedSocketService();
  bool _isAnnouncementSubscribed = false; // Track announcement subscription
  bool _isSocketSetup = false;
  
  // Add tracking for recent notifications to prevent duplicates
  final Map<String, DateTime> _recentNotifications = {};
  static const Duration _notificationCooldown = Duration(seconds: 3);

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
      
      // Create a unique key for this announcement to prevent duplicates
      final announcementId = formattedData['_id']?.toString() ?? 
                           formattedData['id']?.toString() ?? 
                           '${formattedData['title']}_${formattedData['createdAt']}';
      
      // Check if we've shown this notification recently
      final now = DateTime.now();
      if (_recentNotifications.containsKey(announcementId)) {
        final lastShown = _recentNotifications[announcementId]!;
        if (now.difference(lastShown) < _notificationCooldown) {
          print('=== SocketService: Skipping duplicate notification for announcement: $announcementId ===');
          return;
        }
      }
      
      print('=== SocketService: Processing announcement notification ===');
      print('Title: ${formattedData['title']}');
      print('Content: ${formattedData['content']}');
      print('Announcement ID: $announcementId');
      
      // ตรวจสอบว่าเป็น background service หรือไม่
      bool isInBackgroundService = _isInBackgroundService();
      print('=== SocketService: Is in background service: $isInBackgroundService ===');
      
      // Check if FCM is likely to handle this notification
      bool shouldSkipSocketNotification = _shouldSkipSocketNotification(formattedData);
      
      if (shouldSkipSocketNotification) {
        print('=== SocketService: Skipping socket notification (FCM will handle) ===');
        // Still track the notification to prevent duplicates
        _recentNotifications[announcementId] = now;
        return;
      }
      
      // ถ้าแอปอยู่ใน foreground และไม่ใช่ background service ให้ข้าม
      // เพราะ FCM จะจัดการแทน
      if (!isInBackgroundService) {
        print('=== SocketService: App in foreground, letting FCM handle ===');
        _recentNotifications[announcementId] = now;
        return;
      }
      
      // แสดงการแจ้งเตือนเฉพาะเมื่อเป็น background service
      print('=== SocketService: Showing background notification ===');
      _showBackgroundNotification(formattedData);
      
      // Track this notification
      _recentNotifications[announcementId] = now;
      
      // Clean up old entries (older than 1 minute)
      _recentNotifications.removeWhere((key, time) => 
        now.difference(time) > const Duration(minutes: 1));
      
    } catch (e) {
      print('Error handling announcement notification: $e');
      print('Error details: ${e.toString()}');
    }
  }

  /// ตรวจสอบว่าเป็น background service หรือไม่
  bool _isInBackgroundService() {
    try {
      final stackTrace = StackTrace.current.toString();
      
      // ตรวจสอบหลายเงื่อนไขเพื่อให้แน่ใจว่าเป็น background service
      final isBackground = stackTrace.contains('flutter_background_service') || 
             stackTrace.contains('BackgroundService') ||
             stackTrace.contains('onStart') ||
             stackTrace.contains('_showBackgroundNotification') ||
             stackTrace.contains('ServiceInstance') ||
             stackTrace.contains('background_service');
      
      print('=== SocketService: Background service check ===');
      print('Stack trace contains flutter_background_service: ${stackTrace.contains('flutter_background_service')}');
      print('Stack trace contains BackgroundService: ${stackTrace.contains('BackgroundService')}');
      print('Stack trace contains onStart: ${stackTrace.contains('onStart')}');
      print('Stack trace contains ServiceInstance: ${stackTrace.contains('ServiceInstance')}');
      print('Stack trace contains background_service: ${stackTrace.contains('background_service')}');
      print('Is background service: $isBackground');
      
      // For now, let's always show notifications from Socket service
      // since the background service detection is not working properly
      print('=== SocketService: Always showing notification (temporary fix) ===');
      return false; // Don't show notifications from Socket when app is in foreground
      
    } catch (e) {
      print('Error checking background service: $e');
      return false; // Default to not showing notification
    }
  }

  /// แสดง notification ใน background service
  void _showBackgroundNotification(Map<String, dynamic> data) {
    try {
      print('=== SocketService: Showing background notification ===');
      
      // ตรวจสอบ platform เพื่อใช้ service ที่เหมาะสม
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile platforms - ใช้ NotiService
        try {
          _notiService.showNotificationWithoutInit(
            title: 'ประกาศใหม่: ${data['title']}',
            body: data['content'],
            payload: json.encode(data),
          );
          print('=== SocketService: Mobile notification shown ===');
        } catch (e) {
          print('=== SocketService: Mobile notification failed, trying fallback ===');
          print('Error: $e');
          _showFallbackNotification(data);
        }
      } else {
        // Desktop platforms - ใช้ DesktopNotificationService
        try {
          final desktopNotificationService = DesktopNotificationService();
          desktopNotificationService.showAnnouncementNotification(
            title: data['title'] ?? 'ประกาศใหม่',
            content: data['content'] ?? 'มีประกาศใหม่',
            data: data,
          );
          print('=== SocketService: Desktop notification shown ===');
        } catch (e) {
          print('=== SocketService: Desktop notification failed, trying fallback ===');
          print('Error: $e');
          _showFallbackNotification(data);
        }
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
      
      // ใช้ channel เดียวกับ FCM service เพื่อให้มี icon เดียวกัน
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'fcm_foreground_channel',  // ใช้ channel เดียวกับ FCM
          'FCM Foreground Notifications',
          channelDescription: 'ช่องทางการแจ้งเตือน FCM สำหรับ Foreground',
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

  /// Subscribe ไปยังการแจ้งเตือนแชทกลุ่ม
  void subscribeToGroupChatNotifications() {
    print('=== SocketService: Subscribing to Group Chat Notifications ===');
    
    // ตั้งค่า listener สำหรับข้อความใหม่ในแชทกลุ่ม
    _unifiedSocketService.onMessage('newMessageNotification', (data) {
      print('=== SocketService: New Group Chat Message Received ===');
      print('Data: $data');
      
      // จัดการการแจ้งเตือนข้อความใหม่ในแชทกลุ่ม
      _handleGroupChatNotification(data);
    });
  }

  /// Subscribe ไปยังการแจ้งเตือน direct message
  void subscribeToDirectMessageNotifications() {
    print('=== SocketService: Subscribing to Direct Message Notifications ===');
    
    // ตั้งค่า listener สำหรับข้อความใหม่ใน direct message
    _unifiedSocketService.onMessage('newDirectMessageNotification', (data) {
      print('=== SocketService: New Direct Message Received ===');
      print('Data: $data');
      
      // จัดการการแจ้งเตือนข้อความใหม่ใน direct message
      _handleDirectMessageNotification(data);
    });
  }

  /// Subscribe ไปยังการแจ้งเตือนทั้งหมด
  void subscribeToAllNotifications() {
    print('=== SocketService: Subscribing to All Notifications ===');
    
    // Subscribe ไปยังประกาศ
    subscribeToAnnouncements();
    
    // Subscribe ไปยังการแจ้งเตือนแชทกลุ่ม
    subscribeToGroupChatNotifications();
    
    // Subscribe ไปยังการแจ้งเตือน direct message
    subscribeToDirectMessageNotifications();
    
    print('=== SocketService: All notifications subscribed ===');
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
      // Force show notification for testing
      print('=== SocketService: Force showing test notification ===');
      _showBackgroundNotification(testData);
      print('=== SocketService: Test announcement notification sent successfully ===');
    } catch (e) {
      print('=== SocketService: Error sending test announcement notification: $e ===');
    }
  }

  /// จัดการการแจ้งเตือนข้อความใหม่ในแชทกลุ่ม
  void _handleGroupChatNotification(dynamic data) async {
    try {
      print('=== SocketService: Handling Group Chat Notification ===');
      print('Data: $data');
      
      if (data is Map<String, dynamic>) {
        final roomId = data['roomId']?.toString();
        final roomName = data['roomName']?.toString() ?? 'กลุ่ม';
        final message = data['message']?.toString() ?? 'ข้อความใหม่';
        final sender = data['sender'];
        final senderId = sender?['employeeID']?.toString();
        final unreadCount = data['unreadCount'] ?? 1;
        
        // ตรวจสอบว่าเป็นข้อความสำหรับผู้ใช้ปัจจุบันหรือไม่
        final currentUserId = await _getCurrentUserId();
        if (currentUserId == null) {
          print('=== SocketService: Current user ID not found, skipping notification ===');
          return;
        }
        
        // ตรวจสอบว่าไม่ใช่ข้อความที่เราส่งเอง
        if (senderId == currentUserId) {
          print('=== SocketService: Message sent by current user, skipping notification ===');
          return;
        }
        
        String senderName = 'ผู้ใช้';
        if (sender is Map<String, dynamic>) {
          senderName = sender['fullNameThai']?.toString() ?? 
                      sender['fullName']?.toString() ?? 
                      'ผู้ใช้';
        }
        
        print('=== SocketService: Group Chat Notification Details ===');
        print('Room ID: $roomId');
        print('Room Name: $roomName');
        print('Current User ID: $currentUserId');
        print('Sender ID: $senderId');
        print('Sender: $senderName');
        print('Message: $message');
        print('Unread Count: $unreadCount');
        print('=== SocketService: Showing notification ===');
        
        // ตรวจสอบว่าเป็น background service หรือไม่
        bool isInBackgroundService = _isInBackgroundService();
        print('=== SocketService: Is in background service: $isInBackgroundService ===');
        
        if (isInBackgroundService) {
          // ส่งคำสั่งไปยัง background service
          _sendToBackgroundService('showGroupChatNotification', {
            'roomId': roomId,
            'roomName': roomName,
            'senderName': senderName,
            'message': message,
            'unreadCount': unreadCount,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } else {
          // ใช้ NotiService ปกติ
          final shortMessage = message.length > 50 ? message.substring(0, 50) + '...' : message;
          _notiService.showNotification(
            title: 'กลุ่ม: $roomName',
            body: 'ข้อความ: $shortMessage',
            payload: json.encode({
              'type': 'group_chat',
              'roomId': roomId,
              'roomName': roomName,
              'senderName': senderName,
              'message': message,
              'unreadCount': unreadCount,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          );
        }
      }
    } catch (e) {
      print('Error handling group chat notification: $e');
      print('Error details: ${e.toString()}');
    }
  }

  /// จัดการการแจ้งเตือนข้อความใหม่ใน direct message
  void _handleDirectMessageNotification(dynamic data) async {
    try {
      print('=== SocketService: Handling Direct Message Notification ===');
      print('Data: $data');
      
      if (data is Map<String, dynamic>) {
        final recipientId = data['recipientId']?.toString();
        final sender = data['sender'];
        final senderId = sender?['employeeID']?.toString();
        final message = data['message']?.toString() ?? 'ข้อความใหม่';
        final unreadCount = data['unreadCount'] ?? 1;
        
        // ตรวจสอบว่าเป็นข้อความสำหรับผู้ใช้ปัจจุบันหรือไม่
        final currentUserId = await _getCurrentUserId();
        if (currentUserId == null) {
          print('=== SocketService: Current user ID not found, skipping notification ===');
          return;
        }
        
        // ตรวจสอบว่า recipientId ตรงกับ currentUserId หรือไม่
        if (recipientId != currentUserId) {
          print('=== SocketService: Notification not for current user ===');
          print('Recipient ID: $recipientId');
          print('Current User ID: $currentUserId');
          print('=== SocketService: Skipping notification ===');
          return;
        }
        
        // ตรวจสอบว่าไม่ใช่ข้อความที่เราส่งเอง
        if (senderId == currentUserId) {
          print('=== SocketService: Message sent by current user, skipping notification ===');
          return;
        }
        
        String senderName = 'ผู้ใช้';
        if (sender is Map<String, dynamic>) {
          senderName = sender['fullNameThai']?.toString() ?? 
                      sender['fullName']?.toString() ?? 
                      'ผู้ใช้';
        }
        
        print('=== SocketService: Direct Message Notification Details ===');
        print('Recipient ID: $recipientId');
        print('Current User ID: $currentUserId');
        print('Sender ID: $senderId');
        print('Sender: $senderName');
        print('Message: $message');
        print('Unread Count: $unreadCount');
        print('=== SocketService: Showing notification ===');
        
        // ตรวจสอบว่าเป็น background service หรือไม่
        bool isInBackgroundService = _isInBackgroundService();
        print('=== SocketService: Is in background service: $isInBackgroundService ===');
        
        if (isInBackgroundService) {
          // ส่งคำสั่งไปยัง background service
          _sendToBackgroundService('showDirectMessageNotification', {
            'senderId': senderId,
            'senderName': senderName,
            'message': message,
            'unreadCount': unreadCount,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } else {
          // ใช้ NotiService ปกติ
          final shortMessage = message.length > 50 ? message.substring(0, 50) + '...' : message;
          _notiService.showNotification(
            title: 'ข้อความใหม่จาก $senderName',
            body: shortMessage,
            payload: json.encode({
              'type': 'direct_message',
              'senderId': senderId,
              'senderName': senderName,
              'message': message,
              'unreadCount': unreadCount,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          );
        }
      }
    } catch (e) {
      print('Error handling direct message notification: $e');
      print('Error details: ${e.toString()}');
    }
  }

  /// ส่งคำสั่งไปยัง background service
  void _sendToBackgroundService(String command, Map<String, dynamic> data) {
    try {
      print('=== SocketService: Sending to Background Service ===');
      print('Command: $command');
      print('Data: $data');
      
      // ใช้ fallback method แทน เนื่องจากไม่ใช้ flutter_background_service แล้ว
      _showCommandFallbackNotification(data, command);
      
    } catch (e) {
      print('=== SocketService: Error sending to background service ===');
      print('Error: $e');
      print('=== SocketService: Using fallback due to exception ===');
      _showCommandFallbackNotification(data, command);
    }
  }

  /// Fallback notification method เมื่อ background service ไม่ทำงาน
  void _showCommandFallbackNotification(Map<String, dynamic> data, String command) {
    try {
      print('=== SocketService: Using fallback notification method ===');
      
      String title = 'การแจ้งเตือน';
      String body = 'คุณมีการแจ้งเตือนใหม่';
      
      if (command == 'showGroupChatNotification') {
        final roomName = data['roomName']?.toString() ?? 'กลุ่ม';
        final message = data['message']?.toString() ?? 'ข้อความใหม่';
        final shortMessage = message.length > 50 ? message.substring(0, 50) + '...' : message;
        title = 'กลุ่ม: $roomName';
        body = 'ข้อความ: $shortMessage';
      } else if (command == 'showDirectMessageNotification') {
        final senderName = data['senderName']?.toString() ?? 'ผู้ใช้';
        final message = data['message']?.toString() ?? 'ข้อความใหม่';
        
        title = 'ข้อความใหม่จาก $senderName';
        body = message.length > 50 ? '${message.substring(0, 50)}...' : message;
      }
      
      // ใช้ FlutterLocalNotificationsPlugin โดยตรง
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      
      // ใช้ channel เดียวกับ FCM service เพื่อให้มี icon ใหม่
      const notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'fcm_foreground_channel',  // ใช้ channel เดียวกับ FCM เพื่อให้มี icon ใหม่
          'FCM Foreground Notifications',
          channelDescription: 'ช่องทางการแจ้งเตือน FCM สำหรับ Foreground',
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
        title,
        body,
        notificationDetails,
        payload: json.encode(data),
      );
      
      print('=== SocketService: Fallback notification shown successfully ===');
      
    } catch (e) {
      print('=== SocketService: Fallback notification failed ===');
      print('Error: $e');
    }
  }

  void handleConnect(dynamic data) {
    print('Socket connected: ${socket.id}');
    _isSocketSetup = true;

    // Resubscribe to announcements if previously subscribed
    if (_isAnnouncementSubscribed) {
      subscribeToAnnouncements();
    }
    // Re-subscribe to other necessary events upon reconnection
  }

  void refreshBackgroundSubscriptions() {
    print('=== SocketService: Refreshing background subscriptions ===');
    subscribeToAnnouncements();
    subscribeToAllNotifications();
  }

  /// ดึง User ID ของผู้ใช้ปัจจุบัน
  Future<String?> _getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        final employeeId = userData['employeeID']?.toString();
        return employeeId;
      }
      
      return null;
    } catch (e) {
      print('Error getting current user ID: $e');
      return null;
    }
  }

  /// ตรวจสอบว่าควรข้ามการแจ้งเตือนจาก Socket หรือไม่
  bool _shouldSkipSocketNotification(Map<String, dynamic> data) {
    try {
      // For now, let's always show notifications from Socket service
      // since the coordination with FCM is not working properly
      print('=== SocketService: Always showing notification (temporary fix) ===');
      return false;
      
    } catch (e) {
      print('Error checking if should skip socket notification: $e');
      return false;
    }
  }
} 