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
    print('SocketService: Initializing socket with URL: ${dotenv.env['API_BASE_URL']}');
    socket = IO.io('http://192.168.2.81', <String, dynamic>{
      'transports': ['websocket'],
      'path': '/chatio/socket.io/',  // ต้องเปิด comment นี้
      'reconnection': false,
      'forceNew': true
    });

    print('SocketService: Socket instance created with options:');
    print('- URL: http://192.168.2.81:80');
    print('- Path: /socket.io');
    print('- Transport: websocket');
    print('- Reconnection: false');

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
      print('Base URL: http://192.168.2.81:80');
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
    print('SocketService: API_BASE_URL: ${dotenv.env['API_BASE_URL']}');
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

  void onNewAnnouncement(Function(dynamic) callback) {
    print('Setting up newAnnouncement listener');
    socket.on('newAnnouncement', (data) {
      print('Received new announcement: $data');
      // Extract the announcement data from the response
      final rawData = data is List ? data[0] : data;
      final announcementData = rawData['data'];
      
      // Ensure the data structure matches the API response
      final formattedData = {
        ...announcementData,
        'createdBy': {
          'fullNameThai': announcementData['createdBy']?.toString() ?? 'Unknown',
          'department': announcementData['department']?.toString(),
        }
      };
      
      // Show notification for new announcement
      _notiService.showNotification(
        title: 'ประกาศใหม่: ${formattedData['title']}',
        body: formattedData['content'],
        payload: json.encode(formattedData),
      );
      
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
} 