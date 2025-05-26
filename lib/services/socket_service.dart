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
    socket = IO.io(dotenv.env['API_BASE_URL'], <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
      'timeout': 10000,
    });

    // Add socket event listeners for debugging
    socket.onConnect((_) {
      print('SocketService: Socket connected successfully');
    });

    socket.onDisconnect((_) {
      print('SocketService: Socket disconnected');
    });

    socket.onError((error) {
      print('SocketService: Socket error: $error');
    });

    socket.onConnectError((error) {
      print('SocketService: Socket connection error: $error');
    });

    socket.onReconnect((_) {
      print('SocketService: Socket reconnected');
    });

    socket.onReconnectAttempt((attemptNumber) {
      print('SocketService: Socket reconnection attempt: $attemptNumber');
    });

    socket.onReconnectError((error) {
      print('SocketService: Socket reconnection error: $error');
    });
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
} 