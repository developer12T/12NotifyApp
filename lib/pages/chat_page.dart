import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_members_page.dart';
import 'group_settings_page.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class ChatPage extends StatefulWidget {
  final String roomId;
  final String roomName;
  final ApiService apiService;
  final String userRole;
  final String? imageUrl;
  final String color;

  const ChatPage({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.apiService,
    required this.userRole,
    this.imageUrl,
    required this.color,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  List<dynamic> messages = [];
  bool isLoading = true;
  bool isSending = false;
  bool isLoadingMore = false;
  int currentPage = 1;
  int totalPages = 1;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  String? currentUserId;
  bool isConnected = false;
  bool isConnecting = false;

  // เพิ่มตัวแปรสำหรับเก็บ ID ของข้อความที่กำลังส่ง
  Set<String> _sendingMessageIds = {};

  @override
  void initState() {
    super.initState();
    print('ChatPage initialized for room: ${widget.roomId}');
    _loadCurrentUser().then((_) {
      // Only mark as read after user ID is loaded
      if (currentUserId != null) {
        print('Calling _markAsRead from initState');
        _markAsRead();
      }
    });
    fetchMessages();
    _setupSocketListeners();
    _joinRoom();

    _scrollController.addListener(_scrollListener);

    // Add listener to message controller
    _messageController.addListener(() {
      setState(() {}); // Update UI when text changes
    });

    setState(() {
      isConnected = widget.apiService.socket?.connected ?? false;
      isConnecting = !isConnected && widget.apiService.socket != null;
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!isLoadingMore && currentPage < totalPages) {
        fetchMoreMessages();
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      final userData = jsonDecode(userJson);
      print('User data from SharedPreferences: $userData'); // Debug log
      setState(() {
        currentUserId = userData['employeeID'];
      });
      print('Current user ID loaded: $currentUserId'); // Debug log
    } else {
      print('No user data found in SharedPreferences'); // Debug log
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || currentUserId == null) return;

    final messageText = _messageController.text.trim();
    final tempMessageId = DateTime.now().millisecondsSinceEpoch.toString();

    // ตรวจสอบว่ากำลังส่งข้อความนี้อยู่หรือไม่
    // if (_sendingMessageIds.contains(messageText)) {
    //   print('⚠️ Message is already being sent: $messageText');
    //   return;
    // }

    // ตรวจสอบข้อความซ้ำในรายการล่าสุด (5 วินาทีล่าสุด)
    // final recentMessages =
    //     messages.where((m) {
    //       if (m['sender'] is Map &&
    //           m['sender']['employeeID'] == currentUserId &&
    //           m['message'] == messageText) {
    //         final messageTime = DateTime.parse(m['timestamp']);
    //         final timeDiff = DateTime.now().difference(messageTime);
    //         return timeDiff.inSeconds <
    //             5; // ถ้าส่งข้อความเดียวกันภายใน 5 วินาที
    //       }
    //       return false;
    //     }).toList();

    // if (recentMessages.isNotEmpty) {
    //   print('⚠️ Duplicate message detected in recent messages, skipping');
    //   return;
    // }

    setState(() {
      isSending = true;
      _sendingMessageIds.add(messageText); // ใช้ message text แทน ID
    });

    try {
      // ส่งข้อความจริง
      await widget.apiService.sendMessage(
        roomId: widget.roomId,
        message: messageText,
        employeeId: currentUserId!,
      );

      // ล้างข้อความในช่องพิมพ์
      _messageController.clear();
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถส่งข้อความได้: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'ลองอีกครั้ง',
              textColor: Colors.white,
              onPressed: () => _sendMessage(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
          _sendingMessageIds.remove(messageText); // ใช้ message text
        });
      }
    }
  }

  Future<void> _markAsRead() async {
    try {
      print('\n=== Marking Room as Read ===');
      print('Room ID: ${widget.roomId}');
      print('Current User ID: $currentUserId');

      if (currentUserId == null) {
        print('❌ Cannot mark as read: currentUserId is null');
        return;
      }

      if (widget.apiService.socket?.connected != true) {
        print('⚠️ Socket not connected, attempting to reconnect...');
        await widget.apiService.ensureInitialized();
      }

      print('Marking room as read');
      await widget.apiService.markRoomAsRead(widget.roomId);
      print('✅ Successfully marked room as read');

      // Update local message states
      setState(() {
        for (var message in messages) {
          if (message['sender'] is Map &&
              message['sender']['employeeID']?.toString() !=
                  currentUserId?.toString()) {
            message['isRead'] = true;
            print('Updated message ${message['_id']} as read');
          }
        }
      });
    } catch (e) {
      print('❌ Error marking room as read: $e');
      print('Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถอัพเดทสถานะการอ่านได้: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _joinRoom() async {
    print('Joining room: ${widget.roomId}');
    await widget.apiService.joinRoom(widget.roomId);
  }

  void _setupSocketListeners() {
    print('Setting up socket listeners...');

    // เพิ่มตัวแปรเก็บ message IDs ที่ได้รับแล้ว
    final Set<String> receivedMessageIds = <String>{};

    widget.apiService.onNewMessage((dynamic data) {
      print('New message data: $data');

      if (!mounted) {
        print('Widget is not mounted, skipping message update');
        return;
      }

      try {
        dynamic messageData;
        if (data is List && data.isNotEmpty && data[0] is Map) {
          messageData = data[0];
        } else if (data is Map) {
          messageData = data;
        } else {
          print('❌ Invalid message format');
          return;
        }

        // ตรวจสอบว่าเป็นข้อความสำหรับห้องนี้หรือไม่
        if (messageData['room']?.toString() != widget.roomId) {
          return;
        }

        final messageId = messageData['_id']?.toString();
        if (messageId == null) {
          print('❌ Message ID is null');
          return;
        }

        // ตรวจสอบว่าได้รับข้อความนี้แล้วหรือไม่
        if (receivedMessageIds.contains(messageId)) {
          print('ℹ️ Message already received: $messageId');
          return;
        }

        // ตรวจสอบข้อความซ้ำในรายการปัจจุบัน
        final existingIndex = messages.indexWhere((m) => m['_id'] == messageId);
        if (existingIndex != -1) {
          print('ℹ️ Message already exists in list: $messageId');
          return;
        }

        final messageText = messageData['message']?.toString() ?? '';
        final senderId = messageData['sender']?['employeeID']?.toString();
        final messageTimestamp =
            messageData['timestamp']?.toString() ??
            DateTime.now().toIso8601String();

        // ตรวจสอบข้อความซ้ำจากเนื้อหาและเวลา
        final duplicateByContent =
            messages.where((m) {
              if (m['message'] == messageText &&
                  m['sender']?['employeeID']?.toString() == senderId) {
                final existingTime = DateTime.parse(m['timestamp']);
                final newTime = DateTime.parse(messageTimestamp);
                final timeDiff = (existingTime.difference(newTime)).abs();
                return timeDiff.inSeconds <
                    2; // ถ้าข้อความเดียวกันภายใน 2 วินาที
              }
              return false;
            }).toList();

        if (duplicateByContent.isNotEmpty) {
          print('ℹ️ Duplicate message by content detected, skipping...');
          return;
        }

        // เพิ่ม ID ลงใน set
        receivedMessageIds.add(messageId);

        // เพิ่มข้อความใหม่
        final newMessage = {
          '_id': messageId,
          'room': messageData['room'],
          'message': messageText,
          'sender':
              messageData['sender'] is Map
                  ? Map<String, dynamic>.from(messageData['sender'])
                  : {
                    'fullName': messageData['sender']?.toString() ?? 'Unknown',
                    'employeeID': senderId ?? 'Unknown',
                  },
          'timestamp': messageTimestamp,
          'isRead': messageData['isRead'] ?? false,
          'isImage':
              messageData['isImage'] ?? (messageData['imageUrl'] != null),
          'imageUrl': messageData['imageUrl'],
          'status': 'sent',
        };

        setState(() {
          messages.insert(0, newMessage);

          // เลื่อนไปที่ข้อความใหม่ทันที
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            }
          });
        });

        // Mark as read if needed
        if (senderId != currentUserId?.toString()) {
          _markAsRead();
        }
      } catch (e) {
        print('❌ Error processing new message: $e');
        print('Stack trace: ${StackTrace.current}');
      }
    });

    // ... รายการ listeners อื่นๆ
  }

Timer? _sendButtonTimer;

void _handleSendWithDebounce() {
  // ยกเลิก timer เก่า
  _sendButtonTimer?.cancel();
  
  // สร้าง timer ใหม่
  _sendButtonTimer = Timer(const Duration(milliseconds: 300), () {
    _sendMessage();
  });
}


  Future<void> fetchMoreMessages() async {
    if (isLoadingMore || currentPage >= totalPages) return;

    setState(() {
      isLoadingMore = true;
    });

    try {
      final nextPage = currentPage + 1;
      final response = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/api/messages/room/${widget.roomId}?page=$nextPage',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newMessages =
            data['messages'].map((msg) {
              if (msg['message'] != null &&
                  msg['message'].toString().trim().isEmpty) {
                msg.remove('message');
              }
              return msg;
            }).toList();

        // เพิ่มข้อความใหม่ต่อท้ายรายการเดิม
        setState(() {
          messages.addAll(newMessages);
          currentPage = data['pagination']['currentPage'];
          totalPages = data['pagination']['totalPages'];
          isLoadingMore = false;
        });

        // เรียงลำดับข้อความตาม timestamp
        messages.sort((a, b) {
          final aTime = DateTime.parse(a['timestamp']);
          final bTime = DateTime.parse(b['timestamp']);
          return bTime.compareTo(aTime); // เรียงจากใหม่ไปเก่า
        });
      } else {
        setState(() {
          isLoadingMore = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถโหลดข้อความเพิ่มเติมได้')),
          );
        }
      }
    } catch (e) {
      print('Error fetching more messages: $e');
      setState(() {
        isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    }
  }

  Future<void> fetchMessages() async {
    try {
      setState(() {
        isLoading = true;
        currentPage = 1;
        messages = []; // รีเซ็ตรายการข้อความ
      });

      final response = await http.get(
        Uri.parse(
          '${ApiService.baseUrl}/api/messages/room/${widget.roomId}?page=1',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Fetched messages data: $data'); // Debug log

        final fetchedMessages =
            data['messages'].map((msg) {
              if (msg['message'] != null &&
                  msg['message'].toString().trim().isEmpty) {
                msg.remove('message');
              }
              return msg;
            }).toList();

        // เรียงลำดับข้อความตาม timestamp
        fetchedMessages.sort((a, b) {
          final aTime = DateTime.parse(a['timestamp']);
          final bTime = DateTime.parse(b['timestamp']);
          return bTime.compareTo(aTime); // เรียงจากใหม่ไปเก่า
        });

        setState(() {
          messages = fetchedMessages;
          currentPage = data['pagination']['currentPage'];
          totalPages = data['pagination']['totalPages'];
          isLoading = false;
        });

        // เลื่อนไปที่ข้อความล่าสุดหลังจากโหลดเสร็จ
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
            );
          }
        });
      } else {
        print('Error fetching messages: ${response.statusCode}');
        setState(() {
          isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถโหลดข้อความได้')),
          );
        }
      }
    } catch (e) {
      print('Error fetching messages: $e');
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    }
  }

  String formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      return formatter.format(date);
    } catch (e) {
      print('Error formatting date: $e');
      return dateString;
    }
  }

  String formatTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final formatter = DateFormat('HH:mm');
      return formatter.format(date);
    } catch (e) {
      print('Error formatting time: $e');
      return dateString;
    }
  }

  String formatDateOnly(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final formatter = DateFormat('dd/MM/yyyy');
      return formatter.format(date);
    } catch (e) {
      print('Error formatting date only: $e');
      return dateString;
    }
  }

  bool isSameDay(String date1, String date2) {
    try {
      return formatDateOnly(date1) == formatDateOnly(date2);
    } catch (e) {
      print('Error comparing dates: $e');
      return false;
    }
  }

  @override
  void dispose() {
    print('ChatPage disposed for room: ${widget.roomId}'); // Debug log
     _sendButtonTimer?.cancel();
    widget.apiService.leaveRoom(widget.roomId); // Leave room when disposing
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<File?> _pickAndValidateImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        // ตรวจสอบนามสกุลไฟล์
        final fileExtension = image.path.split('.').last.toLowerCase();
        final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];

        if (!allowedExtensions.contains(fileExtension)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'กรุณาเลือกรูปภาพที่มีนามสกุล .jpg, .jpeg, .png, .gif หรือ .webp เท่านั้น',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return null;
        }

        // ตรวจสอบ mimetype
        final file = File(image.path);
        final bytes = await file.readAsBytes();
        final mimeType = _getMimeType(bytes);

        if (!mimeType.startsWith('image/')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'ไฟล์ที่เลือกไม่ใช่รูปภาพ กรุณาเลือกไฟล์รูปภาพเท่านั้น',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return null;
        }

        // ตรวจสอบขนาดไฟล์ (จำกัดที่ 5MB)
        final fileSize = await file.length();
        const maxSize = 5 * 1024 * 1024; // 5MB in bytes

        if (fileSize > maxSize) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ขนาดไฟล์ต้องไม่เกิน 5MB'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return null;
        }

        print('Image validation passed:');
        print('- Path: ${image.path}');
        print('- Extension: $fileExtension');
        print('- MimeType: $mimeType');
        print('- Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

        setState(() {
          _selectedImage = file;
        });

        return file;
      }
      return null;
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  String _getMimeType(List<int> bytes) {
    if (bytes.length < 2) return 'application/octet-stream';

    // Check for JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';

    // Check for PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';

    // Check for GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'image/gif';

    // Check for WebP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    return 'application/octet-stream';
  }

Future<void> _sendImage() async {
  if (_selectedImage == null || currentUserId == null) return;

  // ตรวจสอบประเภทไฟล์อีกครั้งก่อนส่ง
  final fileExtension = _selectedImage!.path.split('.').last.toLowerCase();
  final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];

  if (!allowedExtensions.contains(fileExtension)) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'กรุณาเลือกรูปภาพที่มีนามสกุล .jpg, .jpeg, .png, .gif หรือ .webp เท่านั้น',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
    return;
  }

  // ตรวจสอบ mimetype อีกครั้ง
  final bytes = await _selectedImage!.readAsBytes();
  final mimeType = _getMimeType(bytes);

  if (!mimeType.startsWith('image/')) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ไฟล์ที่เลือกไม่ใช่รูปภาพ กรุณาเลือกไฟล์รูปภาพเท่านั้น',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
    return;
  }

  setState(() {
    isSending = true;
  });

  try {
    print('=== Sending Image ===');
    print('Room ID: ${widget.roomId}');
    print('Current User ID: $currentUserId');
    print('Image path: ${_selectedImage!.path}');
    print('File extension: $fileExtension');
    print('MimeType: $mimeType');

    // ❌ ลบส่วนนี้ออก - ไม่ต้องสร้าง temporary message
    // เพราะ Server จะส่ง Socket event กลับมา
    /*
    final tempMessage = {
      '_id': DateTime.now().millisecondsSinceEpoch.toString(),
      'room': widget.roomId,
      'sender': {'employeeID': currentUserId, 'fullName': 'You'},
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
      'isSending': true,
      'isImage': true,
      'imageUrl': null,
    };
    if (_messageController.text.trim().isNotEmpty) {
      tempMessage['message'] = _messageController.text.trim();
    }

    setState(() {
      messages.insert(0, tempMessage);
    });
    */

    // อัพโหลดรูปภาพ (Server จะ emit Socket event กลับมาเอง)
    final response = await widget.apiService.uploadImage(
      _selectedImage!,
      widget.roomId,
      currentUserId!,
      message: _messageController.text.trim().isNotEmpty 
          ? _messageController.text.trim() 
          : null,
    );

    print('Image upload response: $response');
    print('Image URL: ${response['imageUrl']}');

    if (response == null) {
      throw Exception('ไม่ได้รับข้อมูลการตอบกลับจากเซิร์ฟเวอร์');
    }

    // ❌ ลบส่วนนี้ออก - ไม่ต้องอัพเดท temporary message
    // เพราะ Socket event จะส่งข้อมูลจริงกลับมา
    /*
    setState(() {
      final index = messages.indexWhere((m) => m['isSending'] == true);
      if (index != -1) {
        final updated = {
          ...messages[index],
          '_id': response['_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'sender': response['sender'] ?? {'employeeID': currentUserId, 'fullName': 'You'},
          'timestamp': response['timestamp'] ?? DateTime.now().toIso8601String(),
          'isRead': response['isRead'] ?? false,
          'isSending': false,
          'isImage': true,
          'imageUrl': response['imageUrl'],
        };
        if (response['message'] != null && response['message'].toString().trim().isNotEmpty) {
          updated['message'] = response['message'];
        } else {
          updated.remove('message');
        }
        messages[index] = updated;
      }
    });
    */

    // ล้างข้อความในช่องพิมพ์ถ้ามี
    if (_messageController.text.trim().isNotEmpty) {
      _messageController.clear();
    }

    // รีเซ็ตรูปที่เลือก
    setState(() {
      _selectedImage = null;
    });

    print('✅ Image sent successfully - waiting for Socket event');

  } catch (e) {
    print('Error sending image: $e');
    String errorMessage = 'ไม่สามารถส่งรูปภาพได้';

    if (e.toString().contains('Only image files are allowed')) {
      errorMessage =
          'กรุณาเลือกรูปภาพที่มีนามสกุล .jpg, .jpeg, .png, .gif หรือ .webp เท่านั้น';
    } else if (e.toString().contains('FormatException')) {
      errorMessage =
          'เกิดข้อผิดพลาดในการเชื่อมต่อกับเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
    }

    // ❌ ลบส่วนนี้ออก - ไม่มี temporary message ให้ลบ
    /*
    setState(() {
      messages.removeWhere((m) => m['isSending'] == true);
    });
    */

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'ลองอีกครั้ง',
            textColor: Colors.white,
            onPressed: () {
              if (_selectedImage != null) {
                _sendImage();
              }
            },
          ),
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        isSending = false;
      });
    }
  }
}

Widget _buildImageUploadingIndicator() {
  if (!isSending) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey[300]!),
    ),
    child: Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          'กำลังอัพโหลดรูปภาพ...',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}

  // แก้ไขส่วนของ UI ที่แสดงรูปภาพที่เลือก
  Widget _buildSelectedImagePreview() {
    if (_selectedImage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16),
      alignment: Alignment.centerLeft,
      child: Stack(
        children: [
          Container(
            height: 200,
            width: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: FileImage(_selectedImage!),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedImage = null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roomColor = Color(int.parse(widget.color.replaceAll('#', '0xFF')));

    // ตรวจสอบว่าเป็น desktop หรือไม่
    final isDesktop = MediaQuery.of(context).size.width > 600;

    // ตรวจสอบสิทธิ์การเป็น owner
    final bool isOwner = widget.userRole.toLowerCase() == 'owner';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: roomColor,
        foregroundColor: Colors.white,
        // ปรับ appBar สำหรับ desktop
        toolbarHeight: isDesktop ? 80 : null,
        title: Row(
          children: [
            Container(
              width: isDesktop ? 50 : 40,
              height: isDesktop ? 50 : 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
                image:
                    widget.imageUrl != null
                        ? DecorationImage(
                          image: NetworkImage(
                            '${ApiService.baseUrl}${widget.imageUrl}',
                          ),
                          fit: BoxFit.cover,
                          onError: (exception, stackTrace) {
                            print('Error loading group image: $exception');
                          },
                        )
                        : null,
              ),
              child:
                  widget.imageUrl == null
                      ? Center(
                        child: Text(
                          widget.roomName.characters.first.toUpperCase(),
                          style: TextStyle(
                            fontSize: isDesktop ? 24 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                      : null,
            ),
            SizedBox(width: isDesktop ? 16 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.roomName,
                    style: TextStyle(
                      fontSize: isDesktop ? 22 : 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(left: isDesktop ? 12 : 8),
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 12 : 8,
                      vertical: isDesktop ? 6 : 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isConnected
                              ? Colors.green
                              : isConnecting
                              ? Colors.orange
                              : Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isConnected
                          ? 'ออนไลน์'
                          : isConnecting
                          ? 'กำลังเชื่อมต่อ...'
                          : 'ออฟไลน์',
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context, true),
        ),
        actions: [
          // แสดงปุ่มตั้งค่ากลุ่มเฉพาะ owner เท่านั้น
          if (isOwner)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.menu, size: 26),
                ),
                tooltip: 'ตั้งค่ากลุ่ม',
                onPressed: () async {
                  // ตรวจสอบสิทธิ์อีกครั้งก่อนเปิดหน้าตั้งค่า
                  if (!isOwner) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('คุณไม่มีสิทธิ์เข้าถึงการตั้งค่ากลุ่ม'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => GroupSettingsPage(
                            roomId: widget.roomId,
                            roomName: widget.roomName,
                            userRole: widget.userRole, // ส่ง role ไปด้วย
                          ),
                    ),
                  );
                  if (result == true) {
                    fetchMessages();
                  }
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                isLoading
                    ? Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    )
                    : Stack(
                      children: [
                        RefreshIndicator(
                          color: colorScheme.primary,
                          onRefresh: () async {
                            setState(() {
                              currentPage = 1;
                              messages = [];
                            });
                            await fetchMessages();
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            // ปรับ padding สำหรับ desktop
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 24 : 16,
                              vertical: isDesktop ? 12 : 8,
                            ),
                            itemCount:
                                messages.length + (isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == messages.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: CircularProgressIndicator(
                                      color: colorScheme.primary,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }

                              // Convert message to Map<String, dynamic>
                              final messageData = messages[index];
                              final Map<String, dynamic> message =
                                  Map<String, dynamic>.from(messageData);

                              print(
                                'Message data: $message',
                              ); // Debug log for full message

                              // Get employeeID from sender object
                              final Map<String, dynamic> sender =
                                  Map<String, dynamic>.from(message['sender']);
                              final messageSenderId = sender['employeeID'];
                              final isCurrentUser =
                                  currentUserId != null &&
                                  messageSenderId != null &&
                                  messageSenderId == currentUserId;

                              print(
                                'Message sender employeeID: $messageSenderId, currentUserId: $currentUserId, isCurrentUser: $isCurrentUser',
                              ); // Debug log

                              String senderName = 'Unknown';
                              String senderInitial = '?';
                              if (sender['fullName'] != null) {
                                senderName = sender['fullName'];
                                senderInitial =
                                    senderName.isNotEmpty
                                        ? senderName[0].toUpperCase()
                                        : '?';
                              }

                              Widget? dateSeparator;
                              if (index == messages.length - 1 ||
                                  (index < messages.length - 1 &&
                                      !isSameDay(
                                        message['timestamp'],
                                        messages[index + 1]['timestamp'],
                                      ))) {
                                dateSeparator = Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        formatDateOnly(message['timestamp']),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Column(
                                  key: ValueKey(message['_id']),
                                  children: [
                                    if (dateSeparator != null) dateSeparator,
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: isDesktop ? 6 : 4,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            isCurrentUser
                                                ? MainAxisAlignment.end
                                                : MainAxisAlignment.start,
                                        children: [
                                          if (!isCurrentUser) ...[
                                            GestureDetector(
                                              onTap:
                                                  sender['role'] == 'bot'
                                                      ? null
                                                      : () =>
                                                          _showProfileBottomSheet(
                                                            sender,
                                                          ),
                                              child: Container(
                                                width: isDesktop ? 48 : 42,
                                                height: isDesktop ? 48 : 42,
                                                margin: EdgeInsets.only(
                                                  right: isDesktop ? 12 : 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color:
                                                      sender['role'] == 'bot'
                                                          ? Colors.white
                                                              .withOpacity(0.1)
                                                          : null,
                                                  image:
                                                      sender['role'] != 'bot' &&
                                                              sender['imgUrl'] !=
                                                                  null
                                                          ? DecorationImage(
                                                            image: NetworkImage(
                                                              sender['imgUrl'],
                                                            ),
                                                            fit: BoxFit.cover,
                                                            onError: (
                                                              exception,
                                                              stackTrace,
                                                            ) {
                                                              print(
                                                                'Error loading image: $exception',
                                                              );
                                                            },
                                                          )
                                                          : null,
                                                  gradient:
                                                      sender['role'] != 'bot' &&
                                                              sender['imgUrl'] ==
                                                                  null
                                                          ? LinearGradient(
                                                            colors: [
                                                              colorScheme
                                                                  .primary
                                                                  .withOpacity(
                                                                    0.8,
                                                                  ),
                                                              colorScheme
                                                                  .primary,
                                                            ],
                                                          )
                                                          : null,
                                                ),
                                                child:
                                                    sender['role'] == 'bot'
                                                        ? Image.asset(
                                                          'assets/images/mascot.png',
                                                          fit: BoxFit.cover,
                                                        )
                                                        : sender['imgUrl'] ==
                                                            null
                                                        ? Center(
                                                          child: Text(
                                                            senderInitial,
                                                            style:
                                                                const TextStyle(
                                                                  color:
                                                                      Colors
                                                                          .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        )
                                                        : null,
                                              ),
                                            ),
                                          ],
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment:
                                                  isCurrentUser
                                                      ? CrossAxisAlignment.end
                                                      : CrossAxisAlignment
                                                          .start,
                                              children: [
                                                if (!isCurrentUser)
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                      left: isDesktop ? 16 : 12,
                                                      bottom: isDesktop ? 6 : 4,
                                                    ),
                                                    child: Text(
                                                      senderName,
                                                      style: TextStyle(
                                                        fontSize:
                                                            isDesktop ? 15 : 13,
                                                        color:
                                                            sender['role'] ==
                                                                    'bot'
                                                                ? Colors.red
                                                                : Colors
                                                                    .grey[700],
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  margin: EdgeInsets.only(
                                                    left:
                                                        isCurrentUser
                                                            ? (isDesktop
                                                                ? 80
                                                                : 64)
                                                            : 0,
                                                    right:
                                                        isCurrentUser
                                                            ? 0
                                                            : (isDesktop
                                                                ? 80
                                                                : 64),
                                                  ),
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal:
                                                        isDesktop ? 20 : 16,
                                                    vertical:
                                                        isDesktop ? 16 : 12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        message['isSending'] ==
                                                                true
                                                            ? Colors.grey[200]
                                                            : isCurrentUser
                                                            ? const Color(
                                                              0xFFC3F69D,
                                                            )
                                                            : Colors.white,
                                                    borderRadius: BorderRadius.only(
                                                      topLeft:
                                                          const Radius.circular(
                                                            20,
                                                          ),
                                                      topRight:
                                                          const Radius.circular(
                                                            20,
                                                          ),
                                                      bottomLeft:
                                                          Radius.circular(
                                                            isCurrentUser
                                                                ? 20
                                                                : 4,
                                                          ),
                                                      bottomRight:
                                                          Radius.circular(
                                                            isCurrentUser
                                                                ? 4
                                                                : 20,
                                                          ),
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.05),
                                                        blurRadius: 8,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      _buildMessageContent(
                                                        message,
                                                        isCurrentUser,
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            isDesktop ? 6 : 4,
                                                      ),
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (message['isSending'] ==
                                                              true)
                                                            SizedBox(
                                                              width:
                                                                  isDesktop
                                                                      ? 14
                                                                      : 12,
                                                              height:
                                                                  isDesktop
                                                                      ? 14
                                                                      : 12,
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                valueColor:
                                                                    AlwaysStoppedAnimation<
                                                                      Color
                                                                    >(
                                                                      Colors
                                                                          .grey[400]!,
                                                                    ),
                                                              ),
                                                            ),
                                                          if (message['isSending'] ==
                                                              true)
                                                            SizedBox(
                                                              width:
                                                                  isDesktop
                                                                      ? 6
                                                                      : 4,
                                                            ),
                                                          Text(
                                                            formatTime(
                                                              message['timestamp'],
                                                            ),
                                                            style: TextStyle(
                                                              fontSize:
                                                                  isDesktop
                                                                      ? 12
                                                                      : 11,
                                                              color:
                                                                  message['isSending'] ==
                                                                          true
                                                                      ? Colors
                                                                          .grey[400]
                                                                      : isCurrentUser
                                                                      ? Colors
                                                                          .grey[600]
                                                                      : Colors
                                                                          .grey[600],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          ),
          if (_selectedImage != null) _buildSelectedImagePreview(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color:
                        _selectedImage != null
                            ? colorScheme.primary.withOpacity(0.1)
                            : null,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _selectedImage != null
                          ? Icons.image
                          : Icons.photo_outlined,
                      color:
                          _selectedImage != null
                              ? colorScheme.primary
                              : Colors.grey[600],
                      size: 28,
                    ),
                    tooltip:
                        _selectedImage != null ? 'ส่งรูปภาพ' : 'เลือกรูปภาพ',
                    onPressed:
                        _selectedImage != null
                            ? _sendImage
                            : _pickAndValidateImage,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_messageController.text.trim().isNotEmpty ||
                    _selectedImage != null)
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed:
                          isSending
                              ? null
                              : _selectedImage != null
                              ? _sendImage
                              : _sendMessage,
                      icon:
                          isSending
                              ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : Icon(
                                _selectedImage != null
                                    ? Icons.send_rounded
                                    : Icons.send_rounded,
                                size: 20,
                              ),
                      color: Colors.white,
                      tooltip:
                          _selectedImage != null ? 'ส่งรูปภาพ' : 'ส่งข้อความ',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Add new widget for full-screen image viewer
  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(
                    imageUrl.startsWith('http')
                        ? imageUrl
                        : '${ApiService.baseUrl}$imageUrl',
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value:
                              loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                          color: Colors.white,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      print('Error loading full screen image: $error');
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'เกิดข้อผิดพลาดในการโหลดรูปภาพเต็มหน้าจอ',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
      ),
    );
  }

  // Update _buildMessageImage to use the full-screen viewer
  Widget _buildMessageImage(String? imageUrl, bool isCurrentUser) {
    if (imageUrl == null) {
      print('Image URL is null for message');
      return Container(
        height: 200,
        width: MediaQuery.of(context).size.width * 0.7,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('ไม่สามารถโหลดรูปภาพได้')),
      );
    }

    // สร้าง URL เต็มสำหรับรูปภาพ
    final fullImageUrl =
        imageUrl.startsWith('http')
            ? imageUrl
            : '${ApiService.baseUrl}$imageUrl';

    print('กำลังโหลดรูปภาพจาก URL: $fullImageUrl'); // Debug log

    return GestureDetector(
      onTap: () => _showFullScreenImage(imageUrl),
      child: Hero(
        tag: 'image_$fullImageUrl',
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
            maxHeight: 300,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              fullImageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 200,
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(
                      value:
                          loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                print('เกิดข้อผิดพลาดในการโหลดรูปภาพ: $error');
                print('URL รูปภาพ: $fullImageUrl');
                print('Stack trace: $stackTrace');
                return Container(
                  height: 200,
                  color: Colors.grey[200],
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ไม่สามารถโหลดรูปภาพได้',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Add this function to check if messages should be grouped
  bool _shouldGroupMessages(
    Map<String, dynamic> current,
    Map<String, dynamic>? previous,
  ) {
    if (previous == null) return false;

    // Check if messages are from the same sender
    if (current['sender']['employeeID'] != previous['sender']['employeeID'])
      return false;

    // Check if messages are within 2 minutes of each other
    final currentTime = DateTime.parse(current['timestamp']);
    final previousTime = DateTime.parse(previous['timestamp']);
    final difference = currentTime.difference(previousTime);
    return difference.inMinutes <= 2;
  }

  // Update URL parsing function to handle # as parameter separator
  Map<String, String> _parseUrlParameters(String url) {
    final params = <String, String>{};
    try {
      // Remove any trailing special characters and spaces
      url = url.trim().replaceAll(RegExp(r'[}\s]+$'), '');

      // Find the # separator
      final hashIndex = url.indexOf('#');

      String baseUrl;
      String paramString;

      if (hashIndex > 0) {
        baseUrl = url.substring(0, hashIndex);
        paramString = url.substring(hashIndex + 1);
      } else {
        baseUrl = url;
        paramString = '';
      }

      print('Debug URL parsing:');
      print('Original URL: $url');
      print('Base URL: $baseUrl');
      print('Param String: $paramString');

      // Add base URL to params
      params['baseUrl'] = baseUrl;

      // Parse parameters
      if (paramString.isNotEmpty) {
        final paramPairs = paramString.split('&');
        for (var pair in paramPairs) {
          final parts = pair.split('=');
          if (parts.length == 2) {
            final key = parts[0].trim();
            final value = parts[1].trim();
            params[key] = value;
            print('Found param: $key = $value');
          }
        }
      }
    } catch (e) {
      print('Error parsing URL parameters: $e');
      // If parsing fails, use the original URL as base
      params['baseUrl'] = url;
    }
    return params;
  }

  // Update URL parsing function
  List<Map<String, dynamic>> _parseMessageWithUrls(String text) {
    final urlRegex = RegExp(r'(https?://[^\s]+)');
    final parts = <Map<String, dynamic>>[];
    int lastIndex = 0;

    for (final match in urlRegex.allMatches(text)) {
      // Add text before URL
      if (match.start > lastIndex) {
        parts.add({
          'type': 'text',
          'content': text.substring(lastIndex, match.start),
        });
      }

      // Add URL with parameters
      final url = match.group(0)!;
      final params = _parseUrlParameters(url);

      // Determine button text and color
      String buttonText = params['status'] ?? 'ไปที่ระบบ CreditLimit';
      print('Final buttonText: $buttonText');
      Color buttonColor = const Color(0xFF3F474E); // Default color

      if (params.containsKey('color')) {
        switch (params['color']?.toLowerCase()) {
          case 'green':
            buttonColor = const Color(0xFF4CAF50);
            break;
          case 'red':
            buttonColor = const Color(0xFFE53935);
            break;
          case 'blue':
            buttonColor = const Color(0xFF2196F3);
            break;
          case 'orange':
            buttonColor = const Color(0xFFFF9800);
            break;
          case 'yellow':
            buttonColor = const Color.fromARGB(255, 255, 230, 0);
            break;
          // Add more colors as needed
        }
      }

      parts.add({
        'type': 'url',
        'content': params['baseUrl'] ?? url, // Use base URL for linking
        'buttonText': buttonText,
        'buttonColor': buttonColor,
      });

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < text.length) {
      parts.add({'type': 'text', 'content': text.substring(lastIndex)});
    }

    return parts;
  }

  // Add this function to handle URL launching
  Future<void> _launchUrl(String url) async {
    try {
      // Ensure URL has proper protocol
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }

      final uri = Uri.parse(url);
      print('Launching URL: $uri'); // Debug log

      if (!await launchUrl(
        uri,
        mode:
            LaunchMode
                .externalApplication, // This will open in external browser
      )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถเปิดลิงก์ได้'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเปิดลิงก์: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Update _buildMessageContent to use the button color
  Widget _buildMessageContent(
    Map<String, dynamic> message,
    bool isCurrentUser,
  ) {
    final bool hasImage =
        message['isImage'] == true && message['imageUrl'] != null;
    final String? text = message['message'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage) _buildMessageImage(message['imageUrl'], isCurrentUser),
        if (text != null && text.trim().isNotEmpty) ...[
          if (hasImage) const SizedBox(height: 8),
          ..._parseMessageWithUrls(text).map((part) {
            if (part['type'] == 'text') {
              return Text(
                part['content'],
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrentUser ? Colors.black87 : Colors.black87,
                ),
              );
            } else {
              // Check if button color is yellow to determine text color
              final bool isYellowButton =
                  part['buttonColor'] == const Color.fromARGB(255, 255, 230, 0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: ElevatedButton(
                  onPressed: () => _launchUrl(part['content']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        part['buttonColor'] ?? const Color(0xFF3F474E),
                    foregroundColor:
                        isYellowButton ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 1,
                    shadowColor: Colors.black.withOpacity(0.1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_new,
                        size: 12,
                        color:
                            isYellowButton
                                ? Colors.black.withOpacity(0.9)
                                : Colors.white.withOpacity(0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        part['buttonText'],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isYellowButton ? Colors.black : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }).toList(),
        ],
      ],
    );
  }

  // Add timestamp formatting method
  String _formatTimestamp(String timestamp) {
    final date = DateTime.parse(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  // Update message handling functions
  Future<void> _handleImageUpload() async {
    try {
      final image = await _pickAndValidateImage();
      if (image == null) return;

      final currentUser = await widget.apiService.getUserId();
      if (currentUser == null) {
        throw Exception('User ID not found');
      }

      print('Sending image to room: ${widget.roomId}');
      print('Current user ID: $currentUser');

      // Create temporary message
      final tempMessage = {
        '_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'room': widget.roomId,
        'sender': {'employeeID': currentUser, 'fullName': 'You'},
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': true,
        'isImage': true,
        'imageUrl': null,
        'isLoading': true,
      };
      if (_messageController.text.trim().isNotEmpty) {
        tempMessage['message'] = _messageController.text.trim();
      }

      // Add temporary message to list
      setState(() {
        messages.insert(0, tempMessage);
      });

      // Upload image with optional message
      final message = _messageController.text.trim();
      final response = await widget.apiService.uploadImage(
        image,
        widget.roomId,
        currentUser,
        message: message.isNotEmpty ? message : null,
      );

      // Clear message controller if message was sent
      if (message.isNotEmpty) {
        _messageController.clear();
      }

      // Update message in list with actual data
      setState(() {
        final index = messages.indexWhere(
          (m) => m['_id'] == tempMessage['_id'],
        );
        if (index != -1) {
          final updated = {
            ...messages[index],
            'imageUrl': response['imageUrl'],
            'isLoading': false,
            'isImage': true,
          };
          // อัปเดต message เฉพาะถ้ามีใน response
          if (response['message'] != null &&
              response['message'].toString().trim().isNotEmpty) {
            updated['message'] = response['message'];
          } else {
            updated.remove('message');
          }
          messages[index] = updated;
        }
      });
    } catch (e) {
      print('Error sending image: $e');
      // Remove temporary message on error
      setState(() {
        messages.removeWhere((m) => m['isLoading'] == true);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  Future<void> _handleTextMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      final currentUser = await widget.apiService.getUserId();
      if (currentUser == null) {
        throw Exception('User ID not found');
      }

      // Create temporary message
      final tempMessage = {
        '_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'room': widget.roomId,
        'sender': {'employeeID': currentUser, 'fullName': 'You'},
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': true,
        'isLoading': true,
      };
      if (message.isNotEmpty) {
        tempMessage['message'] = message;
      }

      // Add temporary message to list
      setState(() {
        messages.insert(0, tempMessage);
      });

      // Clear message controller
      _messageController.clear();

      // Send message
      await widget.apiService.sendMessage(
        roomId: widget.roomId,
        message: message,
        employeeId: currentUser,
      );

      // Update message in list
      setState(() {
        final index = messages.indexWhere(
          (m) => m['_id'] == tempMessage['_id'],
        );
        if (index != -1) {
          messages[index] = {...messages[index], 'isLoading': false};
        }
      });
    } catch (e) {
      print('Error sending message: $e');
      // Remove temporary message on error
      setState(() {
        messages.removeWhere((m) => m['isLoading'] == true);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  // Update the send button handler
  void _handleSend() async {
    if (_messageController.text.trim().isNotEmpty) {
      await _handleTextMessage();
    }
  }

  // Update the image button handler
  void _handleImageButton() async {
    await _handleImageUpload();
  }

  // Add new function to show profile bottom sheet
  void _showProfileBottomSheet(Map<String, dynamic> sender) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Profile content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Profile image
                        Container(
                          margin: const EdgeInsets.only(top: 24),
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                sender['role'] == 'bot'
                                    ? Colors.white.withOpacity(0.1)
                                    : null,
                            image:
                                sender['role'] != 'bot' &&
                                        sender['imgUrl'] != null
                                    ? DecorationImage(
                                      image: NetworkImage(sender['imgUrl']),
                                      fit: BoxFit.cover,
                                      onError: (exception, stackTrace) {
                                        print(
                                          'Error loading profile image: $exception',
                                        );
                                      },
                                    )
                                    : null,
                            gradient:
                                sender['role'] != 'bot' &&
                                        sender['imgUrl'] == null
                                    ? LinearGradient(
                                      colors: [
                                        Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.8),
                                        Theme.of(context).colorScheme.primary,
                                      ],
                                    )
                                    : null,
                          ),
                          child:
                              sender['role'] == 'bot'
                                  ? Image.asset(
                                    'assets/images/mascot.png',
                                    fit: BoxFit.cover,
                                  )
                                  : sender['imgUrl'] == null
                                  ? Center(
                                    child: Text(
                                      (sender['fullName'] ?? '?')[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        // User name
                        Column(
                          children: [
                            // Thai name
                            Text(
                              sender['fullNameThai'] ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // English name
                            if (sender['fullName'] != null &&
                                sender['fullName'] != sender['fullNameThai'])
                              Text(
                                sender['fullName']!,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Role badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                sender['role'] == 'bot'
                                    ? Colors.red.withOpacity(0.1)
                                    : Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            sender['role'] == 'bot' ? 'Bot' : 'User',
                            style: TextStyle(
                              color:
                                  sender['role'] == 'bot'
                                      ? Colors.red
                                      : Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Additional info
                        if (sender['role'] != 'bot') ...[
                          _buildInfoItem(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: sender['mail'] ?? 'ไม่ระบุ',
                          ),
                          _buildInfoItem(
                            icon: Icons.business_outlined,
                            label: 'แผนก',
                            value: sender['department'] ?? 'ไม่ระบุ',
                          ),
                          _buildInfoItem(
                            icon: Icons.work_outline,
                            label: 'ตำแหน่ง',
                            value: sender['positon'] ?? 'ไม่ระบุ',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // Helper widget for info items
  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Colors.grey[600]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
