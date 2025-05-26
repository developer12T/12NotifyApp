import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';

class ApiService {
  IO.Socket? socket;  // Make socket nullable
  String? userId;
  static String get baseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
  String? _token;
  bool _isInitialized = false;  // Add initialization flag

  ApiService() {
    print('=== ApiService Constructor ===');
    _initialize();
  }

  Future<void> _initialize() async {
    print('=== Starting ApiService Initialization ===');
    try {
      await _loadUserId();
      await _initSocket();
      _isInitialized = true;
      print('=== ApiService Initialization Complete ===');
      print('Socket connected: ${socket?.connected}');
      print('Socket ID: ${socket?.id}');
      print('User ID: $userId');
    } catch (e) {
      print('=== ApiService Initialization Error ===');
      print('Error: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _loadUserId() async {
    print('=== Loading User ID ===');
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        userId = userData['employeeID']?.toString();
        print('User ID loaded successfully: $userId');
        print('Full user data: $userData');
      } else {
        print('No user data found in SharedPreferences');
      }
    } catch (e) {
      print('Error loading user ID: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _initSocket() async {
    print('=== Socket Initialization ===');
    print('Connecting to: $baseUrl');
    print('User ID at socket init: $userId');

    if (socket != null) {
      print('Socket already exists, disposing old connection');
      print('Old socket ID: ${socket?.id}');
      print('Old socket connected: ${socket?.connected}');
      socket?.disconnect();
      socket?.dispose();
    }

    try {
      socket = IO.io(baseUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
        'forceNew': true,
        'debug': true,
        'auth': userId != null ? {'userId': userId} : null,
        'query': {'userId': userId}, // Add userId to query parameters
        'extraHeaders': {
          'Authorization': 'Bearer $_token', // Add token to headers
        },
      });

      print('Socket instance created');

      // Remove any existing listeners
      socket?.off('connect');
      socket?.off('disconnect');
      socket?.off('error');
      socket?.off('connectError');
      socket?.off('newMessage');
      socket?.off('messageSent');
      socket?.off('roomJoined');
      socket?.off('roomLeft');
      socket?.off('messageBroadcast');
      socket?.off('messageReceived');

      print('Setting up socket event listeners');

      socket?.onConnect((_) {
        print('=== Socket Connected ===');
        print('Socket ID: ${socket?.id}');
        print('Socket connected: ${socket?.connected}');
        print('User ID: $userId');
        print('Socket auth: ${socket?.auth}');
        
        // Emit user connected event
        if (userId != null) {
          socket?.emit('userConnected', {'userId': userId});
          print('Emitted userConnected event');
        }
      });

      socket?.onDisconnect((_) {
        print('=== Socket Disconnected ===');
        print('Attempting to reconnect...');
        Future.delayed(const Duration(seconds: 2), () {
          if (socket?.connected != true) {
            _initSocket();
          }
        });
      });

      socket?.onError((error) {
        print('=== Socket Error ===');
        print('Error: $error');
        // Attempt to reconnect on error
        Future.delayed(const Duration(seconds: 2), () {
          if (socket?.connected != true) {
            _initSocket();
          }
        });
      });

      socket?.onConnectError((error) {
        print('=== Socket Connect Error ===');
        print('Error: $error');
        // Attempt to reconnect on connection error
        Future.delayed(const Duration(seconds: 2), () {
          if (socket?.connected != true) {
            _initSocket();
          }
        });
      });

      // socket?.on('connect', (data) {
      //   print('บอทเชื่อมต่อ socket สำเร็จ');
      //   // ดูห้องที่บอท join อยู่
      //   socket?.emit('getRooms', null, (rooms) {
      //     print('ห้องที่บอท join: $rooms');
      //   });
      // });

    } catch (e) {
      print('Error initializing socket: $e');
      // Attempt to reconnect on initialization error
      Future.delayed(const Duration(seconds: 2), () {
        if (socket?.connected != true) {
          _initSocket();
        }
      });
    }
  }

  Future<String?> getUserId() async {
    if (userId != null) return userId;
    await _loadUserId();
    return userId;
  }

  Future<List<dynamic>> fetchRooms() async {
    await _loadUserId(); // Ensure user ID is loaded
    print('fetchRooms: userId = $userId');
    if (userId == null) throw Exception('User ID not found');

    final response = await http.get(
      Uri.parse('$baseUrl/api/rooms/employee/$userId'),
    );
    print('fetchRooms: statusCode = ${response.statusCode}');
    print('fetchRooms: body = ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['data'] != null && data['data'] is List) {
        return data['data'];
      }
      if (data is Map && data['rooms'] != null) {
        return data['rooms'];
      }
      if (data is List) {
        return data;
      }
      throw Exception('Unexpected response format from fetchRooms');
    } else {
      throw Exception('Failed to fetch rooms');
    }
  }

  Future<Map<String, dynamic>> fetchNotifications(
    String roomId, {
    int page = 1,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/messages/room/$roomId?page=$page'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch notifications');
    }
  }

  void connect() {
    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'auth': {'token': _token},
    });
  }

  Future<void> joinRoom(String roomId) async {
    print('=== Joining Room ===');
    print('Room ID: $roomId');
    print('Socket connected: ${socket?.connected}');
    print('Socket ID: ${socket?.id}');
    print('User ID: $userId');
    
    await ensureInitialized();
    if (socket == null || !socket!.connected) {
      print('Socket not connected, initializing...');
      await _initSocket();
    }

    try {
      // Remove existing listeners
      socket?.off('roomJoined');
      
      print('Emitting joinRoom event');
      final joinData = {
        'roomId': roomId,
        'userId': userId,
      };
      print('Join room payload: $joinData');
      
      socket?.emit('joinRoom', joinData);
      
      // Listen for roomJoined event
      socket?.once('roomJoined', (data) {
        print('=== Room Joined Response ===');
        print('Data: $data');
        print('Socket connected: ${socket?.connected}');
        print('Socket ID: ${socket?.id}');
        
        if (data is Map<String, dynamic>) {
          if (data['success'] == true) {
            print('Successfully joined room: $roomId');
          } else {
            print('Error joining room: ${data['error']}');
          }
        }
      });

      // Add error handler for joinRoom
      socket?.once('error', (error) {
        print('=== Error Joining Room ===');
        print('Error: $error');
        print('Socket connected: ${socket?.connected}');
        print('Socket ID: ${socket?.id}');
      });
    } catch (e) {
      print('=== Error Joining Room ===');
      print('Error details: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> leaveRoom(String roomId) async {
    await ensureInitialized();
    if (socket == null) {
      throw Exception('Socket not initialized');
    }
    print('Leaving room: $roomId'); // Debug log
    socket?.emit('leaveRoom', {'roomId': roomId});
    
    // Listen for roomLeft event
    socket?.once('roomLeft', (data) {
      print('Room left response: $data');
      if (data['success'] == false) {
        print('Error leaving room: ${data['error']}');
      }
    });
  }

  Future<void> leaveAllRooms() async {
    await ensureInitialized();
    if (socket == null) {
      throw Exception('Socket not initialized');
    }
    print('Leaving all rooms'); // Debug log
    socket?.emit('leaveAll', {});
    
    // Listen for leftAllRooms event
    socket?.once('leftAllRooms', (data) {
      print('Left all rooms response: $data');
      if (data['success'] == false) {
        print('Error leaving all rooms: ${data['error']}');
      }
    });
  }

  Future<void> sendMessage({
    required String roomId,
    required String message,
    required String employeeId,
    bool isAdminNotification = false,
  }) async {
    await ensureInitialized();
    print('=== Sending Message ===');
    print('Room ID: $roomId');
    print('Employee ID: $employeeId');
    print('Socket connected: ${socket?.connected}');
    print('Socket ID: ${socket?.id}');
    
    try {
      if (socket?.connected != true) {
        print('Socket not connected, attempting to reconnect...');
        await _initSocket();
        // Wait for connection
        int attempts = 0;
        while (socket?.connected != true && attempts < 5) {
          await Future.delayed(const Duration(seconds: 1));
          attempts++;
        }
        if (socket?.connected != true) {
          throw Exception('Failed to establish socket connection');
        }
      }

      // Emit message directly through socket
      socket?.emit('sendMessage', {
        'roomId': roomId,
        'message': message,
        'employeeId': employeeId,
        'timestamp': DateTime.now().toIso8601String(),
        'isAdminNotification': isAdminNotification,
      });

      // Also send through HTTP for persistence
      final response = await http.post(
        Uri.parse('$baseUrl/api/messages/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomId': [roomId],
          'message': [message],
          'employeeId': employeeId,
          'isAdminNotification': isAdminNotification,
        }),
      );

      print('Message send response: ${response.body}');
      
      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send message');
      }

    } catch (e) {
      print('=== Error Sending Message ===');
      print('Error details: $e');
      rethrow;
    }
  }

  void onNewMessage(Function(dynamic) callback) async {
    await ensureInitialized();
    if (socket == null) {
      print('Socket is null, initializing...');
      await _initSocket();
    }
    
    print('=== Setting up New Message Listener ===');
    print('Socket connected: ${socket?.connected}');
    print('Socket ID: ${socket?.id}');
    
    // Remove ALL existing message listeners to prevent duplicates
    socket?.off('newMessage');
    socket?.off('messageBroadcast');
    socket?.off('messageSent');
    socket?.off('messageReceived');
    
    // Listen for newMessage event
    socket?.on('newMessage', (data) {
      print('=== รับข้อความใหม่ ===');
      print('เป็นข้อความจากบอท: ${(data is Map && data['sender'] is Map) ? (data['sender'] as Map)['role'] == 'bot' : false}');
      print('ข้อมูลทั้งหมด: $data');
      print('Socket connected: ${socket?.connected}');
      print('Socket ID: ${socket?.id}');
      
      try {
        // Handle case where data is a list
        dynamic messageData;
        if (data is List) {
          print('Data is a List, length: ${data.length}');
          if (data.isEmpty) {
            print('Empty data list received');
            return;
          }
          
          // Safely check first element
          final firstElement = data.first;
          print('First element type: ${firstElement.runtimeType}');
          
          if (firstElement is Map) {
            messageData = firstElement;
            print('Extracted message from list:');
            print('- Message ID: ${messageData['_id']}');
            print('- Room: ${messageData['room']}');
            print('- Content: ${messageData['message']}');
            print('- Sender: ${messageData['sender']}');
            print('- Timestamp: ${messageData['timestamp']}');
            print('- Is Read: ${messageData['isRead']}');
            print('- Success: ${messageData['success']}');
          } else {
            print('First element is not a Map, type: ${firstElement.runtimeType}');
            return;
          }
        } else if (data is Map) {
          messageData = data;
          print('Data is a direct message Map');
        } else {
          print('Invalid message data format: ${data.runtimeType}');
          return;
        }

        if (messageData == null) {
          print('No valid message data found');
          return;
        }

        // Process the message data with null safety
        final processedMessage = {
          '_id': messageData['_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'room': messageData['room']?.toString(),
          'message': messageData['message']?.toString() ?? '',
          'sender': messageData['sender'] is Map 
              ? Map<String, dynamic>.from(messageData['sender'])
              : {'fullName': messageData['sender']?.toString() ?? 'Unknown'},
          'timestamp': messageData['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
          'isRead': messageData['isRead'] ?? false,
          'isImage': messageData['isImage'] ?? false,
          'imageUrl': messageData['imageUrl'],
        };

        print('Processed message:');
        print('- ID: ${processedMessage['_id']}');
        print('- Room: ${processedMessage['room']}');
        print('- Content: ${processedMessage['message']}');
        print('- Sender: ${processedMessage['sender']}');
        print('- Timestamp: ${processedMessage['timestamp']}');
        print('- Is Read: ${processedMessage['isRead']}');
        
        print('Calling message callback...');
        callback(processedMessage);
        print('Message callback completed\n');
      } catch (e) {
        print('❌ Error processing new message: $e');
        print('Stack trace: ${StackTrace.current}\n');
      }
    });

    // Add error handler
    socket?.on('error', (error) {
      print('=== Socket Error in Message Listener ===');
      print('Error: $error');
      print('Socket connected: ${socket?.connected}');
      print('Socket ID: ${socket?.id}\n');
    });

    // Add disconnect handler
    socket?.on('disconnect', (reason) {
      print('=== Socket Disconnected in Message Listener ===');
      print('Reason: $reason');
      print('Socket connected: ${socket?.connected}');
      print('Socket ID: ${socket?.id}');
      print('Attempting to reconnect...\n');
      _initSocket();
    });
  }

  Future<void> markRoomAsRead(String roomId) async {
    await _loadUserId(); // Ensure user ID is loaded
    if (userId == null) throw Exception('User ID not found');

    print('\n=== Marking Room as Read ===');
    print('Room ID: $roomId');
    print('User ID: $userId');
    print('Base URL: $baseUrl');
    
    final requestBody = {
      'userId': userId.toString(),
    };
    print('Request body: ${jsonEncode(requestBody)}');
    print('Full URL: $baseUrl/api/rooms/notifications/read/$roomId');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/rooms/notifications/read/$roomId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('Response status code: ${response.statusCode}');
      print('Response headers: ${response.headers}');
      print('Response body: ${response.body}');

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        print('Error response data: $errorData');
        final errorMessage = errorData['message'] ?? 'Failed to mark room as read';
        print('Error message: $errorMessage');
        throw Exception(errorMessage);
      }

      // Listen for unreadCountUpdate socket event
      socket?.once('unreadCountUpdate', (data) {
        print('Received unreadCountUpdate event: $data');
      });

    } catch (e) {
      print('❌ Error in markRoomAsRead:');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadImage(File imageFile, String roomId, String employeeId, {String? message}) async {
    try {
      print('=== Uploading Image ===');
      print('Room ID: $roomId');
      print('Employee ID: $employeeId');
      print('File path: ${imageFile.path}');
      print('Message: $message');

      // Get file extension and determine mimetype
      final fileExtension = imageFile.path.split('.').last.toLowerCase();
      String mimeType;
      switch (fileExtension) {
        case 'jpg':
        case 'jpeg':
          mimeType = 'image/jpeg';
          break;
        case 'png':
          mimeType = 'image/png';
          break;
        case 'gif':
          mimeType = 'image/gif';
          break;
        case 'webp':
          mimeType = 'image/webp';
          break;
        default:
          throw Exception('Unsupported image format: $fileExtension');
      }

      print('File extension: $fileExtension');
      print('Mime type: $mimeType');

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/messages/upload'),
      );

      // Add file to request with explicit mimetype
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType.parse(mimeType),
        ),
      );

      // Add other fields
      request.fields['roomId'] = roomId;
      request.fields['employeeId'] = employeeId;
      if (message != null && message.isNotEmpty) {
        request.fields['message'] = message;
      }

      print('Sending upload request...');
      print('Request fields: ${request.fields}');
      print('Request files: ${request.files.map((f) => '${f.filename} (${f.contentType})').join(', ')}');

      // Send request
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('Upload response status: ${response.statusCode}');
      print('Upload response headers: ${response.headers}');
      print('Upload response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);
          if (responseData['statusCode'] == 200) {
            // Emit socket event for real-time update
            if (socket?.connected == true) {
              print('=== Emitting socket event for uploaded image ===');
              print('Room ID: $roomId');
              print('Image URL: ${responseData['data']['imageUrl']}');
              socket?.emit('sendMessage', {
                'roomId': roomId,
                'message': message ?? '',
                'employeeId': employeeId,
                'timestamp': DateTime.now().toIso8601String(),
                'isImage': true,
                'imageUrl': responseData['data']['imageUrl'],
              });
              print('=== Socket event emitted for uploaded image ===');
            }
            return responseData['data'];
          } else {
            throw Exception(responseData['message'] ?? 'Failed to upload image');
          }
        } catch (e) {
          print('Error parsing response: $e');
          throw Exception('Invalid response format from server');
        }
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? 'Failed to upload image: ${response.statusCode}');
        } catch (e) {
          print('Error parsing error response: $e');
          throw Exception('Failed to upload image: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      print('Error uploading image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  void dispose() {
    print('Disposing socket connection');
    try {
      socket?.off('connect');
      socket?.off('disconnect');
      socket?.off('error');
      socket?.off('connectError');
      socket?.off('newMessage');
      socket?.off('messageSent');
      socket?.off('roomJoined');
      socket?.off('roomLeft');
      
      socket?.disconnect();
      socket?.dispose();
      socket = null;
      _isInitialized = false;
    } catch (e) {
      print('Error disposing socket: $e');
    }
  }

  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await _initialize();
    }else{
      print('Socket already initialized');
    }
  }
}
