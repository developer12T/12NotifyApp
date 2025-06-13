import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'unified_socket_service.dart';
import 'retry_manager.dart';

class ApiService {
  // ใช้ UnifiedSocketService แทนการจัดการ Socket เอง
  final UnifiedSocketService _unifiedSocketService = UnifiedSocketService();
  
  String? userId;
  static String get baseUrl =>
      // 'http://127.0.0.1:3000';
      'https://apps.onetwotrading.co.th/12chat';
  String? _token;
  bool _isInitialized = false;

  // Getter สำหรับ socket เพื่อความเข้ากันได้กับโค้ดเดิม
  IO.Socket? get socket => _unifiedSocketService.socket;
  
  // Setter สำหรับ socket เพื่อความเข้ากันได้กับโค้ดเดิม
  set socket(IO.Socket? value) {
    // ไม่ต้องทำอะไร เพราะ socket ถูกจัดการโดย UnifiedSocketService
    print('ApiService: Socket setter called - ignoring (managed by UnifiedSocketService)');
  }

  ApiService() {
    print('=== ApiService Constructor ===');
    _initialize();
  }

  Future<void> _initialize() async {
    print('=== Starting ApiService Initialization ===');
    try {
      await _loadUserId();
      await _initUnifiedSocket();
      _isInitialized = true;
      print('=== ApiService Initialization Complete ===');
      print('Socket connected: ${_unifiedSocketService.isConnected}');
      print('Socket ID: ${_unifiedSocketService.socketId}');
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
        print('getUserId: ${userData['employeeID']}');
        userId = userData['employeeID']?.toString();
        print('User ID loaded successfully: $userId');
        print('Full user data: $userData');
      } else {
        print('getUserId: null');
        print('No user data found in SharedPreferences');
      }
    } catch (e) {
      print('Error loading user ID: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> _initUnifiedSocket() async {
    print('=== UnifiedSocket Initialization ===');
    print('User ID at socket init: $userId');

    try {
      // เริ่มต้น UnifiedSocketService
      await _unifiedSocketService.initialize(userId: userId);
      
      // ตั้งค่า connection listeners
      _unifiedSocketService.onConnection('connected', (event) {
        print('=== ApiService: Socket Connected ===');
        print('Socket ID: ${_unifiedSocketService.socketId}');
        print('User ID: $userId');
        
        // Emit user connected event
        if (userId != null) {
          _unifiedSocketService.socket.emit('userConnected', {'userId': userId});
          print('Emitted userConnected event');
        }
      });

      _unifiedSocketService.onConnection('disconnected', (event) {
        print('=== ApiService: Socket Disconnected ===');
        print('Attempting to reconnect...');
      });

      _unifiedSocketService.onConnection('error', (event) {
        print('=== ApiService: Socket Error ===');
        print('Error: ${event['data']}');
      });

      print('UnifiedSocket initialization complete');
    } catch (e) {
      print('Error initializing UnifiedSocket: $e');
      rethrow;
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

    return RetryManager.withApiRetry(() async {
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
        return [];
      } else {
        throw Exception('Failed to fetch rooms: ${response.statusCode}');
      }
    });
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
    socket = IO.io('https://apps.onetwotrading.co.th/', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'path': '/chatio/socket.io/',
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
      await _initUnifiedSocket();
    }

    try {
      // Remove existing listeners
      socket?.off('roomJoined');

      print('Emitting joinRoom event');
      final joinData = {'roomId': roomId, 'userId': userId};
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

  Future<dynamic> sendMessage({
    required String roomId,
    required String message,
    required String employeeId,
    String? replyToId,
    String? replyToMessage,
    bool isAdminNotification = false,
  }) async {
    await ensureInitialized();
    print('=== Sending Message ===');
    print('Room ID: $roomId');
    print('Employee ID: $employeeId');
    print('Reply To ID: $replyToId');
    print('Reply Message: $replyToMessage');
    print('Socket connected: ${_unifiedSocketService.isConnected}');
    print('Socket ID: ${_unifiedSocketService.socketId}');

    try {
      // พยายามส่งผ่าน socket ก่อน (หลัก)
      if (_unifiedSocketService.isConnected) {
        try {
          await _unifiedSocketService.sendMessage(
            roomId: roomId,
            message: message,
            replyToId: replyToId,
            replyToMessage: replyToMessage,
            isAdminNotification: isAdminNotification,
          );
          print('Message sent successfully via socket');
          
          // ส่งผ่าน HTTP เพื่อความแน่นอน (fallback)
          try {
            final response = await http.post(
              Uri.parse('$baseUrl/api/messages/send'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'roomId': roomId,
                'message': [message],
                'employeeId': employeeId,
                'isAdminNotification': isAdminNotification,
                'isReply': replyToId != null,
                'replyToId': replyToId,
                'replyToMessage': replyToMessage,
              }),
            );
            print('Message also sent via HTTP for persistence');
          } catch (httpError) {
            print('HTTP fallback failed but socket succeeded: $httpError');
          }
          
          return {'success': true, 'method': 'socket'};
        } catch (socketError) {
          print('Socket send failed, trying HTTP: $socketError');
        }
      } else {
        print('Socket not connected, using HTTP only');
      }

      // ถ้า socket ไม่สำเร็จ ให้ใช้ HTTP
      final response = await http.post(
        Uri.parse('$baseUrl/api/messages/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomId': roomId,
          'message': [message],
          'employeeId': employeeId,
          'isAdminNotification': isAdminNotification,
          'isReply': replyToId != null,
          'replyToId': replyToId,
          'replyToMessage': replyToMessage,
        }),
      );

      print('Message send response: ${response.body}');

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send message');
      }

      final responseData = jsonDecode(response.body);
      return responseData['data'] ?? responseData;
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  void onNewMessage(Function(dynamic) callback) async {
    await ensureInitialized();
    
    print('=== Setting up New Message Listener ===');
    print('Socket connected: ${_unifiedSocketService.isConnected}');
    print('Socket ID: ${_unifiedSocketService.socketId}');

    // ใช้ UnifiedSocketService สำหรับจัดการ message listeners
    _unifiedSocketService.onMessage('newMessage', (data) {
      print('=== รับข้อความใหม่ ===');
      print(
        'เป็นข้อความจากบอท: ${(data is Map && data['sender'] is Map) ? (data['sender'] as Map)['role'] == 'bot' : false}',
      );
      print('ข้อมูลทั้งหมด: $data');
      print('Socket connected: ${_unifiedSocketService.isConnected}');
      print('Socket ID: ${_unifiedSocketService.socketId}');

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
            print(
              'First element is not a Map, type: ${firstElement.runtimeType}',
            );
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
          '_id':
              messageData['_id']?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          'room': messageData['room']?.toString(),
          'message': messageData['message']?.toString() ?? '',
          'sender':
              messageData['sender'] is Map
                  ? Map<String, dynamic>.from(messageData['sender'])
                  : {
                    'fullName': messageData['sender']?.toString() ?? 'Unknown',
                  },
          'timestamp':
              messageData['timestamp']?.toString() ??
              DateTime.now().toIso8601String(),
          'isRead': messageData['isRead'] ?? false,
          'isImage': messageData['isImage'] ?? false,
          'imageUrl': messageData['imageUrl'],
          'isFile': messageData['isFile'] ?? false,
          'fileUrl': messageData['fileUrl'],
          'fileName': messageData['fileName'],
          'fileType': messageData['fileType'],
          'isReply': messageData['isReply'] ?? false,
          'replyTo': messageData['replyTo'],
          'replyToMessage':
              messageData['replyToMessage'] is Map
                  ? Map<String, dynamic>.from(messageData['replyToMessage'])
                  : null,
        };

        print('Processed message:');
        print('- ID: ${processedMessage['_id']}');
        print('- Room: ${processedMessage['room']}');
        print('- Content: ${processedMessage['message']}');
        print('- Sender: ${processedMessage['sender']}');
        print('- Timestamp: ${processedMessage['timestamp']}');
        print('- Is Read: ${processedMessage['isRead']}');
        print('- Is Reply: ${processedMessage['isReply']}');
        print('- Reply To: ${processedMessage['replyTo']}');
        print('- Reply To Message: ${processedMessage['replyToMessage']}');

        print('Calling message callback...');
        callback(processedMessage);
        print('Message callback completed\n');
      } catch (e) {
        print('❌ Error processing new message: $e');
        print('Stack trace: ${StackTrace.current}\n');
      }
    });

    // ตั้งค่า connection listeners สำหรับ error handling
    _unifiedSocketService.onConnection('error', (event) {
      print('=== Socket Error in Message Listener ===');
      print('Error: ${event['data']}');
      print('Socket connected: ${_unifiedSocketService.isConnected}');
      print('Socket ID: ${_unifiedSocketService.socketId}\n');
    });

    _unifiedSocketService.onConnection('disconnected', (event) {
      print('=== Socket Disconnected in Message Listener ===');
      print('Socket connected: ${_unifiedSocketService.isConnected}');
      print('Socket ID: ${_unifiedSocketService.socketId}');
      print('Attempting to reconnect...\n');
    });
  }

  Future<void> markRoomAsRead(String roomId) async {
    await _loadUserId(); // Ensure user ID is loaded
    if (userId == null) throw Exception('User ID not found');

    print('\n=== Marking Room as Read ===');
    print('Room ID: $roomId');
    print('User ID: $userId');
    print('Base URL: $baseUrl');

    final requestBody = {'userId': userId.toString()};
    print('Request body: ${jsonEncode(requestBody)}');
    print('Full URL: $baseUrl/api/rooms/notifications/read/$roomId');

    return RetryManager.withApiRetry(() async {
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

      if (response.statusCode == 200) {
        print('Successfully marked room as read');
        return;
      } else {
        throw Exception('Failed to mark room as read: ${response.statusCode}');
      }
    });
  }

  Future<Map<String, dynamic>> uploadImage(
    File imageFile,
    String roomId,
    String employeeId, {
    String? message,
    String? replyToId,
    Map<String, dynamic>? replyToMessage,
  }) async {
    try {
      print('=== Uploading Image ===');
      print('Room ID: $roomId');
      print('Employee ID: $employeeId');
      print('File path: ${imageFile.path}');
      print('Message: $message');
      print('Reply To ID: $replyToId');
      print('Reply Message: $replyToMessage');

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
      if (replyToId != null) {
        request.fields['isReply'] = 'true';
        request.fields['replyToId'] = replyToId;
        if (replyToMessage != null) {
          request.fields['replyToMessage'] = jsonEncode(replyToMessage);
        }
      }

      print('Sending upload request...');
      print('Request fields: ${request.fields}');
      print(
        'Request files: ${request.files.map((f) => '${f.filename} (${f.contentType})').join(', ')}',
      );

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
            // if (socket?.connected == true) {
            //   print('=== Emitting socket event for uploaded image ===');
            //   print('Image URL: ${responseData['data']['imageUrl']}');
            //   socket?.emit('sendMessage', {
            //     'roomId': roomId,
            //     'message': message ?? '',
            //     'employeeId': employeeId,
            //     'timestamp': DateTime.now().toIso8601String(),
            //     'isImage': true,
            //     'imageUrl': responseData['data']['imageUrl'],
            //     'isReply': replyToId != null,
            //     'replyToId': replyToId,
            //     'replyToMessage': replyToMessage,
            //   });
            //   print('=== Socket event emitted for uploaded image ===');
            // }
            return responseData['data'];
          } else {
            throw Exception(
              responseData['message'] ?? 'Failed to upload image',
            );
          }
        } catch (e) {
          print('Error parsing response: $e');
          throw Exception('Invalid response format from server');
        }
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(
            errorData['message'] ??
                'Failed to upload image: ${response.statusCode}',
          );
        } catch (e) {
          print('Error parsing error response: $e');
          throw Exception(
            'Failed to upload image: ${response.statusCode} - ${response.body}',
          );
        }
      }
    } catch (e) {
      print('Error uploading image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<Map<String, dynamic>> uploadFile(
    PlatformFile file,
    String roomId,
    String employeeId, {
    String? message,
    String? replyToId,
    Map<String, dynamic>? replyToMessage,
  }) async {
    try {
      print('\n=== Starting File Upload ===');
      print('Request Details:');
      print('- Endpoint: $baseUrl/api/messages/upload-file');
      print('- Method: POST');
      print('- Content-Type: multipart/form-data');
      print('\nFile Details:');
      print('- Original Name: ${file.name}');
      print('- Size: ${file.size} bytes');
      print('- Extension: ${file.extension}');
      print('- Path: ${file.path}');
      print('\nParameters:');
      print('- Room ID: $roomId');
      print('- Employee ID: $employeeId');
      print('- Message: $message');
      print('- Reply To ID: $replyToId');

      // Validate file exists and is readable
      final fileObj = File(file.path!);
      if (!await fileObj.exists()) {
        throw Exception('File does not exist at path: ${file.path}');
      }

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/messages/upload-file'),
      );

      // Read file bytes and validate
      final fileBytes = await fileObj.readAsBytes();
      print('\nFile Validation:');
      print('- File exists: true');
      print('- File readable: true');
      print('- Bytes read: ${fileBytes.length}');

      // Encode filename for proper Thai character handling
      final encodedFilename = Uri.encodeComponent(file.name);
      print('- Encoded filename: $encodedFilename');

      // Create multipart file with explicit content type and charset
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path!,
        filename: file.name, // Use original filename, not encoded
        contentType: MediaType.parse('application/${file.extension ?? 'octet-stream'}'),
      );

      // Add file to request
      request.files.add(multipartFile);

      // Set proper headers for Thai character support
      request.headers['Content-Type'] = 'multipart/form-data; charset=utf-8';
      request.headers['Accept-Charset'] = 'utf-8';

      // Add other fields
      request.fields.addAll({
        'roomId': roomId,
        'employeeId': employeeId,
        'fileName': file.name, // Send original filename separately
        if (message != null && message.isNotEmpty) 'message': message,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToMessage != null) 'replyToMessage': jsonEncode(replyToMessage),
      });

      // Log complete request details
      print('\nRequest Details:');
      print('Headers:');
      request.headers.forEach((key, value) {
        print('- $key: $value');
      });
      print('\nFields:');
      request.fields.forEach((key, value) {
        print('- $key: $value');
      });
      print('\nFiles:');
      request.files.forEach((file) {
        print('- Field: ${file.field}');
        print('  Original Filename: ${file.filename}');
        print('  Content-Type: ${file.contentType}');
        print('  Length: ${file.length} bytes');
      });

      // Send request
      print('\nSending request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('\nResponse Details:');
      print('- Status Code: ${response.statusCode}');
      print('- Headers:');
      response.headers.forEach((key, value) {
        print('  $key: $value');
      });
      print('- Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('\nUpload successful:');
        print('- Response data: ${data['data']}');
        return data['data'];
      } else {
        final error = jsonDecode(response.body);
        print('\nUpload failed:');
        print('- Error: ${error['message'] ?? 'ไม่สามารถอัพโหลดไฟล์ได้'}');
        throw Exception(error['message'] ?? 'ไม่สามารถอัพโหลดไฟล์ได้');
      }
    } catch (e) {
      print('\n❌ Error in file upload:');
      print('- Type: ${e.runtimeType}');
      print('- Message: $e');
      print('- Stack trace: ${StackTrace.current}');
      rethrow;
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
    } else {
      print('Socket already initialized');
    }
  }

  // Add method to get user information
  Future<Map<String, dynamic>?> getUserInfo(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$employeeId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        print('Error fetching user info: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching user info: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> sendDirectMessage({
    required String recipientId,
    required String message,
    String? replyToId,
    Map<String, dynamic>? replyToMessage,
  }) async {
    await ensureInitialized();
    print('\n=== Sending Direct Message ===');
    print('Recipient ID: $recipientId');
    print('Message: $message');
    print('Reply To ID: $replyToId');
    print('Reply Message: $replyToMessage');
    print('Socket connected: ${_unifiedSocketService.isConnected}');
    print('Socket ID: ${_unifiedSocketService.socketId}');

    try {
      // Get current user ID
      final senderId = await getUserId();
      if (senderId == null) {
        throw Exception('User ID not found');
      }

      // พยายามส่งผ่าน socket ก่อน (หลัก)
      if (_unifiedSocketService.isConnected) {
        try {
          await _unifiedSocketService.sendDirectMessage(
            recipientId: recipientId,
            message: message,
            replyToId: replyToId,
            replyToMessage: replyToMessage != null ? jsonEncode(replyToMessage) : null,
          );
          print('Direct message sent successfully via socket');
          
          // ส่งผ่าน HTTP เพื่อความแน่นอน (fallback)
          try {
            final response = await http.post(
              Uri.parse('$baseUrl/api/direct-messages/send'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'employeeId': senderId,
                'recipientId': recipientId,
                'message': message,
                'replyToId': replyToId,
                'replyToMessage': replyToMessage,
              }),
            );
            print('Direct message also sent via HTTP for persistence');
          } catch (httpError) {
            print('HTTP fallback failed but socket succeeded: $httpError');
          }
          
          return {'success': true, 'method': 'socket'};
        } catch (socketError) {
          print('Socket send failed, trying HTTP: $socketError');
        }
      } else {
        print('Socket not connected, using HTTP only');
      }

      // ถ้า socket ไม่สำเร็จ ให้ใช้ HTTP
      final response = await http.post(
        Uri.parse('$baseUrl/api/direct-messages/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'employeeId': senderId,
          'recipientId': recipientId,
          'message': message,
          'replyToId': replyToId,
          'replyToMessage': replyToMessage,
        }),
      );

      print('Direct message send response: ${response.body}');

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 201 && responseData['success'] == true && responseData['data'] != null) {
        return Map<String, dynamic>.from(responseData);
      } else {
        // Only throw if not success or no data
        throw Exception(responseData['message'] ?? responseData['error'] ?? 'Failed to send direct message');
      }
    } catch (e) {
      print('=== Error Sending Direct Message ===');
      print('Error details: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> markDirectMessagesAsRead(List<String> messageIds, String conversationId) async {
    await ensureInitialized();
    print('\n=== Marking Direct Messages as Read ===');
    print('Message IDs: $messageIds');
    print('Conversation ID: $conversationId');
    print('Socket connected: ${socket?.connected}');
    print('Socket ID: ${socket?.id}');

    try {
      final readerId = await getUserId();
      if (readerId == null) {
        throw Exception('User ID not found');
      }

      if (socket?.connected != true) {
        print('Socket not connected, attempting to reconnect...');
        await _initUnifiedSocket();
      }

      // Emit read status through socket
      socket?.emit('markDirectMessagesRead', {
        'messageIds': messageIds,
        'readerId': readerId,
        'conversationId': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Also update through HTTP for persistence
      final response = await http.post(
        Uri.parse('$baseUrl/api/direct-messages/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'messageIds': messageIds,
          'readerId': readerId,
          'conversationId': conversationId,
        }),
      );

      print('Mark as read response: ${response.body}');

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to mark messages as read');
      }
    } catch (e) {
      print('=== Error Marking Direct Messages as Read ===');
      print('Error details: $e');
      print('Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<void> deleteDirectMessage(String messageId, String conversationId) async {
    await ensureInitialized();
    final senderId = await getUserId();
    if (senderId == null) throw Exception('User ID not found');

    final url = Uri.parse('$baseUrl/api/direct-messages/$messageId?employeeId=$senderId');
    final response = await http.delete(url);

    print('Delete message response: ${response.body}');

    if (response.statusCode != 200) {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['error'] ?? 'Failed to delete message');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await ensureInitialized();
    final senderId = await getUserId();
    if (senderId == null) throw Exception('User ID not found');

    print('=== Delete Message API Call ===');
    print('Message ID: $messageId');
    print('Employee ID: $senderId');
    print('URL: $baseUrl/api/messages/$messageId');

    final response = await http.delete(
      Uri.parse('$baseUrl/api/messages/$messageId'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'employeeId': senderId,
      }),
    );

    print('Delete message response status: ${response.statusCode}');
    print('Delete message response body: ${response.body}');

    if (response.statusCode != 200) {
      Map<String, dynamic> errorData;
      try {
        errorData = jsonDecode(response.body);
      } catch (e) {
        errorData = {'message': 'ไม่สามารถลบข้อความได้'};
      }
      throw Exception(errorData['message'] ?? 'ไม่สามารถลบข้อความได้');
    }
  }

  /// อัพโหลดรูปภาพใน direct message
  Future<Map<String, dynamic>> uploadDirectMessageImage(
    File imageFile,
    String recipientId,
    String employeeId, {
    String? message,
    String? replyToId,
    Map<String, dynamic>? replyToMessage,
  }) async {
    try {
      print('=== Uploading Direct Message Image ===');
      print('Recipient ID: $recipientId');
      print('Employee ID: $employeeId');
      print('File path: ${imageFile.path}');
      print('Message: $message');
      print('Reply To ID: $replyToId');
      print('Reply Message: $replyToMessage');

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
        Uri.parse('$baseUrl/api/direct-messages/upload'),
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
      request.fields.addAll({
        'recipientId': recipientId,
        'employeeId': employeeId,
        'replyToSender': 'false',  // Add default value for replyToSender
        if (message != null && message.isNotEmpty) 'message': message,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToMessage != null) 'replyToMessage': jsonEncode(replyToMessage),
      });

      print('Sending upload request...');
      print('Request fields: ${request.fields}');
      print(
        'Request files: ${request.files.map((f) => '${f.filename} (${f.contentType})').join(', ')}',
      );

      // Send request
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('Upload response status: ${response.statusCode}');
      print('Upload response headers: ${response.headers}');
      print('Upload response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {  // Accept both 200 and 201
        try {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            // Ensure imageUrl has the full base URL
            if (responseData['data'] != null && responseData['data']['imageUrl'] != null) {
              final imageUrl = responseData['data']['imageUrl'];
              if (imageUrl.startsWith('/')) {
                responseData['data']['imageUrl'] = '$baseUrl$imageUrl';
              }
            }
            return responseData['data'];
          } else {
            throw Exception(
              responseData['message'] ?? 'Failed to upload image',
            );
          }
        } catch (e) {
          print('Error parsing response: $e');
          throw Exception('Invalid response format from server');
        }
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(
            errorData['message'] ??
                'Failed to upload image: ${response.statusCode}',
          );
        } catch (e) {
          print('Error parsing error response: $e');
          throw Exception(
            'Failed to upload image: ${response.statusCode} - ${response.body}',
          );
        }
      }
    } catch (e) {
      print('Error uploading image: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<Map<String, dynamic>> uploadDirectMessageFile(
    PlatformFile file,
    String recipientId,
    String employeeId, {
    String? message,
    String? replyToId,
    Map<String, dynamic>? replyToMessage,
  }) async {
    try {
      print('\n=== Starting Direct Message File Upload ===');
      print('Request Details:');
      print('- Endpoint: $baseUrl/api/direct-messages/upload-file');
      print('- Method: POST');
      print('- Content-Type: multipart/form-data');
      print('\nFile Details:');
      print('- Original Name: ${file.name}');
      print('- Size: ${file.size} bytes');
      print('- Extension: ${file.extension}');
      print('- Path: ${file.path}');
      print('\nParameters:');
      print('- Recipient ID: $recipientId');
      print('- Employee ID: $employeeId');
      print('- Message: $message');
      print('- Reply To ID: $replyToId');

      // Validate file exists and is readable
      final fileObj = File(file.path!);
      if (!await fileObj.exists()) {
        throw Exception('File does not exist at path: ${file.path}');
      }

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/direct-messages/upload-file'),
      );

      // Read file bytes and validate
      final fileBytes = await fileObj.readAsBytes();
      print('\nFile Validation:');
      print('- File exists: true');
      print('- File readable: true');
      print('- Bytes read: ${fileBytes.length}');

      // Encode filename for proper Thai character handling
      final encodedFilename = Uri.encodeComponent(file.name);
      print('- Encoded filename: $encodedFilename');

      // Create multipart file with explicit content type and charset
      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path!,
        filename: file.name, // Use original filename, not encoded
        contentType: MediaType.parse('application/${file.extension ?? 'octet-stream'}'),
      );

      // Add file to request
      request.files.add(multipartFile);

      // Set proper headers for Thai character support
      request.headers['Content-Type'] = 'multipart/form-data; charset=utf-8';
      request.headers['Accept-Charset'] = 'utf-8';

      // Add other fields
      request.fields.addAll({
        'recipientId': recipientId,
        'employeeId': employeeId,
        'fileName': file.name, // Send original filename separately
        if (message != null && message.isNotEmpty) 'message': message,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToMessage != null) 'replyToMessage': jsonEncode(replyToMessage),
      });

      // Log complete request details
      print('\nRequest Details:');
      print('Headers:');
      request.headers.forEach((key, value) {
        print('- $key: $value');
      });
      print('\nFields:');
      request.fields.forEach((key, value) {
        print('- $key: $value');
      });
      print('\nFiles:');
      request.files.forEach((file) {
        print('- Field: ${file.field}');
        print('  Original Filename: ${file.filename}');
        print('  Content-Type: ${file.contentType}');
        print('  Length: ${file.length} bytes');
      });

      // Send request
      print('\nSending request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('\nResponse Details:');
      print('- Status Code: ${response.statusCode}');
      print('- Headers:');
      response.headers.forEach((key, value) {
        print('  $key: $value');
      });
      print('- Body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          print('\nUpload successful:');
          print('- Response data: ${data['data']}');
          return data['data'];
        } else {
          print('\nUpload failed:');
          print('- Error: ${data['error'] ?? 'ไม่สามารถส่งไฟล์ได้'}');
          throw Exception(data['error'] ?? 'ไม่สามารถส่งไฟล์ได้');
        }
      } else {
        final error = jsonDecode(response.body);
        print('\nUpload failed:');
        print('- Error: ${error['error'] ?? 'ไม่สามารถส่งไฟล์ได้'}');
        throw Exception(error['error'] ?? 'ไม่สามารถส่งไฟล์ได้');
      }
    } catch (e) {
      print('\n❌ Error in uploadDirectMessageFile:');
      print('- Type: ${e.runtimeType}');
      print('- Message: $e');
      print('- Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  /// Refresh socket subscriptions for list pages
  Future<void> refreshListPageSubscriptions() async {
    await ensureInitialized();
    
    if (userId != null && socket?.connected == true) {
      print('Refreshing list page subscriptions');
      
      try {
        // Add a small delay to ensure proper cleanup from previous subscriptions
        await Future.delayed(const Duration(milliseconds: 150));
        
        // Subscribe to chat list updates
        print('Subscribing to chat list updates...');
        socket?.emit('subscribeChatList', {
          'empId': userId
        });
        
        // Subscribe to direct message updates with more detailed data
        print('Subscribing to direct message updates...');
        final directMessageData = {
          'senderId': userId,
          'recipientId': userId,
        };
        print('Direct message subscription data: $directMessageData');
        socket?.emit('subscribeDirectMessages', directMessageData);
        
        // Add confirmation listeners with timeout
        bool chatListConfirmed = false;
        bool directMessagesConfirmed = false;
        
        socket?.once('chatListSubscribed', (data) {
          print('✅ Chat list subscription confirmed: $data');
          chatListConfirmed = true;
        });
        
        socket?.once('directMessagesSubscribed', (data) {
          print('✅ Direct messages subscription confirmed: $data');
          directMessagesConfirmed = true;
        });
        
        // Wait for confirmations with timeout
        await Future.delayed(const Duration(milliseconds: 1000));
        
        if (!chatListConfirmed) {
          print('⚠️ Chat list subscription confirmation not received, but continuing...');
        }
        if (!directMessagesConfirmed) {
          print('⚠️ Direct messages subscription confirmation not received, but continuing...');
        }
        
        print('List page subscriptions refreshed successfully');
      } catch (e) {
        print('❌ Error refreshing list page subscriptions: $e');
        print('Stack trace: ${StackTrace.current}');
      }
    } else {
      print('Cannot refresh subscriptions: User ID: $userId, Socket connected: ${socket?.connected}');
      
      // Try to reconnect if not connected
      if (socket != null && !socket!.connected) {
        print('🔄 Attempting to reconnect socket...');
        socket?.connect();
        
        // Wait a bit and try again
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (userId != null) {
            print('🔄 Retrying subscription after reconnection...');
            refreshListPageSubscriptions();
          }
        });
      }
    }
  }
}
