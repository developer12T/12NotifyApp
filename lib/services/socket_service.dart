import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/api_service.dart';
import 'noti_service.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  late IO.Socket socket;
  final NotiService _notiService = NotiService();

  factory SocketService() {
    return _instance;
  }

  SocketService._internal() {
    print('SocketService: Initializing socket with URL: ${ApiService.baseUrl}');
    socket = IO.io('https://apps.onetwotrading.co.th/', <String, dynamic>{
      'transports': ['websocket'],
      'path': '/chatio/socket.io/',
      'reconnection': true,
      'forceNew': true
    });

    print('SocketService: Socket instance created with options:');
    print('- URL: ${ApiService.baseUrl}');
    print('- Path: /socket.io');
    print('- Transport: websocket');
    print('- Reconnection: true');

    // Add explicit connect call
    print('SocketService: Attempting to connect socket...');
    socket?.connect();
    print('SocketService: Socket connect() called');

    // Setup socket event listeners
    socket?.onConnect((_) {
      print('=== SocketService: Socket Connected Successfully ===');
      print('Socket ID: ${socket?.id}');
      print('Socket connected: ${socket?.connected}');
      print('Socket auth: ${socket?.auth}');
      print('Socket nsp: ${socket?.nsp}');

      // Setup message listeners after connection
      _setupMessageListeners();
    });

    socket?.onConnectError((error) {
      print('=== SocketService: Socket Connect Error ===');
      print('Error: $error');
      print('Socket nsp: ${socket?.nsp}');
      print('Socket connected: ${socket?.connected}');
      print('Socket ID: ${socket?.id}');
      print('Base URL: ${ApiService.baseUrl}');
    });

    socket?.onDisconnect((_) {
      print('=== SocketService: Socket Disconnected ===');
      print('Socket ID: ${socket?.id}');
      print('Socket connected: ${socket?.connected}');
    });

    socket?.onError((error) {
      print('=== SocketService: Socket Error ===');
      print('Error: $error');
      print('Socket ID: ${socket?.id}');
      print('Socket connected: ${socket?.connected}');
    });
  }

  void _setupMessageListeners() {
    print('=== SocketService: Setting up Message Listeners ===');
    
    // Remove existing listeners first
    socket?.off('newMessage');
    socket?.off('messageBroadcast');
    socket?.off('messageSent');
    socket?.off('messageReceived');
    socket?.off('roomJoined');
    socket?.off('roomLeft');
    socket?.off('unreadCountUpdate');

    // Listen for message broadcasts (main event from server)
    socket?.on('messageBroadcast', (data) {
      print('=== SocketService: Message Broadcast Received ===');
      print('Raw data: $data');
      
      try {
        // Handle case where data is a list
        dynamic messageData;
        if (data is List) {
          print('Data is a List, length: ${data.length}');
          if (data.isEmpty) {
            print('Empty data list received');
            return;
          }
          messageData = data[0];
        } else if (data is Map) {
          messageData = data;
        } else {
          print('Invalid message data format: ${data.runtimeType}');
          return;
        }

        print('Processed message data:');
        print('- Room ID: ${messageData['room']}');
        print('- Message: ${messageData['message']}');
        print('- Sender: ${messageData['sender']}');
        print('- Timestamp: ${messageData['timestamp']}');
        print('- Is Read: ${messageData['isRead']}');
        print('- Is Reply: ${messageData['isReply']}');
        print('- Reply To: ${messageData['replyTo']}');
        print('- Reply Message: ${messageData['replyToMessage']}');

        // Emit local event for UI update
        socket?.emit('messageReceived', messageData);
      } catch (e) {
        print('Error processing broadcast message: $e');
        print('Stack trace: ${StackTrace.current}');
      }
    });

    // Listen for message sent confirmations
    socket?.on('messageSent', (data) {
      print('=== SocketService: Message Sent Confirmation ===');
      print('Data: $data');
    });

    // Listen for room events
    socket?.on('roomJoined', (data) {
      print('=== SocketService: Room Joined ===');
      print('Data: $data');
      
      // Subscribe to room messages after joining
      if (data is Map && data['roomId'] != null) {
        print('Subscribing to room messages: ${data['roomId']}');
        socket?.emit('subscribeRoom', {'roomId': data['roomId']});
      }
    });

    socket?.on('roomLeft', (data) {
      print('=== SocketService: Room Left ===');
      print('Data: $data');
      
      // Unsubscribe from room messages after leaving
      if (data is Map && data['roomId'] != null) {
        print('Unsubscribing from room messages: ${data['roomId']}');
        socket?.emit('unsubscribeRoom', {'roomId': data['roomId']});
      }
    });

    // Listen for unread count updates
    socket?.on('unreadCountUpdate', (data) {
      print('=== SocketService: Unread Count Update ===');
      print('Data: $data');
    });

    // Listen for announcements events
    socket?.on('newAnnouncement', (data) {
      print('=== SocketService: New Announcement Received ===');
      print('Data: $data');
    });

    // Subscribe to announcements when connected
    socket?.emit('subscribeAnnouncements', {});

    print('=== SocketService: Message Listeners Setup Complete ===');
  }

  // Add method to manually setup listeners
  void setupMessageListeners() {
    print('SocketService: Manually setting up message listeners');
    _setupMessageListeners();
  }

  // Add method to emit test message
  void sendTestMessage(String roomId, String message) {
    print('=== SocketService: Sending Test Message ===');
    print('Room ID: $roomId');
    print('Message: $message');
    print('Socket ID: ${socket?.id}');
    print('Socket connected: ${socket?.connected}');

    if (socket?.connected == true) {
      socket?.emit('sendMessage', {
        'roomId': roomId,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('Test message sent');
    } else {
      print('Cannot send test message: Socket not connected');
    }
  }

  Future<void> connect() async {
    print('SocketService: Attempting to connect socket...');
    print('SocketService: API_BASE_URL: ${ApiService.baseUrl}');
    try {
      socket.connect();
      print('SocketService: Socket connect() called successfully');
    } catch (e) {
      print('SocketService: Error connecting socket: $e');
    }
  }

  void disconnect() {
    print('Disconnecting socket...');
    socket.disconnect();
  }

  void onNewAnnouncement(Function(dynamic) callback, {bool Function()? isInAnnouncementsPage, bool Function()? isAppInForeground}) {
    print('Setting up newAnnouncement listener');
    
    // Subscribe to announcements if socket is connected
    if (socket.connected) {
      socket.emit('subscribeAnnouncements', {});
      print('Subscribed to announcements');
    }
    
    socket.on('newAnnouncement', (data) {
      print('Received new announcement: $data');
      
      // Extract the announcement data from the response
      dynamic announcementData;
      if (data is List && data.isNotEmpty) {
        announcementData = data[0];
      } else if (data is Map) {
        announcementData = data;
      } else {
        print('Invalid announcement data format: ${data.runtimeType}');
        return;
      }
      
      // Handle different data structures
      Map<String, dynamic> formattedData;
      if (announcementData['data'] != null) {
        // If data is nested under 'data' key
        formattedData = {
          ...announcementData['data'],
          'createdBy': {
            'fullNameThai': announcementData['data']['createdBy']?.toString() ?? 'Unknown',
            'department': announcementData['data']['department']?.toString(),
          }
        };
      } else {
        // If data is directly available
        formattedData = {
          ...announcementData,
          'createdBy': {
            'fullNameThai': announcementData['createdBy']?.toString() ?? 'Unknown',
            'department': announcementData['department']?.toString(),
          }
        };
      }
      
      // Show notification for new announcement if:
      // 1. User is not in announcements page, OR
      // 2. App is not in foreground
      final isInAnnouncements = isInAnnouncementsPage?.call() ?? false;
      final isInForeground = isAppInForeground?.call() ?? true;
      print('SocketService: isInAnnouncementsPage check: $isInAnnouncements');
      print('SocketService: isAppInForeground check: $isInForeground');
      
      if (!isInAnnouncements || !isInForeground) {
        print('SocketService: Showing notification for new announcement');
        _notiService.showNotification(
          title: 'ประกาศใหม่: ${formattedData['title']}',
          body: formattedData['content'],
          payload: json.encode(formattedData),
        );
      } else {
        print('User is in announcements page and app is in foreground, skipping notification');
      }
      
      // Call the callback with the formatted announcement data
      callback(formattedData);
    });
  }

  void offNewAnnouncement() {
    print('Removing newAnnouncement listener');
    socket.off('newAnnouncement');
  }

  // Add method to subscribe to room messages
  void subscribeToRoom(String roomId) {
    print('=== SocketService: Subscribing to Room ===');
    print('Room ID: $roomId');
    print('Socket ID: ${socket?.id}');
    print('Socket connected: ${socket?.connected}');

    if (socket?.connected == true) {
      socket?.emit('subscribeRoom', {'roomId': roomId});
      print('Subscribe request sent for room: $roomId');
    } else {
      print('Cannot subscribe: Socket not connected');
    }
  }

  // Add method to unsubscribe from room messages
  void unsubscribeFromRoom(String roomId) {
    print('=== SocketService: Unsubscribing from Room ===');
    print('Room ID: $roomId');
    print('Socket ID: ${socket?.id}');
    print('Socket connected: ${socket?.connected}');

    if (socket?.connected == true) {
      socket?.emit('unsubscribeRoom', {'roomId': roomId});
      print('Unsubscribe request sent for room: $roomId');
    } else {
      print('Cannot unsubscribe: Socket not connected');
    }
  }

  // Add method to test announcements subscription
  void testAnnouncementsSubscription() {
    print('=== SocketService: Testing Announcements Subscription ===');
    print('Socket connected: ${socket.connected}');
    print('Socket ID: ${socket.id}');
    
    if (socket.connected) {
      socket.emit('subscribeAnnouncements', {});
      print('Test subscription request sent for announcements');
    } else {
      print('Cannot test subscription: Socket not connected');
    }
  }

  // Add method to emit test announcement
  void sendTestAnnouncement(String title, String content) {
    print('=== SocketService: Sending Test Announcement ===');
    print('Title: $title');
    print('Content: $content');
    print('Socket ID: ${socket.id}');
    print('Socket connected: ${socket.connected}');

    if (socket.connected) {
      socket.emit('testAnnouncement', {
        'title': title,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('Test announcement sent');
    } else {
      print('Cannot send test announcement: Socket not connected');
    }
  }

  // Add method to test notification service
  // void testNotificationService() {
  //   print('=== SocketService: Testing Notification Service ===');
  //   try {
  //     _notiService.showNotification(
  //       title: 'ทดสอบการแจ้งเตือน',
  //       body: 'นี่คือการทดสอบการแจ้งเตือนจาก SocketService',
  //       payload: json.encode({'type': 'test', 'message': 'test notification'}),
  //     );
  //     print('SocketService: Test notification sent successfully');
  //   } catch (e) {
  //     print('SocketService: Error sending test notification: $e');
  //   }
  // }

  // Add method to test background notification
  // void testBackgroundNotification() {
  //   print('=== SocketService: Testing Background Notification ===');
  //   try {
  //     _notiService.showNotification(
  //       title: 'ประกาศใหม่ (ทดสอบ Background)',
  //       body: 'นี่คือการทดสอบการแจ้งเตือนเมื่อแอปอยู่ใน background',
  //       payload: json.encode({
  //         'type': 'announcement',
  //         'title': 'ประกาศใหม่ (ทดสอบ Background)',
  //         'content': 'นี่คือการทดสอบการแจ้งเตือนเมื่อแอปอยู่ใน background'
  //       }),
  //     );
  //     print('SocketService: Background test notification sent successfully');
  //   } catch (e) {
  //     print('SocketService: Error sending background test notification: $e');
  //   }
  // }
} 