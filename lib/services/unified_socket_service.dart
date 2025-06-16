import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'dart:convert';
import 'connection_manager.dart';
import 'retry_manager.dart';
import 'noti_service.dart';
import 'memory_manager.dart';

/// UnifiedSocketService สำหรับจัดการ Socket ทั้งหมดในที่เดียว
class UnifiedSocketService {
  static final UnifiedSocketService _instance = UnifiedSocketService._internal();
  factory UnifiedSocketService() => _instance;
  UnifiedSocketService._internal();

  final ConnectionManager _connectionManager = ConnectionManager();
  final NotiService _notiService = NotiService();
  final MemoryManager _memoryManager = MemoryManager();
  
  // Event listeners
  final Map<String, List<Function(dynamic)>> _messageListeners = {};
  final Map<String, List<Function(dynamic)>> _announcementListeners = {};
  final Map<String, List<Function(dynamic)>> _connectionListeners = {};
  
  // Configuration
  static const String _baseUrl = 'https://apps.onetwotrading.co.th/';
  static const String _socketPath = '/chatio/socket.io/';
  
  // State tracking
  bool _isInitialized = false;
  String? _currentUserId;
  final Set<String> _subscribedRooms = {};
  final Set<String> _subscribedDirectMessages = {};

  /// Initialize service
  Future<void> initialize({String? userId}) async {
    if (_isInitialized) {
      print('=== UnifiedSocketService: Already initialized ===');
      return;
    }

    print('=== UnifiedSocketService: Initializing ===');
    
    try {
      _currentUserId = userId;
      
      // เริ่มต้น NotiService
      try {
        await _notiService.initNotification();
        print('=== UnifiedSocketService: NotiService initialized successfully ===');
      } catch (e) {
        print('=== UnifiedSocketService: NotiService initialization failed ===');
        print('Error: $e');
        print('=== UnifiedSocketService: Continuing without NotiService ===');
        // ไม่ต้อง rethrow ให้ทำงานต่อ
      }
      
      // ตั้งค่า connection listeners
      _setupConnectionListeners();
      
      _isInitialized = true;
      print('=== UnifiedSocketService: Initialization complete ===');
    } catch (e) {
      print('=== UnifiedSocketService: Initialization error ===');
      print('Error: $e');
      // ไม่ต้อง rethrow ให้ทำงานต่อ
      // rethrow;
    }
  }

  /// ตั้งค่า connection listeners
  void _setupConnectionListeners() {
    _connectionManager.addConnectionListener(_baseUrl, (event) {
      print('=== UnifiedSocketService: Connection event ===');
      print('Event: ${event['event']}');
      print('URL: ${event['url']}');
      print('Data: ${event['data']}');
      
      // เรียก connection listeners
      final listeners = _connectionListeners[event['event']] ?? [];
      for (final listener in listeners) {
        try {
          listener(event);
        } catch (e) {
          print('Error in connection listener: $e');
        }
      }
      
      // ถ้าเชื่อมต่อสำเร็จ ให้ subscribe ใหม่
      if (event['event'] == 'connected') {
        _resubscribeAll();
      }
    });
  }

  /// Subscribe ใหม่ทั้งหมดหลังจาก reconnect
  void _resubscribeAll() {
    print('=== UnifiedSocketService: Resubscribing all ===');
    
    // Resubscribe rooms
    for (final roomId in _subscribedRooms) {
      subscribeToRoom(roomId);
    }
    
    // Resubscribe direct messages
    for (final conversationId in _subscribedDirectMessages) {
      final parts = conversationId.split('_');
      if (parts.length == 2) {
        subscribeToDirectMessages(parts[0], parts[1]);
      }
    }
    
    // Subscribe to announcements
    subscribeToAnnouncements();
  }

  /// ดึง Socket instance
  IO.Socket get socket {
    return _connectionManager.getConnection(_baseUrl);
  }

  /// ตรวจสอบสถานะการเชื่อมต่อ
  bool get isConnected => _connectionManager.isConnected(_baseUrl);

  /// ดึง Socket ID
  String? get socketId => _connectionManager.getSocketId(_baseUrl);

  /// Subscribe ไปยังห้องแชท
  void subscribeToRoom(String roomId) {
    print('=== UnifiedSocketService: Subscribing to room ===');
    print('Room ID: $roomId');
    
    if (!_isInitialized) {
      print('Service not initialized, skipping subscription');
      return;
    }

    if (!isConnected) {
      print('Socket not connected, will retry subscription later');
      _subscribedRooms.add(roomId);
      return;
    }

    try {
      socket.emit('subscribeRoom', {'roomId': roomId});
      _subscribedRooms.add(roomId);
      print('Subscription request sent for room: $roomId');
    } catch (e) {
      print('Error subscribing to room: $e');
    }
  }

  /// Unsubscribe จากห้องแชท
  void unsubscribeFromRoom(String roomId) {
    print('=== UnifiedSocketService: Unsubscribing from room ===');
    print('Room ID: $roomId');
    
    try {
      socket.emit('unsubscribeRoom', {'roomId': roomId});
      _subscribedRooms.remove(roomId);
      print('Unsubscribe request sent for room: $roomId');
    } catch (e) {
      print('Error unsubscribing from room: $e');
    }
  }

  /// Subscribe ไปยังแชทส่วนตัว
  void subscribeToDirectMessages(String senderId, String recipientId) {
    print('=== UnifiedSocketService: Subscribing to direct messages ===');
    print('Sender ID: $senderId');
    print('Recipient ID: $recipientId');
    
    if (!_isInitialized) {
      print('Service not initialized, skipping subscription');
      return;
    }

    if (!isConnected) {
      print('Socket not connected, will retry subscription later');
      final conversationId = '${senderId}_$recipientId';
      _subscribedDirectMessages.add(conversationId);
      return;
    }

    try {
      final conversationId = '${senderId}_$recipientId';
      socket.emit('subscribeDirectMessages', {
        'senderId': senderId,
        'recipientId': recipientId,
        'conversationId': conversationId,
      });
      _subscribedDirectMessages.add(conversationId);
      print('Subscription request sent for direct messages');
    } catch (e) {
      print('Error subscribing to direct messages: $e');
    }
  }

  /// Unsubscribe จากแชทส่วนตัว
  void unsubscribeFromDirectMessages(String senderId, String recipientId) {
    print('=== UnifiedSocketService: Unsubscribing from direct messages ===');
    print('Sender ID: $senderId');
    print('Recipient ID: $recipientId');
    
    try {
      final conversationId = '${senderId}_$recipientId';
      socket.emit('unsubscribeDirectMessages', {
        'senderId': senderId,
        'recipientId': recipientId,
        'conversationId': conversationId,
      });
      _subscribedDirectMessages.remove(conversationId);
      print('Unsubscribe request sent for direct messages');
    } catch (e) {
      print('Error unsubscribing from direct messages: $e');
    }
  }

  /// Subscribe ไปยังประกาศ
  void subscribeToAnnouncements() {
    print('=== UnifiedSocketService: Subscribing to announcements ===');
    
    if (!_isInitialized) {
      print('Service not initialized, skipping subscription');
      return;
    }

    if (!isConnected) {
      print('Socket not connected, will retry subscription later');
      return;
    }

    try {
      socket.emit('subscribeAnnouncements', {});
      print('Subscription request sent for announcements');
    } catch (e) {
      print('Error subscribing to announcements: $e');
    }
  }

  /// เพิ่ม listener สำหรับข้อความ
  void onMessage(String event, Function(dynamic) callback) {
    if (!_messageListeners.containsKey(event)) {
      _messageListeners[event] = [];
      
      // ตั้งค่า socket listener ครั้งแรก
      socket.on(event, (data) {
        print('=== UnifiedSocketService: Message event ===');
        print('Event: $event');
        print('Data: $data');
        
        final listeners = _messageListeners[event] ?? [];
        for (final listener in listeners) {
          try {
            listener(data);
          } catch (e) {
            print('Error in message listener: $e');
          }
        }
      });
      
      // เพิ่ม cleanup callback
      _memoryManager.addCleanupCallback('message_listener', event, () {
        socket.off(event);
      });
    }
    
    _messageListeners[event]!.add(callback);
  }

  /// เพิ่ม listener สำหรับประกาศ
  void onAnnouncement(Function(dynamic) callback) {
    _announcementListeners['newAnnouncement'] = [callback];
    
    socket.on('newAnnouncement', (data) {
      print('=== UnifiedSocketService: Announcement event ===');
      print('Data: $data');
      
      // เรียก callback เท่านั้น ไม่ต้องแสดงการแจ้งเตือนที่นี่
      // การแจ้งเตือนจะถูกจัดการใน SocketService
      for (final listener in _announcementListeners['newAnnouncement'] ?? []) {
        try {
          listener(data);
        } catch (e) {
          print('Error in announcement listener: $e');
        }
      }
    });
    
    // เพิ่ม cleanup callback
    _memoryManager.addCleanupCallback('announcement_listener', 'newAnnouncement', () {
      socket.off('newAnnouncement');
    });
  }

  /// เพิ่ม listener สำหรับการเชื่อมต่อ
  void onConnection(String event, Function(dynamic) callback) {
    if (!_connectionListeners.containsKey(event)) {
      _connectionListeners[event] = [];
    }
    _connectionListeners[event]!.add(callback);
  }

  /// ลบ listener
  void offMessage(String event, Function(dynamic)? callback) {
    if (callback != null) {
      _messageListeners[event]?.remove(callback);
    } else {
      _messageListeners.remove(event);
      socket.off(event);
      _memoryManager.cleanup('message_listener_$event');
    }
  }

  void offAnnouncement() {
    _announcementListeners.clear();
    socket.off('newAnnouncement');
    _memoryManager.cleanup('announcement_listener_newAnnouncement');
  }

  void offConnection(String event, Function(dynamic)? callback) {
    if (callback != null) {
      _connectionListeners[event]?.remove(callback);
    } else {
      _connectionListeners.remove(event);
    }
  }

  /// ส่งข้อความ
  Future<void> sendMessage({
    required String roomId,
    required String message,
    String? replyToId,
    String? replyToMessage,
    bool isAdminNotification = false,
  }) async {
    print('=== UnifiedSocketService: Sending message ===');
    print('Room ID: $roomId');
    print('Message: $message');
    print('Socket connected: $isConnected');
    print('Socket ID: $socketId');
    
    return RetryManager.withSocketRetry(() async {
      // ถ้า socket ไม่เชื่อมต่อ ให้พยายามเชื่อมต่อใหม่
      if (!isConnected) {
        print('Socket not connected, attempting to reconnect...');
        await _attemptReconnection();
        
        // รอให้เชื่อมต่อสำเร็จ
        int attempts = 0;
        while (!isConnected && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          attempts++;
        }
        
        if (!isConnected) {
          throw Exception('Failed to establish socket connection after retry');
        }
      }
      
      print('Socket is connected, sending message...');
      socket.emit('sendMessage', {
        'roomId': roomId,
        'message': message,
        'employeeId': _currentUserId,
        'timestamp': DateTime.now().toIso8601String(),
        'isAdminNotification': isAdminNotification,
        'isReply': replyToId != null,
        'replyToId': replyToId,
        'replyToMessage': replyToMessage,
      });
      
      print('Message sent successfully via socket');
    });
  }

  /// พยายามเชื่อมต่อใหม่
  Future<void> _attemptReconnection() async {
    try {
      print('=== UnifiedSocketService: Attempting reconnection ===');
      
      // ปิดการเชื่อมต่อเก่า (ถ้ามี)
      if (_connectionManager.hasConnection(_baseUrl)) {
        _connectionManager.disconnect(_baseUrl);
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // สร้างการเชื่อมต่อใหม่
      final newSocket = _connectionManager.getConnection(_baseUrl);
      
      // รอให้เชื่อมต่อสำเร็จ
      int attempts = 0;
      while (!newSocket.connected && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
      }
      
      if (newSocket.connected) {
        print('Reconnection successful');
        print('New Socket ID: ${newSocket.id}');
      } else {
        throw Exception('Reconnection failed');
      }
    } catch (e) {
      print('Reconnection error: $e');
      rethrow;
    }
  }

  /// ส่งข้อความส่วนตัว
  Future<void> sendDirectMessage({
    required String recipientId,
    required String message,
    String? replyToId,
    String? replyToMessage,
  }) async {
    print('=== UnifiedSocketService: Sending direct message ===');
    print('Recipient ID: $recipientId');
    print('Message: $message');
    print('Socket connected: $isConnected');
    print('Socket ID: $socketId');
    
    return RetryManager.withSocketRetry(() async {
      if (_currentUserId == null) {
        throw Exception('User ID not found');
      }
      
      // ถ้า socket ไม่เชื่อมต่อ ให้พยายามเชื่อมต่อใหม่
      if (!isConnected) {
        print('Socket not connected, attempting to reconnect...');
        await _attemptReconnection();
        
        // รอให้เชื่อมต่อสำเร็จ
        int attempts = 0;
        while (!isConnected && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          attempts++;
        }
        
        if (!isConnected) {
          throw Exception('Failed to establish socket connection after retry');
        }
      }
      
      final conversationId = '${_currentUserId}_$recipientId';
      
      print('Socket is connected, sending direct message...');
      socket.emit('sendDirectMessage', {
        'employeeId': _currentUserId,
        'recipientId': recipientId,
        'message': message,
        'replyToId': replyToId,
        'replyToMessage': replyToMessage,
        'conversationId': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      print('Direct message sent successfully via socket');
    });
  }

  /// อัปเดต User ID
  void updateUserId(String? userId) {
    _currentUserId = userId;
    print('=== UnifiedSocketService: User ID updated ===');
    print('New User ID: $userId');
  }

  /// Cleanup resources
  void dispose() {
    print('=== UnifiedSocketService: Disposing ===');
    
    // ตรวจสอบว่าเป็น background service หรือไม่
    try {
      final stackTrace = StackTrace.current.toString();
      if (stackTrace.contains('flutter_background_service') || 
          stackTrace.contains('BackgroundService')) {
        print('=== UnifiedSocketService: Background service detected, skipping dispose ===');
        return;
      }
    } catch (e) {
      print('Error checking background service: $e');
    }
    
    // ลบ listeners ทั้งหมด
    _messageListeners.clear();
    _announcementListeners.clear();
    _connectionListeners.clear();
    
    // Clear subscriptions
    _subscribedRooms.clear();
    _subscribedDirectMessages.clear();
    
    // Cleanup memory manager resources
    _memoryManager.cleanupType('message_listener');
    _memoryManager.cleanupType('announcement_listener');
    
    // ปิดการเชื่อมต่อ
    _connectionManager.disconnect(_baseUrl);
    
    _isInitialized = false;
  }

  /// ตรวจสอบสถานะการ initialize
  bool get isInitialized => _isInitialized;

  /// ดึงรายการห้องที่ subscribe อยู่
  Set<String> get subscribedRooms => Set.from(_subscribedRooms);

  /// ดึงรายการแชทส่วนตัวที่ subscribe อยู่
  Set<String> get subscribedDirectMessages => Set.from(_subscribedDirectMessages);
} 