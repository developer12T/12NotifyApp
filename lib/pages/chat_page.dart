import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart'; // Add this import
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_members_page.dart';
import 'group_settings_page.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'web_view_page.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  PlatformFile? _selectedFile; // Add this for file selection
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

  Map<String, dynamic>? _replyingToMessage;
  final FocusNode _messageFocusNode = FocusNode();

  // Add at the top of _ChatPageState
  Timer? _longPressTimer;

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

    setState(() {
      isSending = true;
    });

    try {
      // ส่งข้อความจริง พร้อมข้อมูล reply
      await widget.apiService.sendMessage(
        roomId: widget.roomId,
        message: messageText,
        employeeId: currentUserId!,
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
              }
            : null,
      );

      // ไม่ต้อง insert message ใน messages ตรงนี้ ให้รอจาก socket เท่านั้น

      // ล้างข้อความในช่องพิมพ์และ reply
      _messageController.clear();
      _clearReply();
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
        });
      }
    }
  }

  void _replyToMessage(Map<String, dynamic> message) {
    print('Replying to message: ${message['_id']}');
    setState(() {
      _replyingToMessage = {
        '_id': message['_id'],
        'message': message['message'] ?? '',
        'sender': message['sender'],
        'isImage': message['isImage'] ?? false,
        'imageUrl': message['imageUrl'],
      };
    });
    // Focus the message input field
    _messageFocusNode.requestFocus();
  }

  void _clearReply() {
    print('Clearing reply');
    setState(() {
      _replyingToMessage = null;
    });
  }

  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final sender = _replyingToMessage!['sender'];
    final senderName =
        sender is Map
            ? (sender['fullName'] ?? '...')
            : (sender?.toString() ?? '...');

    final messageText = _replyingToMessage!['message'] ?? '';
    final isImage = _replyingToMessage!['isImage'] == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: Theme.of(context).primaryColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.reply,
                      size: 14,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isImage
                      ? '📷 รูปภาพ${messageText.isNotEmpty ? ': $messageText' : ''}'
                      : messageText,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Colors.grey[600]),
            onPressed: _clearReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyWidget(Map<String, dynamic> replyData) {
    final sender = replyData['sender'];
    final senderName =
        sender is Map
            ? (sender['fullName'] ?? 'Unknown')
            : (sender?.toString() ?? 'Unknown');

    final messageText = replyData['message'] ?? '';
    final isImage = replyData['isImage'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: Colors.grey[500]!, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            isImage
                ? '📷 รูปภาพ${messageText.isNotEmpty ? ': $messageText' : ''}'
                : messageText,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showMessageContextMenu(
    BuildContext context,
    Map<String, dynamic> message,
    Offset position,
  ) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPosition = box.globalToLocal(position);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        localPosition.dx + 1,
        localPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'reply',
          child: Row(
            children: [
              Icon(
                Icons.reply,
                size: 20,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 12),
              Text(
                'ตอบกลับ',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 20, color: Colors.grey[700]),
              const SizedBox(width: 12),
              Text(
                'คัดลอกข้อความ',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        // Copy message to clipboard
        final messageText = message['message'] ?? '';
        if (messageText.isNotEmpty) {
          // สามารถใช้ Clipboard.setData() ถ้าต้องการ
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('คัดลอกข้อความแล้ว')));
        }
      } else if (value == 'reply') {
        _replyToMessage(message);
      }
    });
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

    // Add listener for unreadCountUpdate
    widget.apiService.socket?.on('unreadCountUpdate', (data) {
      print('Received unreadCountUpdate event: $data');
      if (mounted && data is Map) {
        final updateRoomId = data['roomId']?.toString();
        final updateUserId = data['userId']?.toString();
        final count = data['count'];

        if (updateRoomId == widget.roomId) {
          print('Updating unread count for room: $updateRoomId');
          print('User: $updateUserId, Count: $count');

          // Update local state if needed
          setState(() {
            // Update messages if needed
            for (var message in messages) {
              if (message['sender'] is Map &&
                  message['sender']['employeeID']?.toString() !=
                      updateUserId?.toString()) {
                message['isRead'] = true;
              }
            }
          });
        }
      }
    });

    // Listen for connection status
    widget.apiService.socket?.on('connect', (_) {
      print('Socket connected in ChatPage');
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
        });
      }
    });

    widget.apiService.socket?.on('disconnect', (_) {
      print('Socket disconnected in ChatPage');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
        });
      }
    });

    widget.apiService.socket?.on('connecting', (_) {
      print('Socket connecting in ChatPage');
      if (mounted) {
        setState(() {
          isConnecting = true;
        });
      }
    });

    widget.apiService.socket?.on('reconnect', (_) {
      print('Socket reconnected in ChatPage');
      if (mounted) {
        setState(() {
          isConnected = true;
          isConnecting = false;
        });
      }
    });

    widget.apiService.socket?.on('reconnect_attempt', (_) {
      print('Socket reconnect attempt in ChatPage');
      if (mounted) {
        setState(() {
          isConnecting = true;
        });
      }
    });

    // Add listener for message deletion
    widget.apiService.socket?.on('messageDeleted', (data) {
      print('Received messageDeleted event: $data');
      if (mounted && data is Map) {
        final deletedMessageId = data['messageId']?.toString();
        final roomId = data['roomId']?.toString();

        if (roomId == widget.roomId && deletedMessageId != null) {
          setState(() {
            messages.removeWhere((m) => m['_id'] == deletedMessageId);
          });
        }
      }
    });

    widget.apiService.onNewMessage((dynamic data) {
      print('New message data: $data');

      if (!mounted) {
        print('Widget is not mounted, skipping message update');
        return;
      }

      Map<String, dynamic>? message;
      
      // Handle different data formats
      if (data is List && data.isNotEmpty) {
        print('Data is a List, length: ${data.length}');
        if (data.first is Map) {
          print('First element type: ${data.first.runtimeType}');
          message = Map<String, dynamic>.from(data.first);
          print('Extracted message from list:');
        }
      } else if (data is Map) {
        message = Map<String, dynamic>.from(data);
      }

      if (message != null) {
        print('- Message ID: ${message['_id']}');
        print('- Room: ${message['room']}');
        print('- Content: ${message['message']}');
        print('- Sender: ${message['sender']}');
        print('- Timestamp: ${message['timestamp']}');
        print('- Is Read: ${message['isRead']}');
        print('- Success: ${message['success']}');

        // Check if message already exists in the list
        final messageId = message['_id']?.toString();
        if (messageId != null) {
          final existingMessageIndex = messages.indexWhere((m) => m['_id'] == messageId);
          if (existingMessageIndex != -1) {
            print('Message already exists in list, updating instead of adding');
            // Update existing message with any new data
            setState(() {
              messages[existingMessageIndex] = {
                ...messages[existingMessageIndex],
                if (message != null) ...message,
                'isLoading': false, // Ensure loading state is cleared
              };
            });
            return;
          }
        }

        final processedMessage = {
          '_id': message['_id']?.toString(),
          'room': message['room']?.toString(),
          'message': message['message']?.toString(),
          'sender': message['sender'],
          'timestamp': message['timestamp']?.toString(),
          'isRead': message['isRead'] ?? false,
          'isImage': message['isImage'] ?? false,
          'imageUrl': message['imageUrl'],
          'isFile': message['isFile'] ?? false,
          'fileName': message['fileName'] ?? message['filename'],
          'fileType': message['fileType'],
          'fileUrl': message['fileUrl'] ?? message['fileURL'],
          'isReply': message['isReply'] ?? false,
          'replyToId': message['replyToId'],
          'replyToMessage': message['replyToMessage'],
        };

        print('Adding new message to list:');
        print('- ID: ${processedMessage['_id']}');
        print('- Room: ${processedMessage['room']}');
        print('- Content: ${processedMessage['message']}');
        print('- Sender: ${processedMessage['sender']}');
        print('- Timestamp: ${processedMessage['timestamp']}');
        print('- Is Read: ${processedMessage['isRead']}');
        print('DEBUG: processedMessage = $processedMessage');

        // หา temp message ที่ isSending == true และเป็นไฟล์เดียวกัน
        final tempIndex = messages.indexWhere((m) =>
          m?['isSending'] == true &&
          m?['isFile'] == true &&
          m?['fileName'] != null && message?['fileName'] != null &&
          m?['fileName'] == message?['fileName'] &&
          m?['sender'] != null && message?['sender'] != null &&
          m?['sender']?['employeeID'] == message?['sender']?['employeeID']
        );

        if (tempIndex != -1) {
          // แทนที่ temp message ด้วย message จริง
          setState(() {
            messages[tempIndex] = processedMessage;
          });
          return;
        }

        // ป้องกันการ insert ข้อความซ้ำ (เช็ค _id)
        final exists = messages.any((m) => m['_id'] == processedMessage['_id']);
        if (exists) {
          print('Message already exists in messages, skip insert');
          return;
        }

        setState(() {
          messages.insert(0, processedMessage);
        });
      } else {
        print('Received invalid message format: $data');
      }
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
    widget.apiService.leaveRoom(widget.roomId); // Leave room when disposing
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _longPressTimer?.cancel();
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
      // อัพโหลดรูปภาพ พร้อมข้อมูล reply
      await widget.apiService.uploadImage(
        _selectedImage!,
        widget.roomId,
        currentUserId!,
        message: _messageController.text.trim().isNotEmpty ? _messageController.text.trim() : null,
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
              }
            : null,
      );

      // ไม่ต้อง insert message ใน messages ตรงนี้ ให้รอจาก socket เท่านั้น
      setState(() {
        _selectedImage = null;
        _clearReply();
      });
      _messageController.clear();
    } catch (e) {
      print('Error sending image: $e');
      String errorMessage = 'ไม่สามารถส่งรูปภาพได้';

      if (e.toString().contains('Only image files are allowed')) {
        errorMessage = 'กรุณาเลือกรูปภาพที่มีนามสกุล .jpg, .jpeg, .png, .gif หรือ .webp เท่านั้น';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อกับเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
      }

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

  // Add file picker method
  Future<void> _pickAndValidateFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
        allowMultiple: false,
      );

      if (result != null) {
        final file = result.files.first;
        
        // Validate file size (5MB limit)
        if (file.size > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ขนาดไฟล์ต้องไม่เกิน 5MB'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        // Validate file type
        final allowedTypes = ['pdf', 'doc', 'docx', 'xls', 'xlsx'];
        final fileExtension = file.extension?.toLowerCase();
        
        if (fileExtension == null || !allowedTypes.contains(fileExtension)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('กรุณาเลือกไฟล์ PDF, Word หรือ Excel เท่านั้น'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        setState(() {
          _selectedFile = file;
        });
      }
    } catch (e) {
      print('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเลือกไฟล์: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Add file upload method
  Future<void> _sendFile() async {
    if (_selectedFile == null || currentUserId == null) return;

    setState(() {
      isSending = true;
    });

    try {
      // อัพโหลดไฟล์
      await widget.apiService.uploadFile(
        _selectedFile!,
        widget.roomId,
        currentUserId!,
        message: _messageController.text.trim().isNotEmpty ? _messageController.text.trim() : null,
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
              }
            : null,
      );

      // ไม่ต้อง insert message ใน messages ตรงนี้ ให้รอจาก socket เท่านั้น
      setState(() {
        _selectedFile = null;
        _clearReply();
      });
      _messageController.clear();
    } catch (e) {
      print('Error sending file: $e');
      String errorMessage = 'ไม่สามารถส่งไฟล์ได้';

      if (e.toString().contains('File type not allowed')) {
        errorMessage = 'กรุณาเลือกไฟล์ PDF, Word หรือ Excel เท่านั้น';
      } else if (e.toString().contains('File too large')) {
        errorMessage = 'ขนาดไฟล์ต้องไม่เกิน 5MB';
      }

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
                if (_selectedFile != null) {
                  _sendFile();
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

  // Add file preview widget
  Widget _buildSelectedFilePreview() {
    if (_selectedFile == null) return const SizedBox.shrink();

    // Function to truncate filename
    String truncateFilename(String filename, int maxLength) {
      if (filename.length <= maxLength) return filename;
      final extension = filename.split('.').last;
      final nameWithoutExt = filename.substring(0, filename.length - extension.length - 1);
      final truncatedName = nameWithoutExt.substring(0, maxLength - extension.length - 4) + '...';
      return '$truncatedName.$extension';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      alignment: Alignment.centerLeft,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFileIcon(_selectedFile!.extension),
                  color: _getFileColor(_selectedFile!.extension),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        truncateFilename(_selectedFile!.name, 30),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        _formatFileSize(_selectedFile!.size),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                icon: const Icon(Icons.close, color: Colors.white, size: 16),
                onPressed: () {
                  setState(() {
                    _selectedFile = null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for file icons and colors
  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Update message content builder to handle files
  Widget _buildMessageContent(Map<String, dynamic> message, bool isCurrentUser) {
    final bool hasImage = message['isImage'] == true && message['imageUrl'] != null;
    final bool hasFile = message['isFile'] == true && message['fileUrl'] != null;
    final String? text = message['message'];
    final bool isReply = message['isReply'] == true;
    final Map<String, dynamic>? replyToMessage = message['replyToMessage'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isReply && replyToMessage != null) ...[
          _buildReplyWidget(replyToMessage),
          const SizedBox(height: 6),
        ],
        if (hasImage) _buildMessageImage(message['imageUrl'], isCurrentUser),
        if (hasFile) _buildMessageFile(message, isCurrentUser),
        if (text != null && text.trim().isNotEmpty) ...[
          if (hasImage || hasFile) const SizedBox(height: 6),
          ..._parseMessageWithUrls(text).map((part) {
            if (part['type'] == 'text') {
              return Text(
                part['content'],
                style: TextStyle(
                  fontSize: 14,
                  color: isCurrentUser ? Colors.black87 : Colors.black87,
                ),
              );
            } else {
              final bool isYellowButton =
                  part['buttonColor'] == const Color.fromARGB(255, 255, 230, 0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ElevatedButton(
                  onPressed: () => _launchUrl(
                    part['content'],
                    buttonText: part['buttonText'], // ส่ง buttonText ไปด้วย
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        part['buttonColor'] ?? const Color(0xFF3F474E),
                    foregroundColor:
                        isYellowButton ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_new,
                        size: 14,
                        color:
                            isYellowButton
                                ? Colors.black.withOpacity(0.9)
                                : Colors.white.withOpacity(0.9),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        part['buttonText'],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
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

  // Add file message builder
  Widget _buildMessageFile(Map<String, dynamic> message, bool isCurrentUser) {
    final rawFileUrl = message['fileUrl']?.toString() ?? '';
    final fileUrl = rawFileUrl.startsWith('http') 
        ? rawFileUrl 
        : '${ApiService.baseUrl}${rawFileUrl.startsWith('/') ? rawFileUrl : '/$rawFileUrl'}';
    final fileName = message['fileName'];
    final fileType = message['fileType'];

    return GestureDetector(
      onTap: () => _launchUrl(fileUrl),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(fileType),
              color: _getFileColor(fileType),
              size: 32,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'คลิกเพื่อเปิดไฟล์',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
                    // margin: EdgeInsets.only(left: isDesktop ? 12 : 8),
                    // padding: EdgeInsets.symmetric(
                    //   horizontal: isDesktop ? 12 : 8,
                    //   vertical: isDesktop ? 6 : 4,
                    // ),
                    // decoration: BoxDecoration(
                    //   color:
                    //       isConnected
                    //           ? Colors.green
                    //           : isConnecting
                    //           ? Colors.orange
                    //           : Colors.red,
                    //   borderRadius: BorderRadius.circular(12),
                    // ),
                    // child: Text(
                    //   isConnected
                    //       ? 'ออนไลน์'
                    //       : isConnecting
                    //       ? 'กำลังเชื่อมต่อ...'
                    //       : 'ออฟไลน์',
                    //   style: TextStyle(
                    //     fontSize: isDesktop ? 14 : 12,
                    //     color: Colors.white,
                    //   ),
                    // ),
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

                              final messageData = messages[index];
                              final Map<String, dynamic> message =
                                  Map<String, dynamic>.from(messageData);
                              final Map<String, dynamic> sender =
                                  Map<String, dynamic>.from(message['sender']);
                              final messageSenderId = sender['employeeID'];
                              final isCurrentUser =
                                  currentUserId != null &&
                                  messageSenderId != null &&
                                  messageSenderId == currentUserId;

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
                                                Stack(
                                                  children: [
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
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            horizontal:
                                                                isDesktop
                                                                    ? 20
                                                                    : 16,
                                                            vertical:
                                                                isDesktop
                                                                    ? 16
                                                                    : 12,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            message['isSending'] ==
                                                                    true
                                                                ? Colors
                                                                    .grey[200]
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
                                                                .withOpacity(
                                                                  0.05,
                                                                ),
                                                            blurRadius: 8,
                                                            offset:
                                                                const Offset(
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
                                                          SizedBox(height: 6),
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            children: [
                                                              Text(
                                                                formatTime(
                                                                  message['timestamp'],
                                                                ),
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color:
                                                                      Colors
                                                                          .grey[700],
                                                                ),
                                                              ),
                                                              Material(
                                                                color:
                                                                    Colors
                                                                        .transparent,
                                                                child: InkWell(
                                                                  onTap:
                                                                      () => _showMessageMenu(
                                                                        message,
                                                                        isCurrentUser,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                  child: Container(
                                                                    padding:
                                                                        const EdgeInsets.all(
                                                                          6,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Theme.of(
                                                                        context,
                                                                      ).primaryColor.withOpacity(
                                                                        0.1,
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                    ),
                                                                    child: Icon(
                                                                      Icons.more_horiz,
                                                                      size: 18,
                                                                      color:
                                                                          Theme.of(
                                                                            context,
                                                                          ).primaryColor,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
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
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          ),
          // Move file preview here, before the message input
          if (_selectedFile != null) _buildSelectedFilePreview(),
          if (_selectedImage != null) _buildSelectedImagePreview(),
          if (_replyingToMessage != null) 
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildReplyPreview(),
            ),
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
                    color: _selectedImage != null
                        ? colorScheme.primary.withOpacity(0.1)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _selectedImage != null
                          ? Icons.image
                          : Icons.photo_outlined,
                      color: _selectedImage != null
                          ? colorScheme.primary
                          : Colors.grey[600],
                      size: 28,
                    ),
                    tooltip: _selectedImage != null ? 'ส่งรูปภาพ' : 'เลือกรูปภาพ',
                    onPressed: _selectedImage != null ? _sendImage : _pickAndValidateImage,
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  decoration: BoxDecoration(
                    color: _selectedFile != null
                        ? colorScheme.primary.withOpacity(0.1)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _selectedFile != null
                          ? Icons.attach_file
                          : Icons.attach_file_outlined,
                      color: _selectedFile != null
                          ? colorScheme.primary
                          : Colors.grey[600],
                      size: 28,
                    ),
                    tooltip: _selectedFile != null ? 'ส่งไฟล์' : 'เลือกไฟล์',
                    onPressed: _selectedFile != null ? _sendFile : _pickAndValidateFile,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: RawKeyboardListener(
                      focusNode: FocusNode(),
                      onKey: (RawKeyEvent event) {
                        if (event.isKeyPressed(LogicalKeyboardKey.enter)) {
                          if (event.isShiftPressed) {
                            // Insert new line
                            final controller = _messageController;
                            final text = controller.text;
                            final selection = controller.selection;
                            final newText = text.replaceRange(selection.start, selection.end, '');
                            controller.text = newText;
                            controller.selection = TextSelection.collapsed(offset: selection.start + 1);
                          } else {
                            // ส่งข้อความ
                            _sendMessage();
                          }
                        }
                      },
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText:
                              _replyingToMessage != null
                                  ? 'พิมพ์ข้อความตอบกลับ...'
                                  : 'พิมพ์ข้อความ...',
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
                ),
                const SizedBox(width: 12),
                if (_messageController.text.trim().isNotEmpty ||
                    _selectedImage != null ||
                    _selectedFile != null)
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: isSending
                          ? null
                          : _selectedImage != null
                              ? _sendImage
                              : _selectedFile != null
                                  ? _sendFile
                                  : _sendMessage,
                      icon: isSending
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
                                  : _selectedFile != null
                                      ? Icons.send_rounded
                                      : Icons.send_rounded,
                              size: 20,
                            ),
                      color: Colors.white,
                      tooltip: _selectedImage != null
                          ? 'ส่งรูปภาพ'
                          : _selectedFile != null
                              ? 'ส่งไฟล์'
                              : 'ส่งข้อความ',
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

  // Update _launchUrl function to use WebViewPage
  Future<void> _launchUrl(String url, {String? buttonText}) async {
    try {
      // ตรวจสอบและปรับ URL
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }

      print('Opening URL: $url');

      // ถ้าเป็น Windows ให้เปิดในเบราว์เซอร์ภายนอก
      if (Platform.isWindows) {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      // สำหรับแพลตฟอร์มอื่นๆ เปิดใน WebView
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WebViewPage(
              url: url,
              title: buttonText ?? 'เว็บไซต์',
            ),
          ),
        );
      }
    } catch (e) {
      print('Error opening URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเปิดหน้าเว็บ: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'เปิดในเบราว์เซอร์',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  final uri = Uri.parse(url);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  print('Error launching external browser: $e');
                }
              },
            ),
          ),
        );
      }
    }
  }

  void _showMessageMenu(Map<String, dynamic> message, bool isCurrentUser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.reply,
                color: Theme.of(context).primaryColor,
              ),
              title: const Text('ตอบกลับ'),
              onTap: () {
                Navigator.pop(context);
                _replyToMessage(message);
              },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: Colors.grey[700]),
              title: const Text('คัดลอกข้อความ'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('คัดลอกข้อความแล้ว')),
                );
              },
            ),
            if (isCurrentUser)
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red[700]),
                title: Text('ลบ', style: TextStyle(color: Colors.red[700])),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(message['_id']);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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

  // Add new function to handle message deletion
  Future<void> _deleteMessage(String messageId) async {
    try {
      if (currentUserId == null) {
        throw Exception('User ID not found');
      }

      // Show confirmation dialog
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ลบข้อความ'),
          content: const Text('คุณต้องการลบข้อความนี้ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('ลบ'),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('กำลังลบข้อความ...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Call API to delete message
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/api/messages/$messageId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'employeeId': currentUserId}),
      );

      if (response.statusCode == 200) {
        // Remove message from local state
        setState(() {
          messages.removeWhere((m) => m['_id'] == messageId);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ลบข้อความสำเร็จ')),
          );
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'ไม่สามารถลบข้อความได้');
      }
    } catch (e) {
      print('Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถลบข้อความได้: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
