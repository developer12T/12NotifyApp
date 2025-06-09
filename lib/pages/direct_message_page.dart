import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class DirectMessagePage extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final String? recipientImage;
  final ApiService apiService;

  const DirectMessagePage({
    super.key,
    required this.recipientId,
    required this.recipientName,
    required this.apiService,
    this.recipientImage,
  });

  @override
  State<DirectMessagePage> createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends State<DirectMessagePage> {
  // Controllers และ Focus
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  // File selections
  File? _selectedImage;
  PlatformFile? _selectedFile;

  // State variables
  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  bool isSending = false;
  String? currentUserId;
  bool isConnected = false;
  bool isConnecting = false;
  bool _socketListenersSetup = false;
  Map<String, dynamic>? _replyingToMessage;

  @override
  void initState() {
    super.initState();
    _initializeComponent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _removeSocketListeners();
    super.dispose();
  }

  /// แก้ไข: เรียงลำดับการ initialize ให้ถูกต้อง
  Future<void> _initializeComponent() async {
    try {
      // 1. โหลด User ID ก่อน
      await _loadCurrentUserEmployeeId();
      
      // 2. ถ้ายัง mounted อยู่ ค่อยทำส่วนอื่น
      if (mounted) {
        // 3. Setup socket listeners
        _setupSocketListeners();
        
        // 4. Setup text controller listener
        _messageController.addListener(() {
          if (mounted) setState(() {});
        });
        
        // 5. Scroll ไปด้านล่างหลัง build เสร็จ
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToBottom();
        });
      }
    } catch (e) {
      print('❌ Error initializing component: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// แก้ไข: เพิ่ม error handling และ safety checks
  Future<void> _loadCurrentUserEmployeeId() async {
    print('\n=== Loading User ID ===');
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        final employeeId = userData['employeeID']?.toString();
        
        if (employeeId != null) {
          if (mounted) {
            setState(() {
              currentUserId = employeeId;
            });
          }
          
          print('✅ User ID loaded: $employeeId');
          
          // โหลด messages หลังจากได้ user ID
          await _loadMessages();
          
        } else {
          print('❌ Employee ID is null');
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
        }
      } else {
        print('❌ No user data found');
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading user ID: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// แก้ไข: ปรับปรุงการ setup socket listeners
  void _setupSocketListeners() {
    // ตรวจสอบเงื่อนไขก่อน setup
    if (_socketListenersSetup || widget.apiService.socket == null || !mounted) {
      print('⏭️ Skip socket setup');
      return;
    }

    print('\n=== Setting up Socket Listeners ===');
    
    // ลบ listeners เก่าก่อน
    _removeSocketListeners();

    // Connection status listeners
    widget.apiService.socket?.on('connect', (_) {
      print('✅ Socket Connected');
      if (currentUserId != null && mounted) {
        _subscribeToDirectMessages();
        setState(() {
          isConnected = true;
          isConnecting = false;
        });
      }
    });

    widget.apiService.socket?.on('disconnect', (_) {
      print('❌ Socket Disconnected');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
        });
      }
    });

    widget.apiService.socket?.on('connect_error', (error) {
      print('❌ Socket Connection Error: $error');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
        });
      }
    });

    // Message event listeners
    widget.apiService.socket?.on('newDirectMessage', (data) {
      _handleNewDirectMessage(data);
    });

    widget.apiService.socket?.on('directMessageSent', (data) {
      print('\n✅ Direct Message Sent Confirmation');
      _handleDirectMessageSent(data);
    });

    widget.apiService.socket?.on('directMessagesRead', (data) {
      print('\n👁️ Direct Messages Read');
      _handleMessagesRead(data);
    });

    widget.apiService.socket?.on('directMessageDeleted', (data) {
      final messageId = data['messageId'];
      if (messageId != null) {
        setState(() {
          messages.removeWhere((m) => m['_id'] == messageId);
        });
      }
    });

    widget.apiService.socket?.on('newDirectMessageNotification', (data) {
      if (!mounted) return;
      try {
        final notification = data is Map ? data : {};
        final recipientId = notification['recipientId']?.toString();
        final sender = notification['sender'] as Map?;
        final senderId = sender?['employeeID']?.toString();
        final messageId = notification['_id']?.toString();

        // จัดการ reply message
        if (notification['replyToMessage'] != null) {
          final replyData = notification['replyToMessage'];
          final replySender = replyData['sender'] as Map?;
          final hasReplyContent =
            (replySender != null && (replySender['fullName']?.toString().trim().isNotEmpty ?? false)) ||
            (replyData['message']?.toString().trim().isNotEmpty ?? false);

          if (hasReplyContent) {
            notification['replyToMessage'] = {
              'messageId': replyData['messageId'] ?? replyData['_id'],
              'message': replyData['message'] ?? '',
              'sender': replyData['sender'] ?? {
                'employeeID': replyData['senderId'] ?? 'unknown',
                'fullName': 'Unknown User',
                'department': '',
                'imgUrl': null,
              },
              'isImage': replyData['isImage'] ?? false,
              'imageUrl': replyData['imageUrl'],
              'isFile': replyData['isFile'] ?? false,
              'fileName': replyData['fileName'],
              'fileType': replyData['fileType'],
              'fileUrl': replyData['fileUrl'],
              'timestamp': replyData['timestamp'] ?? replyData['isoString'],
            };
          } else {
            notification['replyToMessage'] = null;
          }
        }

        if ((recipientId == currentUserId && senderId == widget.recipientId) ||
            (senderId == currentUserId && recipientId == widget.recipientId)) {
          setState(() {
            final exists = messages.any((m) => m['_id'] == messageId);
            if (!exists) {
              messages.add({
                '_id': messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
                'message': notification['message'] ?? '',
                'timestamp': notification['isoString'] ?? notification['timestamp'] ?? DateTime.now().toIso8601String(),
                'isoString': notification['isoString'] ?? notification['timestamp'] ?? DateTime.now().toIso8601String(),
                'isRead': false,
                'isSending': false,
                'isImage': notification['isImage'] ?? false,
                'imageUrl': notification['imageUrl'],
                'isFile': notification['isFile'] ?? false,
                'fileName': notification['fileName'],
                'fileType': notification['fileType'],
                'fileUrl': notification['fileUrl'],
                'isReply': notification['replyToMessage'] != null,
                'replyToId': notification['replyToMessage']?['messageId'],
                'replyToMessage': notification['replyToMessage'],
                'sender': sender ?? {'employeeID': senderId ?? 'unknown', 'fullName': 'Unknown User'},
              });
              _sortMessagesByTime();
              _scrollToBottom();
            }
          });
        }
      } catch (e) {
        print('❌ Error handling newDirectMessageNotification: $e');
      }
    });

    _socketListenersSetup = true;

    // Subscribe ถ้ามี user ID แล้ว
    if (currentUserId != null) {
      _subscribeToDirectMessages();
    }
  }

  /// ลบ socket listeners
  void _removeSocketListeners() {
    if (widget.apiService.socket == null) return;
    
    print('🧹 Removing Socket Listeners');
    widget.apiService.socket?.off('newDirectMessage');
    widget.apiService.socket?.off('directMessageSent');
    widget.apiService.socket?.off('directMessagesRead');
    widget.apiService.socket?.off('connect');
    widget.apiService.socket?.off('disconnect');
    widget.apiService.socket?.off('connect_error');
    widget.apiService.socket?.off('directMessageDeleted');
    widget.apiService.socket?.off('newDirectMessageNotification');
    _socketListenersSetup = false;
  }

  /// แก้ไข: ปรับปรุงการ subscribe
  Future<void> _subscribeToDirectMessages() async {
    if (currentUserId == null) {
      print('❌ Cannot subscribe: currentUserId is null');
      return;
    }

    if (widget.apiService.socket?.connected != true) {
      print('❌ Cannot subscribe: Socket not connected');
      if (mounted) {
        setState(() {
          isConnecting = true;
        });
      }
      return;
    }

    try {
      final subscriptionData = {
        'senderId': currentUserId,
        'recipientId': widget.recipientId,
        'conversationId': '${currentUserId}_${widget.recipientId}',
      };
      
      print('📡 Subscribing: $subscriptionData');
      widget.apiService.socket?.emit('subscribeDirectMessages', subscriptionData);
      
      // Listen for confirmation
      widget.apiService.socket?.once('directMessagesSubscribed', (data) {
        print('✅ Subscription confirmed');
        if (mounted) {
          setState(() {
            isConnected = true;
            isConnecting = false;
          });
        }
      });

    } catch (e) {
      print('❌ Error subscribing: $e');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
        });
      }
    }
  }

  /// แก้ไข: ปรับปรุงการจัดการข้อความใหม่
  void _handleNewDirectMessage(dynamic data) {
    if (!mounted || data is! Map) return;
    try {
      final messageData = Map<String, dynamic>.from(data);
      final sender = messageData['sender'] as Map?;
      final senderId = sender?['employeeID']?.toString();
      final recipientId = messageData['recipientId']?.toString();
      final messageId = messageData['_id']?.toString();
      final message = messageData['message']?.toString() ?? '';

      // จัดการ reply message
      if (messageData['replyToMessage'] != null) {
        final replyData = messageData['replyToMessage'];
        final replySender = replyData['sender'] as Map?;
        final hasReplyContent =
          (replySender != null && (replySender['fullName']?.toString().trim().isNotEmpty ?? false)) ||
          (replyData['message']?.toString().trim().isNotEmpty ?? false);

        final isReply = hasReplyContent;
      }

      if (!_isMessageForThisConversation(senderId, recipientId)) return;

      setState(() {
        _removeTempMessage(senderId, message);
        final exists = messages.any((m) => m['_id'] == messageId);
        if (!exists) {
          final safeMessage = _createSafeMessage(messageData);
          messages.add(safeMessage);
          _sortMessagesByTime();
        }
      });
      _scrollToBottom();
    } catch (e) {
      print('❌ Error handling new message: $e');
    }
  }

  /// จัดการการยืนยันการส่งข้อความ
  void _handleDirectMessageSent(dynamic data) {
    if (!mounted || data is! Map) return;

    try {
      final messageData = Map<String, dynamic>.from(data);
      final senderId = messageData['sender']?['employeeID']?.toString();
      final messageId = messageData['_id']?.toString();
      final message = messageData['message']?.toString() ?? '';

      // ตรวจสอบว่าเป็นข้อความที่เราส่งหรือไม่
      if (senderId != currentUserId) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          // ลบข้อความชั่วคราว
          _removeTempMessage(senderId, message);

          // หาและอัพเดตข้อความ
          final index = messages.indexWhere((m) => m['_id'] == messageId);
          if (index != -1) {
            messages[index] = {
              ...messages[index],
              ...messageData,
              'isSending': false,
            };
          } else {
            // เพิ่มข้อความใหม่ถ้าไม่เจอ
            final safeMessage = _createSafeMessage(messageData);
            messages.add(safeMessage);
            _sortMessagesByTime();
          }
        });
      });

    } catch (e) {
      print('❌ Error handling message sent: $e');
    }
  }

  /// จัดการสถานะอ่านแล้ว
  void _handleMessagesRead(dynamic data) {
    if (!mounted || data is! Map) return;

    try {
      final messageIds = List<String>.from(data['messageIds'] ?? []);
      if (messageIds.isEmpty) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          for (int i = 0; i < messages.length; i++) {
            if (messageIds.contains(messages[i]['_id'])) {
              messages[i] = Map<String, dynamic>.from(messages[i])
                ..['isRead'] = true;
            }
          }
        });
      });

    } catch (e) {
      print('❌ Error handling messages read: $e');
    }
  }

  /// ตรวจสอบว่าข้อความเป็นสำหรับ conversation นี้หรือไม่
  bool _isMessageForThisConversation(String? senderId, String? recipientId) {
    if (currentUserId == null || senderId == null) return false;
    
    // กรณี 1: เราส่งให้ recipient
    final sentByUs = (senderId == currentUserId && recipientId == widget.recipientId);
    
    // กรณี 2: recipient ส่งให้เรา
    final sentToUs = (senderId == widget.recipientId && recipientId == currentUserId);
    
    return sentByUs || sentToUs;
  }

  /// ลบข้อความชั่วคราวที่ตรงกัน
  void _removeTempMessage(String? senderId, String message) {
    messages.removeWhere((m) =>
      m['isSending'] == true &&
      m['sender']?['employeeID'] == senderId &&
      m['message'] == message
    );
  }

  /// แก้ไข: สร้างข้อความที่ปลอดภัย
  Map<String, dynamic> _createSafeMessage(Map<String, dynamic> messageData) {
    final sender = messageData['sender'] as Map?;
    final timestamp = messageData['isoString'] ??
        messageData['timestamp'] ??
        messageData['createdAt'] ??
        DateTime.now().toIso8601String();

    // Handle reply message structure
    Map<String, dynamic>? replyToMessage;
    bool isReply = false;
    if (messageData['replyToMessage'] != null) {
      final replyData = messageData['replyToMessage'];
      final replySender = replyData['sender'] as Map?;
      final hasReplyContent =
          (replySender != null && (replySender['fullName']?.toString().trim().isNotEmpty ?? false)) ||
          (replyData['message']?.toString().trim().isNotEmpty ?? false);

      if (hasReplyContent) {
        isReply = true;
        replyToMessage = {
          '_id': replyData['messageId'] ?? replyData['_id'],
          'message': replyData['message'] ?? '',
          'timestamp': replyData['createdAt'] ?? timestamp,
          'isImage': replyData['isImage'] ?? false,
          'imageUrl': replyData['imageUrl'],
          'isFile': replyData['isFile'] ?? false,
          'fileName': replyData['fileName'],
          'fileType': replyData['fileType'],
          'fileUrl': replyData['fileUrl'],
          'sender': replySender != null
              ? {
                  'employeeID': replySender['employeeID']?.toString() ?? 'unknown',
                  'fullName': replySender['fullName']?.toString() ?? 'Unknown User',
                  'department': replySender['department']?.toString() ?? '',
                  'imgUrl': replySender['imgUrl'],
                }
              : {
                  'employeeID': replyData['sender']?.toString() ?? 'unknown',
                  'fullName': 'Unknown User',
                  'department': '',
                  'imgUrl': null,
                },
        };
      }
    }

    return {
      '_id': messageData['_id']?.toString() ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'message': messageData['message'] ?? '',
      'timestamp': timestamp,
      'isoString': timestamp,
      'isRead': messageData['isRead'] ?? false,
      'isSending': false,
      'isImage': messageData['isImage'] ?? false,
      'imageUrl': messageData['imageUrl'],
      'isFile': messageData['isFile'] ?? false,
      'fileName': messageData['fileName'],
      'fileType': messageData['fileType'],
      'fileUrl': messageData['fileUrl'],
      'isReply': isReply,
      'replyToId': isReply ? (messageData['replyTo'] ?? messageData['replyToMessage']?['messageId']) : null,
      'replyToMessage': isReply ? replyToMessage : null,
      'sender': {
        'employeeID': sender?['employeeID']?.toString() ?? 'unknown',
        'fullName': sender?['fullName']?.toString() ?? 'Unknown User',
        'department': sender?['department']?.toString() ?? '',
        'imgUrl': sender?['imgUrl'],
      },
    };
  }

  /// เรียงลำดับข้อความตามเวลา
  void _sortMessagesByTime() {
    messages.sort((a, b) {
      final aTime = DateTime.parse(a['timestamp'] ?? DateTime.now().toIso8601String());
      final bTime = DateTime.parse(b['timestamp'] ?? DateTime.now().toIso8601String());
      return aTime.compareTo(bTime);
    });
  }

  /// แก้ไข: โหลดข้อความจาก API
  Future<void> _loadMessages() async {
    if (currentUserId == null) return;

    try {
      final url = Uri.parse('${ApiService.baseUrl}/api/direct-messages/conversation/${widget.recipientId}')
          .replace(queryParameters: {
        'employeeId': currentUserId,
        'page': '1',
        'limit': '50',
      });

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] && mounted) {
          final List<dynamic> messagesData = data['data'] ?? [];

          setState(() {
            messages = messagesData.map((msg) {
              return _createSafeMessage(Map<String, dynamic>.from(msg));
            }).toList();
            
            _sortMessagesByTime();
            isLoading = false;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToBottom();
          });
        } else {
          if (mounted) {
            setState(() {
              messages = [];
              isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            messages = [];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading messages: $e');
      if (mounted) {
        setState(() {
          messages = [];
          isLoading = false;
        });
      }
    }
  }

  /// แก้ไข: ปรับปรุงการ scroll ไปด้านล่าง
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// แก้ไข: ปรับปรุงการส่งข้อความ
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || currentUserId == null || isSending) {
      return;
    }

    final messageText = _messageController.text.trim();
    setState(() => isSending = true);

    try {
      // สร้างข้อความชั่วคราว
      final tempMessage = _createTempMessage(messageText);

      setState(() {
        messages.add(tempMessage);
        _sortMessagesByTime();
        _messageController.clear();
      });

      _scrollToBottom();

      // ส่งข้อความผ่าน API
      final response = await widget.apiService.sendDirectMessage(
        recipientId: widget.recipientId,
        message: messageText,
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null 
            ? _createReplyToMessage(_replyingToMessage!) 
            : null,
      );

      if (response['success'] == true) {
        setState(() {
          // ลบ temp message ออก
          messages.removeWhere((m) =>
            m['isSending'] == true &&
            m['message'] == messageText &&
            m['sender']?['employeeID'] == currentUserId
          );
          _clearReply();
        });
      } else {
        throw Exception(response['message'] ?? 'ไม่สามารถส่งข้อความได้');
      }

    } catch (e) {
      print('❌ Error sending message: $e');
      // ลบข้อความชั่วคราวเมื่อเกิดข้อผิดพลาด
      if (mounted) {
        setState(() {
          messages.removeWhere((m) => 
            m['isSending'] == true && 
            m['message'] == messageText &&
            m['sender']?['employeeID'] == currentUserId
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถส่งข้อความได้: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  /// สร้างข้อความชั่วคราว
  Map<String, dynamic> _createTempMessage(String messageText) {
    bool hasReply = false;
    Map<String, dynamic>? replyToMessage;
    String? replyToId;

    if (_replyingToMessage != null) {
      final sender = _replyingToMessage!['sender'];
      final hasSender = sender != null && (sender['fullName']?.toString().trim().isNotEmpty ?? false);
      final hasMsg = _replyingToMessage!['message']?.toString().trim().isNotEmpty ?? false;
      hasReply = hasSender || hasMsg;
      if (hasReply) {
        replyToId = _replyingToMessage!['_id'];
        replyToMessage = _createReplyToMessage(_replyingToMessage!);
      }
    }

    return {
      '_id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'message': messageText,
      'timestamp': DateTime.now().toIso8601String(),
      'isoString': DateTime.now().toIso8601String(),
      'isRead': false,
      'isSending': true,
      'isImage': false,
      'isFile': false,
      'isReply': hasReply,
      'replyToId': hasReply ? replyToId : null,
      'replyToMessage': hasReply ? replyToMessage : null,
      'sender': {
        'employeeID': currentUserId,
        'fullName': 'You',
        'department': '',
        'imgUrl': null,
      },
    };
  }

  /// สร้าง replyToMessage object
  Map<String, dynamic> _createReplyToMessage(Map<String, dynamic> replyTo) {
    final sender = replyTo['sender'];
    final imageUrl = replyTo['imageUrl'];
    final fileUrl = replyTo['fileUrl'];

    return {
      'messageId': replyTo['_id'],
      'message': replyTo['message'] ?? '',
      'sender': {
        'employeeID': sender?['employeeID']?.toString() ?? 'unknown',
        'fullName': sender?['fullName']?.toString() ?? 'Unknown User',
        'department': sender?['department']?.toString() ?? '',
        'imgUrl': sender?['imgUrl'],
      },
      'isImage': replyTo['isImage'] ?? false,
      'imageUrl': imageUrl != null 
          ? (imageUrl.toString().startsWith('http') 
              ? imageUrl 
              : '${ApiService.baseUrl}/${imageUrl.toString().startsWith('/') ? imageUrl.toString().substring(1) : imageUrl}')
          : null,
      'isFile': replyTo['isFile'] ?? false,
      'fileName': replyTo['fileName'],
      'fileType': replyTo['fileType'],
      'fileUrl': fileUrl != null
          ? (fileUrl.toString().startsWith('http')
              ? fileUrl
              : '${ApiService.baseUrl}/${fileUrl.toString().startsWith('/') ? fileUrl.toString().substring(1) : fileUrl}')
          : null,
      'timestamp': replyTo['timestamp'] ?? replyTo['isoString'] ?? DateTime.now().toIso8601String(),
    };
  }

  /// ส่งไฟล์
  Future<void> _sendFile() async {
    if (_selectedFile == null || currentUserId == null) return;

    setState(() => isSending = true);

    try {
      // สร้างข้อความชั่วคราว
      final tempMessage = _createTempFileMessage();

      setState(() {
        messages.add(tempMessage);
        _sortMessagesByTime();
      });

      _scrollToBottom();

      // อัพโหลดไฟล์
      final response = await widget.apiService.uploadDirectMessageFile(
        _selectedFile!,
        widget.recipientId,
        currentUserId!,
        message: _messageController.text.trim().isNotEmpty 
            ? _messageController.text.trim() 
            : null,
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null 
            ? _createReplyToMessage(_replyingToMessage!) 
            : null,
      );

      // อัพเดตข้อความชั่วคราว
      if (mounted) {
        setState(() {
          final index = messages.indexWhere((m) => m['isSending'] == true);
          if (index != -1) {
            messages[index] = {
              ...messages[index],
              '_id': response['_id'],
              'sender': response['sender'],
              'timestamp': response['timestamp'],
              'isRead': response['isRead'] ?? false,
              'isSending': false,
              'fileUrl': response['fileUrl'],
              'fileName': response['fileName'],
              'fileType': response['fileType'],
            };
            
            if (response['message'] != null) {
              messages[index]['message'] = response['message'];
            }
          }
          
          _selectedFile = null;
          _clearReply();
        });
        
        _messageController.clear();
      }

    } catch (e) {
      print('❌ Error sending file: $e');
      
      String errorMessage = 'ไม่สามารถส่งไฟล์ได้';
      if (e.toString().contains('File type not allowed')) {
        errorMessage = 'กรุณาเลือกไฟล์ PDF, Word หรือ Excel เท่านั้น';
      } else if (e.toString().contains('File too large')) {
        errorMessage = 'ขนาดไฟล์ต้องไม่เกิน 5MB';
      }

      if (mounted) {
        setState(() {
          messages.removeWhere((m) => m['isSending'] == true);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  /// สร้างข้อความชั่วคราวสำหรับไฟล์
  Map<String, dynamic> _createTempFileMessage() {
    return {
      '_id': 'temp_file_${DateTime.now().millisecondsSinceEpoch}',
      'message': _messageController.text.trim().isNotEmpty 
          ? _messageController.text.trim() 
          : '',
      'timestamp': DateTime.now().toIso8601String(),
      'isoString': DateTime.now().toIso8601String(),
      'isRead': false,
      'isSending': true,
      'isFile': true,
      'fileName': _selectedFile!.name,
      'fileType': _selectedFile!.extension,
      'isReply': _replyingToMessage != null,
      'replyToId': _replyingToMessage?['_id'],
      'replyToMessage': _replyingToMessage != null 
          ? _createReplyToMessage(_replyingToMessage!) 
          : null,
      'sender': {
        'employeeID': currentUserId,
        'fullName': 'You',
        'department': '',
        'imgUrl': null,
      },
    };
  }

  /// สร้างข้อความชั่วคราวสำหรับรูปภาพ
  Map<String, dynamic> _createTempImageMessage() {
    return {
      '_id': 'temp_img_${DateTime.now().millisecondsSinceEpoch}',
      'message': _messageController.text.trim().isNotEmpty 
          ? _messageController.text.trim() 
          : '',
      'timestamp': DateTime.now().toIso8601String(),
      'isoString': DateTime.now().toIso8601String(),
      'isRead': false,
      'isSending': true,
      'isImage': true,
      'imageUrl': null,
      'isReply': _replyingToMessage != null,
      'replyToId': _replyingToMessage?['_id'],
      'replyToMessage': _replyingToMessage != null 
          ? _createReplyToMessage(_replyingToMessage!) 
          : null,
      'sender': {
        'employeeID': currentUserId,
        'fullName': 'You',
        'department': '',
        'imgUrl': null,
      },
    };
  }

  /// ส่งรูปภาพ
  Future<void> _sendImage() async {
    if (_selectedImage == null || currentUserId == null || isSending) return;
    
    setState(() => isSending = true);
    try {
      // สร้างข้อความชั่วคราว
      final tempMessage = _createTempImageMessage();
      final tempMessageId = tempMessage['_id'];
      final tempMessageText = tempMessage['message'];

      setState(() {
        messages.add(tempMessage);
        _sortMessagesByTime();
      });
      _scrollToBottom();

      // อัพโหลดรูปภาพ
      final response = await widget.apiService.uploadDirectMessageImage(
        _selectedImage!,
        widget.recipientId,
        currentUserId!,
        message: tempMessageText.isNotEmpty ? tempMessageText : null,
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null 
            ? _createReplyToMessage(_replyingToMessage!) 
            : null,
      );

      print('📸 Image upload response: $response');

      // ถ้า response เป็น null หรือไม่มี _id (ซึ่งควรจะมีถ้าส่งสำเร็จ) ให้โยน error
      if (response == null || response['_id'] == null) {
        throw Exception('ไม่สามารถส่งรูปภาพได้');
      }

      // ถ้าส่งสำเร็จ ให้ลบข้อความชั่วคราว
      setState(() {
        messages.removeWhere((m) =>
          m['isSending'] == true &&
          m['_id'] == tempMessageId &&
          m['sender']?['employeeID'] == currentUserId
        );
        _selectedImage = null;
        _clearReply();
        _messageController.clear();
      });

    } catch (e) {
      print('❌ Error sending image: $e');
      if (mounted) {
        setState(() {
          // ลบข้อความชั่วคราวเมื่อเกิดข้อผิดพลาด
          messages.removeWhere((m) => 
            m['isSending'] == true && 
            m['sender']?['employeeID'] == currentUserId
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถส่งรูปภาพได้: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  /// ล้างการตอบกลับ
  void _clearReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

  /// ตั้งค่าการตอบกลับข้อความ
  void _replyToMessage(Map<String, dynamic> message) {
    setState(() {
      _replyingToMessage = {
        '_id': message['_id'],
        'message': message['message'] ?? '',
        'sender': message['sender'],
        'isImage': message['isImage'] ?? false,
        'imageUrl': message['imageUrl'],
        'isFile': message['isFile'] ?? false,
        'fileName': message['fileName'],
        'fileType': message['fileType'],
        'fileUrl': message['fileUrl'],
        'timestamp': message['timestamp'] ?? message['isoString'],
      };
    });
    _messageFocusNode.requestFocus();
  }

  /// เปิด URL
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri)) {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      print('❌ Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดไฟล์ได้')),
        );
      }
    }
  }

  /// เลือกรูปภาพ
  Future<void> _pickAndValidateImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      print('❌ Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// เลือกไฟล์
  Future<void> _pickAndValidateFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx'],
        allowMultiple: false,
      );

      if (result != null) {
        final file = result.files.first;
        
        // ตรวจสอบขนาดไฟล์
        if (file.size > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('ขนาดไฟล์ต้องไม่เกิน 5MB'),
                backgroundColor: Colors.red,
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
      print('❌ Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเลือกไฟล์: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// แสดงเมนูข้อความ
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
              leading: Icon(Icons.reply, color: Theme.of(context).primaryColor),
              title: const Text('ตอบกลับ'),
              onTap: () {
                Navigator.pop(context);
                _replyToMessage(message);
              },
            ),
            if (message['message'] != null && message['message'].toString().trim().isNotEmpty)
              ListTile(
                leading: Icon(Icons.copy, color: Colors.grey[700]),
                title: const Text('คัดลอกข้อความ'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message['message']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกข้อความแล้ว')),
                  );
                },
              ),
            if (isCurrentUser)
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red[700]),
                title: Text('ลบ', style: TextStyle(color: Colors.red[700])),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteMessage(message['_id']);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// ตรวจสอบว่าวันเดียวกันหรือไม่
  bool _isSameDay(String? date1, String? date2) {
    if (date1 == null || date2 == null) return false;
    try {
      final d1 = DateTime.parse(date1);
      final d2 = DateTime.parse(date2);
      return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
    } catch (e) {
      return false;
    }
  }

  /// จัดรูปแบบวันที่
  String _formatDateOnly(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) {
        return 'วันนี้';
      } else if (messageDate == today.subtract(const Duration(days: 1))) {
        return 'เมื่อวาน';
      } else {
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (e) {
      return '';
    }
  }

  /// จัดรูปแบบเวลา
  String _formatMessageTime(String? timestamp) {
    if (timestamp == null) return '';
    
    try {
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(messageTime.year, messageTime.month, messageTime.day);

      if (messageDate == today) {
        return DateFormat('HH:mm').format(messageTime);
      } else if (messageDate == today.subtract(const Duration(days: 1))) {
        return 'เมื่อวาน ${DateFormat('HH:mm').format(messageTime)}';
      } else {
        return DateFormat('dd/MM HH:mm').format(messageTime);
      }
    } catch (e) {
      return DateFormat('HH:mm').format(DateTime.now());
    }
  }

  /// จัดรูปแบบขนาดไฟล์
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// รับไอคอนไฟล์
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

  /// รับสีไฟล์
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

  /// สร้าง widget แสดงการตอบกลับ
  Widget _buildReplyWidget(Map<String, dynamic> replyData) {
    final sender = replyData['sender'];
    final senderName = sender is Map
        ? (sender['fullName'] ?? 'Unknown')
        : (sender?.toString() ?? 'Unknown');

    final messageText = replyData['message'] ?? '';
    final isImage = replyData['isImage'] == true;
    final isFile = replyData['isFile'] == true;
    final fileName = replyData['fileName'];
    final fileType = replyData['fileType'];
    final imageUrl = replyData['imageUrl'];

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
          Row(
            children: [
              Text(
                senderName,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isImage || isFile) ...[
                const SizedBox(width: 4),
                Icon(
                  isImage ? Icons.image : _getFileIcon(fileType),
                  size: 12,
                  color: isImage ? Colors.grey[600] : _getFileColor(fileType),
                ),
              ],
            ],
          ),
          const SizedBox(height: 1),
          if (isImage)
            Row(
              children: [
                if (imageUrl != null)
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      image: DecorationImage(
                        image: NetworkImage(
                          imageUrl.toString().startsWith('http')
                              ? imageUrl
                              : '${ApiService.baseUrl}/${imageUrl.toString().startsWith('/') ? imageUrl.toString().substring(1) : imageUrl}'
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    'รูปภาพ${messageText.isNotEmpty ? ': $messageText' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          else if (isFile)
            Row(
              children: [
                Icon(
                  _getFileIcon(fileType),
                  size: 12,
                  color: _getFileColor(fileType),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName ?? 'ไฟล์',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Text(
              messageText,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  /// สร้าง widget แสดงการตอบกลับ
  Widget _buildReplyPreview() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final sender = _replyingToMessage!['sender'];
    final senderName = sender?['fullName'] ?? 'Unknown User';
    final isImage = _replyingToMessage!['isImage'] == true;
    final isFile = _replyingToMessage!['isFile'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'ตอบกลับ $senderName',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _clearReply,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: Colors.grey[600],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (isImage)
                  Row(
                    children: [
                      Icon(Icons.image, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'รูปภาพ',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  )
                else if (isFile)
                  Row(
                    children: [
                      Icon(_getFileIcon(_replyingToMessage!['fileType']), 
                        size: 16, 
                        color: _getFileColor(_replyingToMessage!['fileType'])),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _replyingToMessage!['fileName'] ?? 'ไฟล์',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    _replyingToMessage!['message'] ?? '',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// สร้าง widget แสดงรูปภาพที่เลือก
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
                onPressed: () => setState(() => _selectedImage = null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// สร้าง widget แสดงไฟล์ที่เลือก
  Widget _buildSelectedFilePreview() {
    if (_selectedFile == null) return const SizedBox.shrink();

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
                        _selectedFile!.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        _formatFileSize(_selectedFile!.size),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                onPressed: () => setState(() => _selectedFile = null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// สร้าง widget แสดงข้อความ
  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    final theme = Theme.of(context);

    // เช็ก reply widget ก่อน
    Widget? replyWidget;
    if (message['isReply'] == true && message['replyToMessage'] != null && message['replyToMessage']['sender'] != null) {
      final reply = message['replyToMessage'];
      final hasReplyContent =
        (reply['sender'] != null && (reply['sender']['fullName']?.toString().trim().isNotEmpty ?? false)) ||
        (reply['message']?.toString().trim().isNotEmpty ?? false);

      if (hasReplyContent) {
        replyWidget = GestureDetector(
          onTap: () {
            final repliedMessageIndex = messages.indexWhere(
              (m) => m['_id'] == message['replyToId'],
            );
            if (repliedMessageIndex != -1) {
              _scrollController.animateTo(
                repliedMessageIndex * 100.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: _buildReplyWidget(message['replyToMessage']),
          ),
        );
      }
    }

    return Container(
      margin: EdgeInsets.only(
        left: isMe ? 64 : 0,
        right: isMe ? 0 : 64,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: message['isSending'] == true
            ? Colors.grey[200]
            : isMe
                ? const Color(0xFFC3F69D)
                : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyWidget != null) replyWidget,
          
          // Image
          if (message['isImage'] == true && message['imageUrl'] != null)
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กำลังพัฒนาการดูรูปภาพเต็มหน้าจอ')),
                );
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(
                      message['imageUrl'].toString().startsWith('http') 
                          ? message['imageUrl'] 
                          : '${ApiService.baseUrl}/${message['imageUrl'].toString().startsWith('/') ? message['imageUrl'].toString().substring(1) : message['imageUrl']}'
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          
          // File
          if (message['isFile'] == true && message['fileUrl'] != null)
            GestureDetector(
              onTap: () => _launchUrl(message['fileUrl']),
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
                      _getFileIcon(message['fileType']),
                      color: _getFileColor(message['fileType']),
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message['fileName'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Row(
                            children: [
                              Text(
                                'คลิกเพื่อเปิดไฟล์',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.open_in_new, size: 12, color: Colors.grey[600]),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Text message
          if (message['message'] != null && message['message'].toString().trim().isNotEmpty)
            SelectableText(
              message['message'],
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          
          const SizedBox(height: 4),
          
          // Time and menu button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatMessageTime(message['timestamp']),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showMessageMenu(message, isMe),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            // Avatar
            if (widget.recipientImage != null)
              Hero(
                tag: 'avatar_${widget.recipientId}',
                child: CircleAvatar(
                  backgroundImage: NetworkImage(widget.recipientImage!),
                  radius: 16,
                ),
              )
            else
              Hero(
                tag: 'avatar_${widget.recipientId}',
                child: CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  child: Text(
                    widget.recipientName[0].toUpperCase(),
                    style: TextStyle(color: colorScheme.onPrimary),
                  ),
                  radius: 16,
                ),
              ),
            const SizedBox(width: 8),
            // Name and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipientName,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Text(
                //   isConnected ? 'ออนไลน์' : isConnecting ? 'กำลังเชื่อมต่อ...' : 'ออฟไลน์',
                //   style: theme.textTheme.bodySmall?.copyWith(
                //     color: isConnected 
                //         ? Colors.green 
                //         : isConnecting 
                //             ? Colors.orange 
                //             : Colors.grey,
                //     fontSize: 12,
                //   ),
                // ),
              ],
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
        ),
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
                      ),
                    )
                  : messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ยังไม่มีข้อความ',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'เริ่มต้นการสนทนากับ ${widget.recipientName}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 24 : 16,
                            vertical: isDesktop ? 12 : 8,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            if (index >= messages.length) {
                              return const SizedBox.shrink();
                            }
                            
                            final message = messages[index];
                            final sender = message['sender'];
                            final senderId = sender?['employeeID']?.toString();
                            final isMe = senderId != null && currentUserId != null && senderId == currentUserId;

                            // Date separator
                            Widget? dateSeparator;
                            if (index == 0 || 
                                (index > 0 && !_isSameDay(
                                  message['timestamp'],
                                  messages[index - 1]['timestamp'],
                                ))) {
                              dateSeparator = Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _formatDateOnly(message['timestamp']),
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

                            return Column(
                              children: [
                                if (dateSeparator != null) dateSeparator,
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: isDesktop ? 4 : 2,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: isMe
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      // Avatar for other user only
                                      if (!isMe) ...[
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundImage: sender?['imgUrl'] != null
                                              ? NetworkImage(sender!['imgUrl'])
                                              : null,
                                          backgroundColor: colorScheme.primary,
                                          child: sender?['imgUrl'] == null
                                              ? Text(
                                                  sender?['fullName']?[0].toUpperCase() ?? '?',
                                                  style: TextStyle(
                                                    color: colorScheme.onPrimary,
                                                    fontSize: 14,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      
                                      // Message bubble
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            // Sender name (for others)
                                            if (!isMe)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4,
                                                  bottom: 2,
                                                ),
                                                child: Text(
                                                  sender?['fullName'] ?? 'Unknown',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.black87,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            _buildMessageBubble(message, isMe),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            
            // File previews
            if (_selectedFile != null) _buildSelectedFilePreview(),
            if (_selectedImage != null) _buildSelectedImagePreview(),
            
            // Reply preview
            if (_replyingToMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildReplyPreview(),
              ),
            
            // Input area
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
                  // Image button
                  Container(
                    decoration: BoxDecoration(
                      color: _selectedImage != null
                          ? colorScheme.primary.withOpacity(0.1)
                          : null,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _selectedImage != null ? Icons.image : Icons.photo_outlined,
                        color: _selectedImage != null
                            ? colorScheme.primary
                            : Colors.grey[600],
                        size: 28,
                      ),
                      tooltip: _selectedImage != null ? 'ส่งรูปภาพ' : 'เลือกรูปภาพ',
                      onPressed: _selectedImage != null 
                          ? _sendImage 
                          : _pickAndValidateImage,
                    ),
                  ),
                  const SizedBox(width: 2),
                  
                  // File button
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
                      onPressed: _selectedFile != null 
                          ? _sendFile 
                          : _pickAndValidateFile,
                    ),
                  ),
                  const SizedBox(width: 2),
                  
                  // Text input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: _replyingToMessage != null
                              ? 'พิมพ์ข้อความตอบกลับ...'
                              : 'พิมพ์ข้อความ...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) {
                          if (_messageController.text.trim().isNotEmpty) {
                            _sendMessage();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Send button
                  if (_messageController.text.isNotEmpty ||
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
                            : const Icon(Icons.send_rounded, size: 20),
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
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    if (currentUserId == null) return;
    try {
      final conversationId = '${currentUserId}_${widget.recipientId}';
      await widget.apiService.deleteDirectMessage(messageId, conversationId);
      setState(() {
        messages.removeWhere((m) => m['_id'] == messageId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบข้อความสำเร็จ')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: ${e.toString()}')),
      );
    }
  }
}