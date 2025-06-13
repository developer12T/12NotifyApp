import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import 'direct_message_page.dart';
import 'select_user_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class DirectMessageListPage extends StatefulWidget {
  final ApiService apiService;
  final Function(int)? onTotalUnreadCountChanged;
  final Function(String, int)? onNewMessageNotification;

  const DirectMessageListPage({
    super.key, 
    required this.apiService,
    this.onTotalUnreadCountChanged,
    this.onNewMessageNotification,
  });

  @override
  State<DirectMessageListPage> createState() => _DirectMessageListPageState();
}

class _DirectMessageListPageState extends State<DirectMessageListPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> conversations = [];
  String? currentUserId;
  bool isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _socketListenersSetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    loadCurrentUser();
  }

  void _setupSocketListeners() {
    if (_socketListenersSetup) {
      print('Socket listeners already setup, skipping');
      return;
    }

    if (widget.apiService.socket == null) {
      print('Socket is null, waiting for initialization...');
      // Wait a bit and try again
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_socketListenersSetup) {
          _setupSocketListeners();
        }
      });
      return;
    }

    print('\n=== Setting up Direct Message List Socket Listeners ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');
    print('Current User ID: $currentUserId');

    // Remove any existing listeners first
    _removeSocketListeners();

    // Listen for socket connection status
    widget.apiService.socket?.on('connect', (_) {
      print('\n=== Direct Message List Socket Connected ===');
      print('Socket ID: ${widget.apiService.socket?.id}');
      print('Current User ID: $currentUserId');
      
      // Subscribe immediately when connected
      if (currentUserId != null) {
        _subscribeToDirectMessageUpdates();
      }
    });

    widget.apiService.socket?.on('disconnect', (_) {
      print('\n=== Direct Message List Socket Disconnected ===');
      _socketListenersSetup = false;
    });

    widget.apiService.socket?.on('connect_error', (error) {
      print('\n=== Direct Message List Socket Connection Error ===');
      print('Error: $error');
      _socketListenersSetup = false;
    });

    // Listen for direct message room join confirmation
    widget.apiService.socket?.on('directMessageRoomJoined', (data) {
      print('\n=== Direct Message Room Join Confirmation ===');
      print('Data: $data');
      
      if (data is Map && data['success'] == true) {
        print('Successfully joined direct message room: ${data['roomId']}');
        print('Participants: ${data['participants']}');
      } else {
        print('Failed to join direct message room: ${data['error']}');
      }
    });

    // Listen for user joined direct message room notification
    widget.apiService.socket?.on('userJoinedDirectMessage', (data) {
      print('\n=== User Joined Direct Message Room ===');
      print('Data: $data');
      
      if (data is Map && mounted) {
        final roomId = data['roomId']?.toString();
        final userId = data['userId']?.toString();
        final timestamp = data['timestamp'];
        
        print('User $userId joined room $roomId at $timestamp');
        // You can add additional logic here if needed
      }
    });

    // Listen for chat list updates from direct message endpoints
    // This is the main event for updating the conversation list
    widget.apiService.socket?.on('updateChatList', (data) {
      print('\n=== รับ Chat List Update จาก Direct Message ===');
      print('ข้อมูลทั้งหมด: $data');
      print('Current User ID: $currentUserId');
      print('Mounted: $mounted');

      if (!mounted) {
        print('Widget is not mounted, ignoring update');
        return;
      }

      Map<String, dynamic>? updateData;
      
      // Handle different data formats
      if (data is List && data.isNotEmpty) {
        print('Data is a List, length: ${data.length}');
        if (data.first is Map) {
          updateData = Map<String, dynamic>.from(data.first);
        }
      } else if (data is Map) {
        updateData = Map<String, dynamic>.from(data);
      }

      if (updateData != null) {
        print('- Message ID: ${updateData['_id']}');
        print('- Recipient ID: ${updateData['recipientId']}');
        print('- Sender: ${updateData['sender']}');
        print('- Message: ${updateData['message']}');
        print('- Is Read: ${updateData['isRead']}');
        print('- Is Image: ${updateData['isImage']}');
        print('- Is File: ${updateData['isFile']}');

        _handleChatListUpdate(updateData);
      } else {
        print('Received invalid update data format: $data');
      }
    });

    // Listen for messages read updates (for mark as read functionality)
    widget.apiService.socket?.on('directMessagesRead', (data) {
      print('\n=== 👁️ Direct Messages Read Update ===');
      print('📊 Data: $data');
      
      if (data is Map && mounted && currentUserId != null) {
        final conversationId = data['conversationId']?.toString();
        final readerId = data['readerId']?.toString();
        final messageIds = data['messageIds'] as List?;
        
        print('🔍 Conversation ID: $conversationId');
        print('👤 Reader ID: $readerId');
        print('📝 Message IDs: $messageIds');
        
        if (conversationId != null && readerId == currentUserId) {
          // Extract participant ID from conversation ID (format: senderId_recipientId)
          final parts = conversationId.split('_');
          if (parts.length == 2) {
            final participantId = parts[0] == currentUserId ? parts[1] : parts[0];
            print('📱 Updating unread count for participant: $participantId');
            
            // Reset unread count to 0 when messages are marked as read
            _updateConversationUnreadCount(participantId, 0);
          }
        }
      }
    });

    // Listen for new direct message notifications
    widget.apiService.socket?.on('newDirectMessageNotification', (data) {
      print('\n=== New Direct Message Notification ===');
      print('Data: $data');
      print('Current User ID: $currentUserId');
      print('Mounted: $mounted');
      
      if (data is Map && mounted && currentUserId != null) {
        final recipientId = data['recipientId']?.toString();
        final sender = data['sender'];
        
        print('Recipient ID: $recipientId');
        print('Sender: $sender');
        
        // ตรวจสอบว่าเป็นข้อความสำหรับ current user หรือไม่
        if (recipientId == currentUserId && sender != null) {
          final senderId = sender['employeeID']?.toString();
          
          if (senderId != null) {
            print('New message from: $senderId');
            print('Message: ${data['message']}');
            
            // อัปเดต conversation list ด้วยข้อความใหม่
            _handleNewDirectMessageNotification(Map<String, dynamic>.from(data));
            
            // แสดง notification indicator (ถ้าต้องการ)
            _showNotificationIndicator(sender['fullName'] ?? 'Unknown User', data['message'] ?? '');
          }
        }
      }
    });

    _socketListenersSetup = true;
    print('Direct message list socket listeners setup completed');

    // Subscribe if we have user ID and socket is connected
    if (currentUserId != null && widget.apiService.socket?.connected == true) {
      print('Immediately subscribing to direct message updates');
      _subscribeToDirectMessageUpdates();
    } else {
      print('Cannot subscribe immediately: User ID: $currentUserId, Socket connected: ${widget.apiService.socket?.connected}');
    }
  }

  void _removeSocketListeners() {
    print('Removing existing direct message list socket listeners');
    widget.apiService.socket?.off('updateChatList');
    widget.apiService.socket?.off('directMessagesRead');
    widget.apiService.socket?.off('directMessageRoomJoined');
    widget.apiService.socket?.off('userJoinedDirectMessage');
    widget.apiService.socket?.off('newDirectMessageNotification');
    widget.apiService.socket?.off('connect');
    widget.apiService.socket?.off('disconnect');
    widget.apiService.socket?.off('connect_error');
  }

  void _subscribeToDirectMessageUpdates() {
    if (currentUserId != null && widget.apiService.socket?.connected == true) {
      print('\n=== 📡 DEBUG: Subscribing to Direct Message Updates ===');
      print('📍 Called from: ${StackTrace.current.toString().split('\n')[1]}');
      print('⏰ Timestamp: ${DateTime.now().toIso8601String()}');
      print('👤 User ID: $currentUserId');
      print('📡 Socket connected: ${widget.apiService.socket?.connected}');
      print('🆔 Socket ID: ${widget.apiService.socket?.id}');
      print('🔍 Note: This is ONLY subscribing, NOT marking as read');
      
      try {
        // Subscribe to direct message updates for the current user
        // This will allow us to receive updateChatList events
        final subscriptionData = {
          'senderId': currentUserId,
          'recipientId': currentUserId,
        };
        
        print('Subscription data: $subscriptionData');
        
        // Subscribe to general direct message updates for list page
        widget.apiService.socket?.emit('subscribeDirectMessages', subscriptionData);
        
        // Also subscribe to chat list updates
        widget.apiService.socket?.emit('subscribeChatList', {
          'empId': currentUserId
        });
        
        print('✅ Subscribe direct message updates request sent');
        print('🔍 No mark as read operation performed');
        
        // Add a confirmation listener with timeout
        bool subscriptionConfirmed = false;
        widget.apiService.socket?.once('directMessagesSubscribed', (data) {
          print('✅ Direct messages subscription confirmed: $data');
          subscriptionConfirmed = true;
        });
        
        // Wait for confirmation with timeout
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!subscriptionConfirmed) {
            print('⚠️ Direct messages subscription confirmation not received, but continuing...');
          }
        });
        
      } catch (e) {
        print('❌ Error subscribing to direct messages: $e');
        print('Stack trace: ${StackTrace.current}');
        
        // Retry subscription after error
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && currentUserId != null) {
            print('🔄 Retrying subscription after error...');
            _subscribeToDirectMessageUpdates();
          }
        });
      }
    } else {
      print('❌ Cannot subscribe: User ID: $currentUserId, Socket connected: ${widget.apiService.socket?.connected}');
      print('❌ Socket object: ${widget.apiService.socket}');
      
      // Try to reconnect and subscribe again
      if (widget.apiService.socket != null && !widget.apiService.socket!.connected) {
        print('🔄 Attempting to reconnect socket...');
        widget.apiService.socket?.connect();
        
        // Wait a bit and try to subscribe again
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted && currentUserId != null) {
            print('🔄 Retrying subscription after reconnection...');
            _subscribeToDirectMessageUpdates();
          }
        });
      }
    }
  }

  void _handleChatListUpdate(Map<String, dynamic> updateData) {
    if (!mounted || currentUserId == null) return;

    try {
      print('\n=== Handling Chat List Update ===');
      print('Current User ID: $currentUserId');
      print('Update Data: $updateData');

      // ตรวจสอบว่าเป็นข้อความสำหรับ current user หรือไม่
      final recipientId = updateData['recipientId']?.toString();
      if (recipientId != currentUserId) {
        print('Message not for current user, ignoring');
        return;
      }

      final sender = updateData['sender'];
      if (sender == null || sender['employeeID'] == null) {
        print('Invalid sender data, ignoring');
        return;
      }

      final senderId = sender['employeeID'].toString();
      
      // ตรวจสอบว่ามี conversation อยู่แล้วหรือไม่
      final existingIndex = conversations.indexWhere((conv) {
        return conv['participantId'].toString() == senderId;
      });

      setState(() {
        if (existingIndex != -1) {
          // อัพเดท conversation ที่มีอยู่
          final updatedConversation = Map<String, dynamic>.from(conversations[existingIndex]);
          
          // อัพเดท last message
          updatedConversation['lastMessage'] = {
            'message': updateData['message'] ?? '',
            'createdAt': updateData['createdAt'] ?? updateData['timestamp'],
            'sender': sender,
            'isImage': updateData['isImage'] ?? false,
            'isFile': updateData['isFile'] ?? false,
          };

          // เพิ่ม unread count ถ้าไม่ใช่ข้อความของตัวเอง
          if (senderId != currentUserId) {
            updatedConversation['unreadCount'] = (updatedConversation['unreadCount'] ?? 0) + 1;
            
            // Notify about new message
            widget.onNewMessageNotification?.call('direct', updatedConversation['unreadCount']);
          }
          
          // ย้าย conversation ไปไว้ด้านบน
          conversations.removeAt(existingIndex);
          conversations.insert(0, updatedConversation);
          
          print('Updated existing conversation for sender: $senderId');
        } else {
          // สร้าง conversation ใหม่
          final newConversation = {
            'participantId': senderId,
            'participant': {
              'employeeID': sender['employeeID'],
              'fullNameThai': sender['fullNameThai'] ?? sender['fullName'],
              'fullName': sender['fullName'],
              'imgUrl': sender['imgUrl'] ?? sender['profileImage'],
              'department': sender['department'],
            },
            'lastMessage': {
              'message': updateData['message'] ?? '',
              'createdAt': updateData['createdAt'] ?? updateData['timestamp'],
              'sender': sender,
              'isImage': updateData['isImage'] ?? false,
              'isFile': updateData['isFile'] ?? false,
            },
            'unreadCount': senderId != currentUserId ? 1 : 0,
            'participants': [currentUserId, senderId],
          };
          
          conversations.insert(0, newConversation);
          print('Created new conversation for sender: $senderId');
        }
      });
      
      // Update total unread count after modifying conversations
      _updateTotalUnreadCount();

      // Sort conversations
      conversations.sort((a, b) {
        final aTime = a['lastMessage']?['createdAt'];
        final bTime = b['lastMessage']?['createdAt'];
        if (aTime == null || bTime == null) return 0;
        final aDate = aTime is DateTime ? aTime : DateTime.tryParse(aTime.toString());
        final bDate = bTime is DateTime ? bTime : DateTime.tryParse(bTime.toString());
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });
    } catch (e) {
      print('Error handling chat list update: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  void _updateConversationUnreadCount(String participantId, int unreadCount) {
    if (!mounted) return;

    print('🔍 DEBUG: Updating unread count for participant $participantId to $unreadCount');

    setState(() {
      final conversationIndex = conversations.indexWhere((conv) {
        return conv['participantId'].toString() == participantId;
      });

      if (conversationIndex != -1) {
        // Update the unreadCount field directly
        conversations[conversationIndex]['unreadCount'] = unreadCount;
        
        // Also update the lastMessage.isRead status for consistency
        if (conversations[conversationIndex]['lastMessage'] != null) {
          conversations[conversationIndex]['lastMessage']['isRead'] = (unreadCount == 0);
        }
        print('✅ Updated conversation $participantId - unreadCount: $unreadCount, isRead: ${conversations[conversationIndex]['lastMessage']?['isRead']}');
        
        // Update total unread count
        _updateTotalUnreadCount();
      } else {
        print('❌ Conversation not found for participant: $participantId');
      }
    });
  }

  // Method to calculate and update total unread count
  void _updateTotalUnreadCount() {
    final totalUnread = conversations.fold<int>(0, (sum, conversation) {
      return sum + (conversation['unreadCount'] as int? ?? 0);
    });
    
    print('🔍 DEBUG: Total unread count: $totalUnread');
    
    // Notify parent widget about the change
    widget.onTotalUnreadCountChanged?.call(totalUnread);
  }

  /// Handle new direct message notification
  void _handleNewDirectMessageNotification(Map<String, dynamic> messageData) {
    if (!mounted || currentUserId == null) return;

    try {
      print('\n=== Handling New Direct Message Notification ===');
      final sender = messageData['sender'];
      final senderId = sender?['employeeID']?.toString();
      
      if (senderId == null) return;

      // ตรวจสอบว่ามี conversation อยู่แล้วหรือไม่
      final existingIndex = conversations.indexWhere((conv) {
        return conv['participantId'].toString() == senderId;
      });

      setState(() {
        if (existingIndex != -1) {
          // อัพเดท conversation ที่มีอยู่
          final updatedConversation = Map<String, dynamic>.from(conversations[existingIndex]);
          
          // อัพเดท last message
          updatedConversation['lastMessage'] = {
            'message': messageData['message'] ?? '',
            'createdAt': messageData['createdAt'] ?? messageData['isoString'],
            'sender': sender,
            'isImage': messageData['isImage'] ?? false,
            'isFile': messageData['isFile'] ?? false,
          };

          // เพิ่ม unread count
          updatedConversation['unreadCount'] = (updatedConversation['unreadCount'] ?? 0) + 1;
          
          // Notify about new message
          widget.onNewMessageNotification?.call('direct', updatedConversation['unreadCount']);
          
          // ย้าย conversation ไปไว้ด้านบน
          conversations.removeAt(existingIndex);
          conversations.insert(0, updatedConversation);
          
          print('Updated existing conversation for sender: $senderId');
        } else {
          // สร้าง conversation ใหม่
          final newConversation = {
            'participantId': senderId,
            'participant': {
              'employeeID': sender['employeeID'],
              'fullNameThai': sender['fullNameThai'] ?? sender['fullName'],
              'fullName': sender['fullName'],
              'imgUrl': sender['imgUrl'] ?? sender['profileImage'],
              'department': sender['department'],
            },
            'lastMessage': {
              'message': messageData['message'] ?? '',
              'createdAt': messageData['createdAt'] ?? messageData['isoString'],
              'sender': sender,
              'isImage': messageData['isImage'] ?? false,
              'isFile': messageData['isFile'] ?? false,
            },
            'unreadCount': 1,
            'participants': [currentUserId, senderId],
          };
          
          conversations.insert(0, newConversation);
          print('Created new conversation for sender: $senderId');
          
          // Notify about new message for new conversation
          widget.onNewMessageNotification?.call('direct', 1);
        }
      });
      
      // Update total unread count after modifying conversations
      _updateTotalUnreadCount();

      // Sort conversations
      conversations.sort((a, b) {
        final aTime = a['lastMessage']?['createdAt'];
        final bTime = b['lastMessage']?['createdAt'];
        if (aTime == null || bTime == null) return 0;
        final aDate = aTime is DateTime ? aTime : DateTime.tryParse(aTime.toString());
        final bDate = bTime is DateTime ? bTime : DateTime.tryParse(bTime.toString());
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });
    } catch (e) {
      print('Error handling new direct message notification: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  /// Show notification indicator
  void _showNotificationIndicator(String senderName, String message) {
    if (!mounted) return;

    // แสดง SnackBar แจ้งเตือน
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.message, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    senderName+'ส่งข้อความใหม่',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    message.length > 50 ? '${message.substring(0, 50)}...' : message,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue[600],
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-subscribe to direct message updates when page becomes visible
    print('DirectMessageListPage: didChangeDependencies called');
    _refreshSocketSubscriptions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('\n=== App Resumed - Refreshing Direct Messages ===');
      loadCurrentUser();
      if (widget.apiService.socket?.connected != true) {
        widget.apiService.socket?.connect();
      }
      // Refresh subscriptions when app resumes
      _refreshSocketSubscriptions();
    } else if (state == AppLifecycleState.paused) {
      widget.apiService.socket?.disconnect();
    }
  }

  /// Refresh socket subscriptions when returning to the page
  void _refreshSocketSubscriptions() {
    if (currentUserId != null && widget.apiService.socket?.connected == true) {
      print('Refreshing direct message subscriptions');
      
      // Reset the setup flag to force re-setup
      _socketListenersSetup = false;
      
      // Remove existing listeners first
      _removeSocketListeners();
      
      // Add a delay to ensure proper cleanup before resubscribing
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          // Re-setup listeners
          _setupSocketListeners();
          
          // Also use the ApiService method as backup
          widget.apiService.refreshListPageSubscriptions();
          
          print('✅ Direct message subscriptions refreshed');
        }
      });
    } else {
      print('Cannot refresh subscriptions: User ID: $currentUserId, Socket connected: ${widget.apiService.socket?.connected}');
      
      // Try to initialize if not ready
      if (currentUserId == null) {
        print('User ID is null, trying to load current user...');
        loadCurrentUser();
      }
      
      if (widget.apiService.socket?.connected != true) {
        print('Socket not connected, trying to reconnect...');
        widget.apiService.socket?.connect();
        
        // Wait and try to refresh again
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted && currentUserId != null) {
            print('🔄 Retrying subscription after reconnection...');
            _refreshSocketSubscriptions();
          }
        });
      }
    }
  }

  void loadCurrentUser() async {
    final userData = await getCurrentUserFromPrefs();
    if (userData != null) {
      setState(() {
        currentUserId = userData['employeeID']?.toString();
      });
      print('fetchCurrentUser (from prefs): currentUserId = $currentUserId');
      
      // Ensure socket is initialized before setting up listeners
      await widget.apiService.ensureInitialized();
      
      // Setup socket listeners and subscribe
      _setupSocketListeners();
      
      // Also subscribe immediately if socket is already connected
      if (currentUserId != null && widget.apiService.socket?.connected == true) {
        print('Socket already connected, subscribing immediately');
        _subscribeToDirectMessageUpdates();
      }
      
      _loadConversations();
    } else {
      print('fetchCurrentUser: No user data in SharedPreferences');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadConversations() async {
    print('_loadConversations called, currentUserId = $currentUserId');
    if (currentUserId == null) {
      print('Cannot load conversations: currentUserId is null');
      setState(() {
        isLoading = false;
      });
      return;
    }

    print('\n=== Loading Direct Message Conversations ===');
    print('Current User ID: $currentUserId');

    try {
      final url = Uri.parse(
        '${ApiService.baseUrl}/api/direct-messages/conversations',
      ).replace(
        queryParameters: {
          'employeeId': currentUserId,
          'page': '1',
          'limit': '20',
        },
      );

      print('Fetching conversations from: $url');
      final response = await http.get(url);
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      setState(() {
        isLoading = false;
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            conversations = List<Map<String, dynamic>>.from(data['data']);
            print('Loaded ${conversations.length} conversations');
            
            // Update total unread count after loading conversations
            _updateTotalUnreadCount();
            
            // Join direct message rooms for all existing conversations
            _joinAllDirectMessageRooms();

            // Sort conversations
            conversations.sort((a, b) {
              final aTime = a['lastMessage']?['createdAt'];
              final bTime = b['lastMessage']?['createdAt'];
              if (aTime == null || bTime == null) return 0;
              final aDate = aTime is DateTime ? aTime : DateTime.tryParse(aTime.toString());
              final bDate = bTime is DateTime ? bTime : DateTime.tryParse(bTime.toString());
              if (aDate == null || bDate == null) return 0;
              return bDate.compareTo(aDate);
            });
          } else {
            print('API returned success: false');
            conversations = [];
            _updateTotalUnreadCount();
          }
        } else {
          print('API returned status code: ${response.statusCode}');
          conversations = [];
          _updateTotalUnreadCount();
        }
      });

      if (response.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโหลดประวัติการสนทนาได้')),
        );
      }
    } catch (e) {
      print('Error loading conversations: $e');
      setState(() {
        isLoading = false;
        conversations = [];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
        );
      }
    }
  }

  /// Join direct message rooms for all existing conversations
  void _joinAllDirectMessageRooms() {
    if (currentUserId == null || conversations.isEmpty) return;

    print('\n=== Joining All Direct Message Rooms ===');
    print('Total conversations: ${conversations.length}');

    for (final conversation in conversations) {
      final participantId = conversation['participantId']?.toString();
      if (participantId != null && participantId.isNotEmpty) {
        _joinDirectMessageRoom(participantId);
      }
    }
  }

  /// Join a specific direct message room
  void _joinDirectMessageRoom(String participantId) {
    if (currentUserId == null || widget.apiService.socket?.connected != true) {
      print('Cannot join room: User ID or socket not ready');
      return;
    }

    try {
      final conversationId = '${currentUserId}_$participantId';
      final joinData = {
        'senderId': currentUserId,
        'recipientId': participantId,
        'conversationId': conversationId,
      };

      print('Joining direct message room: $conversationId');
      widget.apiService.socket?.emit('joinDirectMessageRoom', joinData);

      // Listen for join confirmation
      widget.apiService.socket?.once('directMessageRoomJoined', (data) {
        if (data is Map && data['success'] == true) {
          print('✅ Successfully joined direct message room: $conversationId');
        } else {
          print('❌ Failed to join direct message room: $conversationId');
        }
      });

    } catch (e) {
      print('❌ Error joining direct message room: $e');
    }
  }

  void _startNewChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => SelectUserPage(
              apiService: widget.apiService,
              currentUserId: currentUserId,
            ),
      ),
    );

    if (result != null && mounted) {
      // If a new conversation was started, join the direct message room
      if (result is Map<String, dynamic> && result['recipientId'] != null) {
        final recipientId = result['recipientId'].toString();
        print('\n=== Starting New Chat with User: $recipientId ===');
        
        // Join the direct message room for the new conversation
        _joinDirectMessageRoom(recipientId);
      }
      
      _loadConversations(); // Reload conversations after starting new chat
    }
  }

  void _openChat(Map<String, dynamic> conversation) async {
    print('\n=== 🚪 DEBUG: Opening Direct Message Chat ===');
    print('📍 Called from: ${StackTrace.current.toString().split('\n')[1]}');
    print('⏰ Timestamp: ${DateTime.now().toIso8601String()}');
    print('👤 Current User ID: $currentUserId');
    print('📱 Conversation: ${conversation['participantId']}');
    print('🔍 Note: This is ONLY opening chat, NOT marking as read');
    
    try {
      // Navigate to chat page
      if (mounted) {
        print('🚀 Navigating to DirectMessagePage...');
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DirectMessagePage(
              recipientId: conversation['participantId'].toString(),
              recipientName:
                  conversation['participant']['fullNameThai'] ??
                  conversation['participant']['fullName'] ??
                  'ไม่ระบุชื่อ',
              recipientImage: conversation['participant']['imgUrl'],
              apiService: widget.apiService,
            ),
          ),
        );
        
        print('🔙 Returned from chat page with result: $result');
        
        // Always refresh conversations when returning from chat to update unread counts
        print('🔄 Refreshing conversations to update unread counts');
        _loadConversations();
      }
    } catch (e) {
      print('❌ Error opening chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถเปิดการสนทนาได้: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.person_add_alt_1, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child:
            isLoading
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'กำลังโหลดข้อมูล...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                )
                : conversations.isEmpty
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ยังไม่มีประวัติการสนทนา',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final participant = conversation['participant'];
                    final lastMessage = conversation['lastMessage'];
                    
                    // Use unreadCount from API response
                    int unreadCount = conversation['unreadCount'] ?? 0;

                    print('🔍 DEBUG: Conversation ${conversation['participantId']} - unreadCount from API: $unreadCount');

                    // เวลาข้อความล่าสุด
                    String lastMsgTime = '';
                    if (lastMessage != null &&
                        lastMessage['createdAt'] != null) {
                      try {
                        // ถ้า createdAt เป็น String รูปแบบ "05/06/2025 21:25"
                        if (lastMessage['createdAt'] is String) {
                          DateTime date = DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).parse(lastMessage['createdAt']);
                          lastMsgTime =
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        }
                        // ถ้า createdAt เป็น DateTime object
                        else if (lastMessage['createdAt'] is DateTime) {
                          DateTime date = lastMessage['createdAt'];
                          lastMsgTime =
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        }
                      } catch (e) {
                        print('Error parsing createdAt: $e');
                        lastMsgTime = '';
                      }
                    }
                    // ชื่อผู้ส่ง
                    String senderName = 'คุณ';
                    if (lastMessage != null && lastMessage['sender'] != null) {
                      if (lastMessage['sender']['employeeID'].toString() !=
                          currentUserId) {
                        senderName = lastMessage['sender']['fullName'] ?? '';
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      child: Material(
                        color: Colors.white,
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap:
                              () => _openChat(
                                conversation,
                              ), // เพิ่ม loading, mark as read ได้
                          child: Container(
                            height: 70,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.blue,
                                  backgroundImage:
                                      participant['imgUrl'] != null
                                          ? NetworkImage(participant['imgUrl'])
                                          : null,
                                  child:
                                      participant['imgUrl'] == null
                                          ? Text(
                                            (participant['fullNameThai'] ??
                                                participant['fullName'] ??
                                                '?')[0],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                          : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              participant['fullNameThai'] ??
                                                  participant['fullName'] ??
                                                  'ไม่ระบุชื่อ',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            lastMsgTime,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        lastMessage != null
                                            ? '$senderName: ${lastMessage['message'] ?? (lastMessage['isImage'] == true
                                                    ? 'รูปภาพ'
                                                    : lastMessage['isFile'] == true
                                                    ? 'ไฟล์'
                                                    : '')}'
                                            : '',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (unreadCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(left: 10),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: unreadCount > 99 ? 6 : 4,
                                      vertical: 2,
                                    ),
                                    constraints: BoxConstraints(
                                      minWidth: unreadCount > 99 ? 24 : 20,
                                      minHeight: 20,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade500,
                                      shape: unreadCount > 99 ? BoxShape.rectangle : BoxShape.circle,
                                      borderRadius: unreadCount > 99 ? BorderRadius.circular(12) : null,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withOpacity(0.2),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'เมื่อวาน';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} วันที่แล้ว';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      return jsonDecode(userJson) as Map<String, dynamic>;
    }
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _removeSocketListeners();
    _socketListenersSetup = false;
    super.dispose();
  }
}
