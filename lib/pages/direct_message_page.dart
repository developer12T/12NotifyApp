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
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  File? _selectedImage;
  PlatformFile? _selectedFile;
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
    _loadCurrentUserEmployeeId();
    // Setup socket listeners after a short delay to ensure widget is mounted
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _setupSocketListeners();
      }
    });
    _messageController.addListener(() {
      setState(() {}); // Update UI when text changes
    });
    // Add listener to scroll to bottom when messages change
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-subscribe to direct messages when dependencies change
    if (currentUserId != null && _socketListenersSetup) {
      _subscribeToDirectMessages();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _removeSocketListeners();
    super.dispose();
  }

  Future<void> _loadCurrentUserEmployeeId() async {
    print('\n=== Loading User ID ===');
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      final userData = jsonDecode(userJson);
      final employeeId = userData['employeeID']?.toString();
      print('User ID loaded successfully: $employeeId');

      if (employeeId != null) {
        setState(() {
          currentUserId = employeeId;
        });
        
        // Load messages and subscribe only after currentUserId is set
        await _loadMessages();
        if (_socketListenersSetup) {
          _subscribeToDirectMessages();
        }
      }
    } else {
      print('No user data found in SharedPreferences');
    }
  }

  void _setupSocketListeners() {
    if (_socketListenersSetup || widget.apiService.socket == null) {
      print('Socket listeners already setup or socket is null');
      return;
    }

    print('\n=== Setting up Socket Listeners ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');
    print('Current User ID: $currentUserId');
    print('Recipient ID: ${widget.recipientId}');

    // Remove any existing listeners first
    _removeSocketListeners();

    // Listen for socket connection status
    widget.apiService.socket?.on('connect', (_) {
      print('\n=== Socket Connected ===');
      print('Socket ID: ${widget.apiService.socket?.id}');
      print('Current User ID: $currentUserId');
      if (currentUserId != null) {
        _subscribeToDirectMessages();
      }
      setState(() {
        isConnected = true;
        isConnecting = false;
      });
    });

    widget.apiService.socket?.on('disconnect', (_) {
      print('\n=== Socket Disconnected ===');
      setState(() {
        isConnected = false;
        isConnecting = false;
        _socketListenersSetup = false;
      });
    });

    widget.apiService.socket?.on('connect_error', (error) {
      print('\n=== Socket Connection Error ===');
      print('Error: $error');
      setState(() {
        isConnected = false;
        isConnecting = false;
        _socketListenersSetup = false;
      });
    });

    // Listen for new direct messages
    widget.apiService.socket?.on('newDirectMessage', (data) {
      print('\n=== New Direct Message Received ===');
      print('Socket ID: ${widget.apiService.socket?.id}');
      print('Current User ID: $currentUserId');
      print('Recipient ID: ${widget.recipientId}');
      print('Raw Message Data: $data');

      if (data is Map && mounted) {
        final messageData = Map<String, dynamic>.from(data);
        if (messageData['_id'] == null || messageData['sender'] == null) {
          print('Invalid message data: missing required fields');
          return;
        }
        final sender = messageData['sender'];
        final senderId = sender?['employeeID']?.toString();
        final messageId = messageData['_id']?.toString();
        final message = messageData['message']?.toString();
        final timestamp = messageData['isoString'] ?? messageData['timestamp'] ?? DateTime.now().toIso8601String();

        final isForThisConversation = (senderId == currentUserId && widget.recipientId == widget.recipientId) ||
            (senderId == widget.recipientId && currentUserId == widget.recipientId);

        if (isForThisConversation) {
          print('Processing message for this conversation');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              print('Before remove temp: ${messages.where((m) => m['isSending'] == true && m['sender']?['employeeID'] == currentUserId && m['message'] == message).toList()}');
              messages.removeWhere((m) =>
                m['isSending'] == true &&
                m['sender']?['employeeID'] == currentUserId &&
                m['message'] == message
              );
              print('After remove temp: ${messages.where((m) => m['isSending'] == true && m['sender']?['employeeID'] == currentUserId && m['message'] == message).toList()}');
              int existingMessageIndex = messages.indexWhere((m) => m['_id'] == messageId);
              if (existingMessageIndex == -1) {
                existingMessageIndex = messages.indexWhere((m) => 
                  m['isSending'] == true && 
                  m['sender']?['employeeID'] == currentUserId &&
                  m['message'] == message
                );
              }
              if (existingMessageIndex != -1) {
                final existingMessage = messages[existingMessageIndex];
                final updatedMessage = Map<String, dynamic>.from({
                  ...existingMessage,
                  ...messageData,
                  'isSending': false,
                  'isoString': timestamp,
                  'timestamp': timestamp,
                  'message': message ?? existingMessage['message'],
                  'sender': sender ?? existingMessage['sender'],
                  'replyTo': messageData['replyTo'],
                  'replyToMessage': messageData['replyToMessage'],
                });
                messages[existingMessageIndex] = updatedMessage;
              } else {
                final safeData = Map<String, dynamic>.from({
                  ...messageData,
                  'isSending': false,
                  'isRead': messageData['isRead'] ?? false,
                  'isoString': timestamp,
                  'timestamp': timestamp,
                  'sender': {
                    'employeeID': sender?['employeeID'] ?? 'unknown',
                    'fullName': sender?['fullName'] ?? 'Unknown User',
                    'department': sender?['department'] ?? '',
                    'imgUrl': sender?['imgUrl'],
                  },
                });
                messages.add(safeData);
              }
              messages.sort((a, b) {
                final aTime = DateTime.parse(a['isoString'] ?? a['timestamp'] ?? DateTime.now().toIso8601String());
                final bTime = DateTime.parse(b['isoString'] ?? b['timestamp'] ?? DateTime.now().toIso8601String());
                return aTime.compareTo(bTime);
              });
            });
            _scrollToBottom();
            if (senderId == widget.recipientId && messageId != null) {
              print('Marking message as read');
              widget.apiService.markDirectMessagesAsRead(
                [messageId],
                currentUserId!,
              );
            }
          });
        } else {
          print('Message is not for this conversation, ignoring');
        }
      } else {
        print('Invalid message data or widget not mounted');
      }
    });

    // Listen for message notifications
    widget.apiService.socket?.on('newDirectMessageNotification', (data) {
      print('\n=== New Direct Message Notification ===');
      print('Notification Data: $data');
      
      if (data is Map && mounted) {
        final notificationData = Map<String, dynamic>.from(data);
        final sender = notificationData['sender'];
        final senderId = sender?['employeeID']?.toString();
        final message = notificationData['message']?.toString();
        final timestamp = notificationData['isoString'] ?? notificationData['timestamp'] ?? DateTime.now().toIso8601String();

        print('Notification details:');
        print('- Sender ID: $senderId');
        print('- Message: $message');
        print('- Timestamp: $timestamp');

        // Check if notification is for this conversation
        final isForThisConversation = (senderId == currentUserId && widget.recipientId == widget.recipientId) ||
            (senderId == widget.recipientId && currentUserId == widget.recipientId);

        if (isForThisConversation) {
          print('Processing notification for this conversation');
          
          // Ensure we're on the main thread
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            
            setState(() {
              // Add notification as a temporary message if it doesn't exist
              final messageExists = messages.any((m) => 
                m['message'] == message && 
                m['sender']?['employeeID'] == senderId &&
                m['timestamp'] == timestamp
              );

              if (!messageExists) {
                print('Adding notification as temporary message');
                final safeData = Map<String, dynamic>.from({
                  '_id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'isSending': false,
                  'isRead': false,
                  'isoString': timestamp,
                  'timestamp': timestamp,
                  'message': message,
                  'sender': {
                    'employeeID': sender?['employeeID'] ?? 'unknown',
                    'fullName': sender?['fullName'] ?? 'Unknown User',
                    'department': sender?['department'] ?? '',
                    'imgUrl': sender?['imgUrl'],
                  },
                });
                messages.add(safeData);
                print('Added notification message: $safeData');

                // Sort messages
                messages.sort((a, b) {
                  final aTime = DateTime.parse(a['isoString'] ?? a['timestamp'] ?? DateTime.now().toIso8601String());
                  final bTime = DateTime.parse(b['isoString'] ?? b['timestamp'] ?? DateTime.now().toIso8601String());
                  return aTime.compareTo(bTime);
                });

                // Scroll to bottom
                _scrollToBottom();
              } else {
                print('Message already exists, skipping notification');
              }
            });
          });
        } else {
          print('Notification is not for this conversation, ignoring');
        }
      }
    });

    // Listen for message sent confirmation
    widget.apiService.socket?.on('directMessageSent', (data) {
      print('\n=== Direct Message Sent Confirmation ===');
      print('Raw Data: $data');

      if (data is Map && mounted) {
        final messageData = Map<String, dynamic>.from(data);
        final messageId = messageData['_id']?.toString();
        final senderId = messageData['sender']?['employeeID']?.toString();
        final message = messageData['message']?.toString();
        final timestamp = messageData['isoString'] ?? messageData['timestamp'] ?? DateTime.now().toIso8601String();

        print('Message ID: $messageId');
        print('Sender ID: $senderId');
        print('Message: $message');
        print('Timestamp: $timestamp');

        if (senderId == currentUserId) {
          print('Processing sent message confirmation');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              print('Before remove temp (sent): ${messages.where((m) => m['isSending'] == true && m['sender']?['employeeID'] == currentUserId && m['message'] == message).toList()}');
              messages.removeWhere((m) =>
                m['isSending'] == true &&
                m['sender']?['employeeID'] == currentUserId &&
                m['message'] == message
              );
              print('After remove temp (sent): ${messages.where((m) => m['isSending'] == true && m['sender']?['employeeID'] == currentUserId && m['message'] == message).toList()}');
              int index = messages.indexWhere((m) => m['_id'] == messageId);
              if (index == -1) {
                index = messages.indexWhere((m) => 
                  m['isSending'] == true && 
                  m['sender']?['employeeID'] == currentUserId &&
                  m['message'] == message
                );
              }
              if (index != -1) {
                final existingMessage = messages[index];
                final updatedMessage = Map<String, dynamic>.from({
                  ...existingMessage,
                  ...messageData,
                  'isSending': false,
                  'isoString': timestamp,
                  'timestamp': timestamp,
                  'message': message ?? existingMessage['message'],
                  'sender': messageData['sender'] ?? existingMessage['sender'],
                });
                messages[index] = updatedMessage;
              } else {
                print('Warning: Could not find message to update');
              }
            });
          });
        }
      }
    });

    _socketListenersSetup = true;
    print('Socket listeners setup completed');

    // Subscribe to direct messages if we have user ID
    if (currentUserId != null) {
      print('Current user ID available, subscribing to direct messages');
      _subscribeToDirectMessages();
    } else {
      print('Current user ID not available, cannot subscribe to direct messages');
    }
  }

  void _removeSocketListeners() {
    print('\n=== Removing Socket Listeners ===');
    print('Socket ID: ${widget.apiService.socket?.id}');
    widget.apiService.socket?.off('newDirectMessage');
    widget.apiService.socket?.off('directMessagesRead');
    widget.apiService.socket?.off('directMessageDeleted');
    widget.apiService.socket?.off('connect');
    widget.apiService.socket?.off('disconnect');
    widget.apiService.socket?.off('connect_error');
    widget.apiService.socket?.off('subscribeDirectMessages');
    widget.apiService.socket?.off('directMessagesSubscribed');
    widget.apiService.socket?.off('directMessageSent');
    print('Socket listeners removed');
  }

  Future<void> _subscribeToDirectMessages() async {
    print('\n=== Subscribing to Direct Messages ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');
    print('Current User ID: $currentUserId');
    print('Recipient ID: ${widget.recipientId}');

    if (currentUserId == null) {
      print('❌ Cannot subscribe: Current user ID is null');
      return;
    }

    if (widget.apiService.socket?.connected != true) {
      print('❌ Cannot subscribe: Socket is not connected');
      setState(() {
        isConnecting = true;
      });
      return;
    }

    try {
      // Remove any existing subscription first
      widget.apiService.socket?.off('subscribeDirectMessages');
      widget.apiService.socket?.off('directMessagesSubscribed');

      final subscriptionData = {
        'senderId': currentUserId,
        'recipientId': widget.recipientId,
        'conversationId': '${currentUserId}_${widget.recipientId}',
      };
      print('Emitting subscribeDirectMessages event with data: $subscriptionData');
      
      widget.apiService.socket?.emit('subscribeDirectMessages', subscriptionData);

      // Listen for subscription confirmation
      widget.apiService.socket?.once('directMessagesSubscribed', (data) {
        print('✅ Direct messages subscription confirmed:');
        print('Data: $data');
        if (mounted) {
          setState(() {
            isConnected = true;
            isConnecting = false;
          });
        }
      });

      print('Subscribe request sent successfully');
    } catch (e) {
      print('❌ Error subscribing to direct messages:');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      print('Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          isConnected = false;
          isConnecting = false;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    if (currentUserId == null) {
      print('❌ currentUserId is null, cannot load messages');
      return;
    }
    try {
      print('\n=== Loading Conversation Messages ===');
      print('Recipient ID: ${widget.recipientId}');
      print('Current User ID: $currentUserId');

      final url = Uri.parse(
        '${ApiService.baseUrl}/api/direct-messages/conversation/${widget.recipientId}',
      ).replace(
        queryParameters: {
          'employeeId': currentUserId,
          'page': '1',
          'limit': '50',
        },
      );

      print('Fetching messages from: $url');
      final response = await http.get(url);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final List<dynamic> messagesData = data['data'];
          print('Loaded ${messagesData.length} messages');

          // Sort messages by createdAt in ascending order (oldest first)
          messagesData.sort((a, b) {
            final aTime = DateTime.parse(a['isoString'] ?? a['createdAt'] ?? a['timestamp'] ?? DateTime.now().toIso8601String());
            final bTime = DateTime.parse(b['isoString'] ?? b['createdAt'] ?? b['timestamp'] ?? DateTime.now().toIso8601String());
            return aTime.compareTo(bTime); // เรียงจากเก่าไปใหม่ (เก่าอยู่บน)
          });

          setState(() {
            messages = messagesData.map((msg) {
              // Ensure sender object exists
              if (msg['sender'] == null) {
                msg['sender'] = {
                  'employeeID': msg['sender']?.toString() ?? 'unknown',
                  'fullName': 'Unknown User',
                  'department': '',
                  'imgUrl': null,
                };
              }

              // Ensure timestamp exists
              msg['timestamp'] = msg['createdAt'] ?? DateTime.now().toIso8601String();

              return Map<String, dynamic>.from(msg);
            }).toList();
            isLoading = false;
          });

          print('Messages loaded successfully');
          // Scroll to bottom after messages are loaded
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        } else {
          print('API returned success: false');
          setState(() {
            messages = [];
            isLoading = false;
          });
        }
      } else {
        print('API returned status code: ${response.statusCode}');
        setState(() {
          messages = [];
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        messages = [];
        isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || currentUserId == null) return;
    setState(() => isSending = true);
    try {
      print('\n=== Sending Direct Message ===');
      print('Recipient ID: ${widget.recipientId}');
      print('Current User ID: $currentUserId');
      print('Message: ${_messageController.text.trim()}');
      print('Is Reply: ${_replyingToMessage != null}');
      print('Reply To ID: ${_replyingToMessage?['_id']}');
      
      // Create temporary message
      final tempMessage = {
        '_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'sender': {'employeeID': currentUserId, 'fullName': 'You'},
        'message': _messageController.text.trim(),
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
        'isSending': true,
        'isReply': _replyingToMessage != null,
        'replyToId': _replyingToMessage?['_id'],
        'replyToMessage': _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
                'isFile': _replyingToMessage!['isFile'] ?? false,
                'fileName': _replyingToMessage!['fileName'],
                'fileType': _replyingToMessage!['fileType'],
              }
            : null,
      };

      // Add temporary message to list
      setState(() {
        messages.add(tempMessage);
        messages.sort((a, b) {
          final aTime = DateTime.parse(a['isoString'] ?? a['createdAt'] ?? a['timestamp'] ?? DateTime.now().toIso8601String());
          final bTime = DateTime.parse(b['isoString'] ?? b['createdAt'] ?? b['timestamp'] ?? DateTime.now().toIso8601String());
          return aTime.compareTo(bTime);
        });
      });

      final response = await widget.apiService.sendDirectMessage(
        recipientId: widget.recipientId,
        message: _messageController.text.trim(),
        replyToId: _replyingToMessage?['_id'],
        replyToMessage: _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
                'isFile': _replyingToMessage!['isFile'] ?? false,
                'fileName': _replyingToMessage!['fileName'],
                'fileType': _replyingToMessage!['fileType'],
              }
            : null,
      );
      print('API Response: $response');
      
      if (response == null) {
        throw Exception('No response from server');
      }
      print('response Art: $response');
      if (response['message'] == 'ส่งข้อความสำเร็จ' || response['success'] == true) {
        print('Message sent successfully');
        if (mounted) {
          setState(() {
            _messageController.clear();
            _clearReply();
          });
          // ScaffoldMessenger.of(context).showSnackBar(
          //   const SnackBar(
          //     content: Text('ส่งข้อความสำเร็จ'),
          //     backgroundColor: Colors.green,
          //     duration: Duration(seconds: 2),
          //   ),
          // );
        }
        return;
      }

      throw Exception(response['message'] ?? 'ไม่สามารถส่งข้อความได้');
      
    } catch (e) {
      print('Error sending message: $e');
      print('Stack trace: ${StackTrace.current}');
      if (e.toString() != 'Exception: ส่งข้อความสำเร็จ') {
        setState(() {
          messages.removeWhere((m) => 
            m['isSending'] == true && 
            m['sender']?['employeeID'] == currentUserId &&
            m['message'] == _messageController.text.trim()
          );
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถส่งข้อความได้'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

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
      print('Error picking image: $e');
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
          ),
        );
      }
    }
  }

  void _clearReply() {
    setState(() {
      _replyingToMessage = null;
    });
  }

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
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
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
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    _replyingToMessage!['message'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
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
            ListTile(
              leading: Icon(Icons.copy, color: Colors.grey[700]),
              title: const Text('คัดลอกข้อความ'),
              onTap: () {
                Navigator.pop(context);
                if (message['message'] != null && message['message'].toString().trim().isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: message['message']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกข้อความแล้ว')),
                  );
                }
              },
            ),
            if (isCurrentUser)
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red[700]),
                title: Text('ลบ', style: TextStyle(color: Colors.red[700])),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement message deletion
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('กำลังพัฒนาการลบข้อความ')),
                  );
                },
              ),
          ],
        ),
      ),
    );
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
        'isFile': message['isFile'] ?? false,
        'fileName': message['fileName'],
        'fileType': message['fileType'],
      };
    });
    // Focus the message input field
    _messageFocusNode.requestFocus();
  }

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
                if (replyData['imageUrl'] != null)
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      image: DecorationImage(
                        image: NetworkImage(replyData['imageUrl']),
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
                Expanded(
                  child: Text(
                    fileName ?? 'ไฟล์',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
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
                ? const Color(0xFFE3F2FD)
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Builder(
                builder: (bubbleContext) => Container(
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color.fromARGB(255, 199, 211, 232)
                        : Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.more_horiz, color: Colors.grey[700], size: 20),
                    onPressed: () {
                      _showMessageMenu(message, isMe);
                    },
                    tooltip: 'เมนู',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ],
          ),
          if (message['isReply'] == true && message['replyToMessage'] != null)
            GestureDetector(
              onTap: () {
                // Scroll to replied message
                final repliedMessageIndex = messages.indexWhere(
                  (m) => m['_id'] == message['replyToId'],
                );
                if (repliedMessageIndex != -1) {
                  _scrollController.animateTo(
                    repliedMessageIndex * 100.0, // Approximate height
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: _buildReplyWidget(message['replyToMessage']),
              ),
            ),
          if (message['isImage'] == true && message['imageUrl'] != null)
            GestureDetector(
              onTap: () {
                // TODO: Implement full screen image view
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กำลังพัฒนาการดูรูปภาพเต็มหน้าจอ')),
                );
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(message['imageUrl']),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['fileName'],
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
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
                  ],
                ),
              ),
            ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatMessageTime(message['isoString'] ?? message['createdAt'] ?? message['timestamp']),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  message['isRead'] == true ? Icons.done_all : Icons.done,
                  size: 14,
                  color: message['isRead'] == true ? Colors.blue : Colors.grey[600],
                ),
              ],
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
                Text(
                  isConnected ? 'ออนไลน์' : 'ออฟไลน์',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isConnected ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.more_vert, color: Colors.black87),
          //   onPressed: () {
          //     // TODO: Implement more options menu
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(content: Text('กำลังพัฒนาหน้าเมนูเพิ่มเติม')),
          //     );
          //   },
          // ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
        ),
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.primary,
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

                        // Add date separator if needed
                        Widget? dateSeparator;
                        if (index > 0) {
                          final currentMessage = messages[index];
                          final previousMessage = messages[index - 1];
                          if (!_isSameDay(
                            currentMessage['isoString'] ?? currentMessage['createdAt'] ?? currentMessage['timestamp'],
                            previousMessage['isoString'] ?? previousMessage['createdAt'] ?? previousMessage['timestamp'],
                          )) {
                            dateSeparator = Container(
                              margin: const EdgeInsets.symmetric(vertical: 16),
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
                                    _formatDateOnly(message['isoString'] ?? message['createdAt'] ?? message['timestamp']),
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
                        }

                        return Column(
                          children: [
                            if (dateSeparator != null) dateSeparator,
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: isDesktop ? 6 : 4,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: isMe
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [
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
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: isMe
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              sender?['fullName'] ?? 'Unknown',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        _buildMessageBubble(message, isMe),
                                      ],
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 8),
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
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
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
                        _selectedImage != null ? Icons.image : Icons.photo_outlined,
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
                        _selectedFile != null ? Icons.attach_file : Icons.attach_file_outlined,
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
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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

  String _formatDateOnly(String? timestamp) {
    if (timestamp == null) return '';
    try {
      // Use isoString from API response
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
      print('Error formatting date: $e');
      return '';
    }
  }

  String _formatMessageTime(String timestamp) {
    try {
      // Use isoString from API response
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(
        messageTime.year,
        messageTime.month,
        messageTime.day,
      );

      // ถ้าเป็นวันเดียวกัน แสดงเฉพาะเวลา
      if (messageDate == today) {
        return DateFormat('HH:mm').format(messageTime);
      }
      // ถ้าเป็นเมื่อวาน
      else if (messageDate == today.subtract(const Duration(days: 1))) {
        return 'เมื่อวาน ${DateFormat('HH:mm').format(messageTime)}';
      }
      // ถ้าเป็นวันอื่น ๆ
      else {
        return DateFormat('dd/MM HH:mm').format(messageTime);
      }
    } catch (e) {
      print('Error formatting time: $e');
      return DateFormat('HH:mm').format(DateTime.now());
    }
  }

  bool _isSameDay(String? date1, String? date2) {
    if (date1 == null || date2 == null) return false;
    try {
      final d1 = DateTime.parse(date1);
      final d2 = DateTime.parse(date2);
      return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
    } catch (e) {
      print('Error comparing dates: $e');
      return false;
    }
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเปิดไฟล์ได้')),
        );
      }
    }
  }

  Future<void> _sendImage() async {
    if (_selectedImage == null || currentUserId == null) return;

                          setState(() {
      isSending = true;
    });

    try {
      // Create temporary message
      final tempMessage = {
        '_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'sender': {'employeeID': currentUserId, 'fullName': 'You'},
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
        'isSending': true,
        'isImage': true,
        'imageUrl': null,
        'isReply': _replyingToMessage != null,
        'replyToId': _replyingToMessage?['_id'],
        'replyToMessage': _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
              }
            : null,
      };
      if (_messageController.text.trim().isNotEmpty) {
        tempMessage['message'] = _messageController.text.trim();
      }

      // Add temporary message to end of list
      setState(() {
        messages.add(tempMessage);
      });

      // Upload image with optional message
      final response = await widget.apiService.uploadImage(
        _selectedImage!,
        widget.recipientId,
        currentUserId!,
        message: _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : null,
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

      // Update temporary message with actual data
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
            'isImage': true,
            'imageUrl': response['imageUrl'],
            'isReply': response['isReply'] ?? false,
            'replyToId': response['replyToId'],
            'replyToMessage': response['replyToMessage'],
          };
          if (response['message'] != null &&
              response['message'].toString().trim().isNotEmpty) {
            messages[index]['message'] = response['message'];
          }
        }
      });

      // Reset image selection and reply
      setState(() {
        _selectedImage = null;
        _clearReply();
      });
      _messageController.clear();
    } catch (e) {
      print('Error sending image: $e');
      // Remove temporary message on error
      setState(() {
        messages.removeWhere((m) => m['isSending'] == true);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถส่งรูปภาพได้'),
            backgroundColor: Colors.red,
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

  Future<void> _sendFile() async {
    if (_selectedFile == null || currentUserId == null) return;

    setState(() {
      isSending = true;
    });

    try {
      // Create temporary message
      final tempMessage = {
        '_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'sender': {'employeeID': currentUserId, 'fullName': 'You'},
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
        'isSending': true,
        'isFile': true,
        'fileName': _selectedFile!.name,
        'fileType': _selectedFile!.extension,
        'isReply': _replyingToMessage != null,
        'replyToId': _replyingToMessage?['_id'],
        'replyToMessage': _replyingToMessage != null
            ? {
                'message': _replyingToMessage!['message'],
                'sender': _replyingToMessage!['sender'],
                'isImage': _replyingToMessage!['isImage'] ?? false,
                'imageUrl': _replyingToMessage!['imageUrl'],
              }
            : null,
      };
      if (_messageController.text.trim().isNotEmpty) {
        tempMessage['message'] = _messageController.text.trim();
      }

      // Add temporary message to end of list
      setState(() {
        messages.add(tempMessage);
      });

      // Upload file with optional message
      final response = await widget.apiService.uploadFile(
        _selectedFile!,
        widget.recipientId,
        currentUserId!,
        message: _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : null,
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

      // Update temporary message with actual data
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
            'isFile': true,
            'fileUrl': response['fileUrl'],
            'fileName': response['fileName'],
            'fileType': response['fileType'],
            'isReply': response['isReply'] ?? false,
            'replyToId': response['replyToId'],
            'replyToMessage': response['replyToMessage'],
          };
          if (response['message'] != null &&
              response['message'].toString().trim().isNotEmpty) {
            messages[index]['message'] = response['message'];
          }
        }
      });

      // Reset file selection and reply
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

      // Remove temporary message on error
      setState(() {
        messages.removeWhere((m) => m['isSending'] == true);
      });

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
}
