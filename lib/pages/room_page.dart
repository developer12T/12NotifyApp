import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import 'dart:math' as math;
import 'chat_page.dart';
import 'package:intl/intl.dart';

class ChatRoom {
  final String id;
  final String name;
  final String description;
  final String admin;
  final Map<String, dynamic> lastMessage;
  final int unreadCount;
  final String color;
  final int memberCount;
  final String userRole;
  final String? imageUrl;

  ChatRoom({
    required this.id,
    required this.name,
    required this.description,
    required this.admin,
    required this.lastMessage,
    required this.unreadCount,
    required this.color,
    required this.memberCount,
    required this.userRole,
    this.imageUrl,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      admin: json['admin'] ?? '',
      lastMessage: json['lastMessage'] ?? {'sender': 'ยังไม่มีข้อความ'},
      unreadCount: json['unreadCount'] ?? 0,
      color: json['color'] ?? '#2196F3',
      memberCount: json['memberCount'] ?? 1,
      userRole: json['userRole']?.toString().toLowerCase() ?? 'member',
      imageUrl: json['imageUrl'],
    );
  }

  String get lastMessageText => lastMessage['message'] ?? '';
  
  String lastMessageSender(String? currentUserEmployeeId, String roomName) {
    final sender = lastMessage['sender'];
    print('lastMessageSender: sender = $currentUserEmployeeId');
    if (sender is Map && sender['employeeID'] != null && currentUserEmployeeId != null) {
      if (sender['employeeID'].toString() == currentUserEmployeeId) {
        return 'คุณ';
      }
      return sender['fullName'] ?? roomName;
    } else if (sender is String && sender.isNotEmpty) {
      return sender;
    }
    return roomName;
  }
  
  String get lastMessageTime {
    // ใช้ isoString เท่านั้น เพื่อให้ได้เวลาท้องถิ่นที่ถูกต้อง
    final timeString = lastMessage['isoString'];
    
    if (timeString != null) {
      try {
        // print('Debug - Original timeString: $timeString');
        final messageTime = DateTime.parse(timeString).toLocal();
        // print('Debug - Parsed messageTime (local): $messageTime');
        // print('Debug - messageTime.hour: ${messageTime.hour}');
        // print('Debug - messageTime.minute: ${messageTime.minute}');
        
        final formattedTime = DateFormat('HH:mm').format(messageTime);
        // print('Debug - Formatted time: $formattedTime');
        
        return formattedTime;
      } catch (e) {
        print('Error parsing timestamp: $timeString - $e');
        return '';
      }
    }
    return '';
  }
}

class RoomPage extends StatefulWidget {
  final ApiService apiService;
  final Function(int)? onTotalUnreadCountChanged;
  final Function(int)? onNewMessageNotification;

  const RoomPage({
    super.key, 
    required this.apiService,
    this.onTotalUnreadCountChanged,
    this.onNewMessageNotification,
  });

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  String _userName = '';
  final List<ChatRoom> _chatRooms = [];
  bool _isLoading = true;
    bool _isNavigating = false;
  String? _errorMessage;
  String? _currentUserEmployeeId;
  bool _isDisposed = false;
  bool _isFirstLoad = true;
  bool _socketListenersSetup = false;
  String? _currentChatRoomId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('\n=== App Lifecycle State Changed: $state ===');
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed - refreshing data and reconnecting socket');
        _handleAppResume();
        break;
      case AppLifecycleState.paused:
        print('App paused');
        break;
      case AppLifecycleState.inactive:
        print('App inactive');
        break;
      case AppLifecycleState.detached:
        print('App detached');
        break;
      default:
        break;
    }
  }

  void _handleAppResume() async {
    if (!_isDisposed && mounted) {
      // Reconnect socket if needed
      if (widget.apiService.socket?.connected != true) {
        print('Socket not connected, attempting to reconnect...');
        await widget.apiService.ensureInitialized();
      }
      
      // Refresh data
      _refreshData();
      
      // Ensure socket listeners are setup
      if (!_socketListenersSetup) {
        _setupSocketListeners();
      }
    }
  }

  Future<void> _initializeData() async {
    try {
      await _loadCurrentUserEmployeeId();
      await _loadUserData();
      _setupSocketListeners();
    } catch (e) {
      print('Error initializing data: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isFirstLoad && mounted) {
      _refreshData();
      // Re-subscribe to chat list when page becomes visible with better timing
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_isDisposed) {
          _refreshSocketSubscriptions();
        }
      });
    }
    _isFirstLoad = false;
  }

  /// Refresh socket subscriptions when returning to the page
  void _refreshSocketSubscriptions() {
    if (_currentUserEmployeeId != null && widget.apiService.socket?.connected == true) {
      print('Refreshing chat list subscriptions');
      
      // Use a delay to ensure proper cleanup and subscription restoration
      Future.delayed(const Duration(milliseconds: 300), () {
        if (widget.apiService.socket?.connected == true) {
          widget.apiService.refreshListPageSubscriptions();
        } else {
          print('❌ Socket not connected during refresh, attempting reconnection...');
          widget.apiService.ensureInitialized().then((_) {
            if (widget.apiService.socket?.connected == true) {
              widget.apiService.refreshListPageSubscriptions();
            }
          });
        }
      });
    } else {
      print('Cannot refresh subscriptions: Employee ID: $_currentUserEmployeeId, Socket connected: ${widget.apiService.socket?.connected}');
    }
  }

  /// Handle chat room entry and exit
  void _handleChatRoomEntry(String roomId) {
    print('=== _handleChatRoomEntry called ===');
    print('Room ID: "$roomId"');
    print('Current chat room ID before: "$_currentChatRoomId"');
    
    if (roomId.isEmpty) {
      // User left a chat room
      print('User left chat room: $_currentChatRoomId');
      _currentChatRoomId = null;
      print('Current chat room ID after leaving: "$_currentChatRoomId"');
      
      // Immediately refresh socket subscriptions to ensure notifications work
      if (_currentUserEmployeeId != null && widget.apiService.socket?.connected == true) {
        print('Refreshing subscriptions after leaving chat room');
        
        // Add a small delay to ensure proper cleanup from chat page
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_isDisposed) {
            print('Executing delayed subscription refresh');
            _subscribeToChatList();
            
            // Also refresh all room subscriptions
            _refreshAllRoomSubscriptions();
            
            // Re-setup socket listeners to ensure they work for all rooms
            _setupSocketListeners();
          }
        });
      }
    } else {
      // User entered a chat room
      print('User entered chat room: $roomId');
      _currentChatRoomId = roomId;
      print('Current chat room ID after entering: "$_currentChatRoomId"');
      
      // Ensure socket listeners are set up for all rooms when entering a room
      if (_currentUserEmployeeId != null && widget.apiService.socket?.connected == true) {
        print('Setting up socket listeners after entering chat room');
        _setupSocketListeners();
      }
    }
  }

  /// Refresh all room subscriptions to ensure real-time updates work
  void _refreshAllRoomSubscriptions() {
    print('=== Refreshing All Room Subscriptions ===');
    
    if (_currentUserEmployeeId == null || widget.apiService.socket?.connected != true) {
      print('Cannot refresh subscriptions: User ID or socket not ready');
      return;
    }
    
    try {
      // Re-join all rooms to ensure subscriptions are active
      for (final room in _chatRooms) {
        print('Re-joining room: ${room.id}');
        widget.apiService.socket?.emit('joinRoom', {
          'roomId': room.id,
          'userId': _currentUserEmployeeId
        });
      }
      
      // Also re-subscribe to chat list updates
      widget.apiService.socket?.emit('subscribeChatList', {
        'empId': _currentUserEmployeeId
      });
      
      print('✅ All room subscriptions refreshed');
    } catch (e) {
      print('❌ Error refreshing room subscriptions: $e');
    }
  }

  /// Check if user is in a specific chat room
  bool _isUserInChatRoom(String roomId) {
    print('=== _isUserInChatRoom Check ===');
    print('Checking room ID: "$roomId"');
    print('Current chat room ID: "$_currentChatRoomId"');
    print('Is user in chat room: ${_currentChatRoomId == roomId}');
    return _currentChatRoomId == roomId;
  }

  void _setupSocketListeners() {
    if (widget.apiService.socket == null) {
      print('Socket is null, cannot setup listeners');
      return;
    }

    print('\n=== Setting up Socket Listeners ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');
    print('Current listeners setup: $_socketListenersSetup');

    // Remove any existing listeners first to prevent duplicates
    _removeSocketListeners();

    // Listen for socket connection status
    widget.apiService.socket?.on('connect', (_) {
      print('\n=== Socket Connected ===');
      print('Socket ID: ${widget.apiService.socket?.id}');
      _subscribeToChatList();
    });

    widget.apiService.socket?.on('disconnect', (_) {
      print('\n=== Socket Disconnected ===');
      _socketListenersSetup = false;
    });

    widget.apiService.socket?.on('connect_error', (error) {
      print('\n=== Socket Connection Error ===');
      print('Error: $error');
      _socketListenersSetup = false;
    });

    // Listen for socket errors
    widget.apiService.socket?.on('error', (error) {
      print('\n=== Socket Error ===');
      print('Error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ: ${error['message'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    // Listen for messages read updates
    widget.apiService.socket?.on('messagesRead', (data) {
      print('\n=== Messages Read Update ===');
      print('Data: $data');
      
      if (data is Map && mounted) {
        final roomId = data['roomId']?.toString();
        if (roomId != null) {
          _updateRoomUnreadCount(roomId, 0);
        }
      }
    });

    // Listen for new messages - MAIN FIX HERE
    widget.apiService.socket?.on('newMessage', (data) {
      print('\n=== รับข้อความใหม่ ===');
      print('เป็นข้อความจากบอท: false');
      print('ข้อมูลทั้งหมด: $data');
      print('Data type: ${data.runtimeType}');
      print('Socket connected: ${widget.apiService.socket?.connected}');
      print('Socket ID: ${widget.apiService.socket?.id}');
      print('Current chat room ID: "$_currentChatRoomId"');

      if (!mounted || _isDisposed) {
        print('Widget is not mounted or disposed, ignoring message');
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

        final processedMessage = {
          '_id': message['_id']?.toString(),
          'room': message['room']?.toString(),
          'message': message['message']?.toString(),
          'sender': message['sender'],
          'timestamp': message['timestamp']?.toString(),
          'isRead': message['isRead'] ?? false,
          'isImage': message['isImage'] ?? false,
          'imageUrl': message['imageUrl'],
        };

        print('Processed message:');
        print('- ID: ${processedMessage['_id']}');
        print('- Room: ${processedMessage['room']}');
        print('- Content: ${processedMessage['message']}');
        print('- Sender: ${processedMessage['sender']}');
        print('- Timestamp: ${processedMessage['timestamp']}');
        print('- Is Read: ${processedMessage['isRead']}');

        print('Calling message callback...');
        _handleNewMessage(processedMessage);
        print('Message callback completed');
      } else {
        print('Received invalid message format: $data');
      }
    });

    // Listen for new message notifications
    widget.apiService.socket?.on('newMessageNotification', (data) {
      print('\n=== New Message Notification Received ===');
      print('Data: $data');
      print('Data type: ${data.runtimeType}');
      print('Socket connected: ${widget.apiService.socket?.connected}');
      print('Socket ID: ${widget.apiService.socket?.id}');

      if (!mounted || _isDisposed) {
        print('Widget is not mounted or disposed, ignoring notification');
        return;
      }

      if (data is Map) {
        final roomId = data['roomId']?.toString();
        final roomName = data['roomName']?.toString();
        final message = data['message']?.toString();
        final sender = data['sender'];
        final isImage = data['isImage'] ?? false;
        final timestamp = data['timestamp']?.toString();

        print('Notification details:');
        print('- Room ID: $roomId');
        print('- Room Name: $roomName');
        print('- Message: $message');
        print('- Sender: $sender');
        print('- Is Image: $isImage');
        print('- Timestamp: $timestamp');

        // Check if user is currently in this chat room
        final isInChatRoom = _isUserInChatRoom(roomId ?? '');
        print('Is user in chat room: $isInChatRoom');

        if (!isInChatRoom && roomId != null) {
          // Find the room and get current unread count
          final roomIndex = _chatRooms.indexWhere((room) => room.id == roomId);
          if (roomIndex != -1) {
            final room = _chatRooms[roomIndex];
            final newUnreadCount = room.unreadCount + 1;
            
            print('Current unread count: ${room.unreadCount}');
            print('New unread count: $newUnreadCount');
            
            // Update the room's unread count in the UI
            final updatedRoom = ChatRoom(
              id: room.id,
              name: room.name,
              description: room.description,
              admin: room.admin,
              lastMessage: room.lastMessage,
              unreadCount: newUnreadCount,
              color: room.color,
              memberCount: room.memberCount,
              userRole: room.userRole,
              imageUrl: room.imageUrl,
            );

            setState(() {
              // Update the room in the list
              _chatRooms[roomIndex] = updatedRoom;
              
              // Move updated room to top of list if it has unread messages
              if (newUnreadCount > 0) {
                _chatRooms.removeAt(roomIndex);
                _chatRooms.insert(0, updatedRoom);
              }
            });
            
            // Update total unread count for badge indicator
            _updateTotalUnreadCount();
            
            print('Calling onNewMessageNotification with count: $newUnreadCount');
            print('onNewMessageNotification callback exists: ${widget.onNewMessageNotification != null}');
            
            if (widget.onNewMessageNotification != null) {
              widget.onNewMessageNotification!(newUnreadCount);
              print('onNewMessageNotification called successfully');
            } else {
              print('ERROR: onNewMessageNotification callback is null!');
            }
          } else {
            print('Room not found for notification: $roomId');
          }
        } else {
          print('User is in chat room or room ID is null, skipping notification');
        }
      } else {
        print('Invalid notification data format: $data');
      }
    });

    // Listen for all socket events for debugging
    widget.apiService.socket?.onAny((eventName, data) {
      print('\n=== Socket Event Received ===');
      print('Event name: $eventName');
      print('Event data: $data');
      print('Event data type: ${data.runtimeType}');
    });

    // Listen for chat list updates
    widget.apiService.socket?.on('chatListUpdate', (data) {
      print('\n=== Received Chat List Update ===');
      print('Socket connected: ${widget.apiService.socket?.connected}');
      print('Socket ID: ${widget.apiService.socket?.id}');
      print('Data: $data');
      
      if (data is Map && data['rooms'] is List && mounted) {
        final rooms = (data['rooms'] as List).map((room) => ChatRoom.fromJson(room)).toList();
        print('Processed ${rooms.length} rooms');
        
        setState(() {
          // Do not clear the chat rooms list, update only the rooms that have changed
          for (final updatedRoom in rooms) {
            final existingRoomIndex = _chatRooms.indexWhere((r) => r.id == updatedRoom.id);
            if (existingRoomIndex != -1) {
              _chatRooms[existingRoomIndex] = updatedRoom;
            } else {
              _chatRooms.add(updatedRoom);
            }
          }
          _isLoading = false;
        });
        
        // Update total unread count after modifying rooms
        _updateTotalUnreadCount();
      }
    });

    _socketListenersSetup = true;
    print('✅ Socket listeners setup completed successfully');
    print('Socket listeners setup flag: $_socketListenersSetup');

    // Subscribe to chat list if we have user ID
    if (_currentUserEmployeeId != null) {
      _subscribeToChatList();
    }
  }

  void _removeSocketListeners() {
    print('Removing existing socket listeners');
    widget.apiService.socket?.off('newMessage');
    widget.apiService.socket?.off('newMessageNotification');
    widget.apiService.socket?.off('messagesRead');
    widget.apiService.socket?.off('chatListUpdate');
    widget.apiService.socket?.off('error');
    widget.apiService.socket?.off('connect');
    widget.apiService.socket?.off('disconnect');
    widget.apiService.socket?.off('connect_error');
  }

  void _handleNewMessage(Map<String, dynamic> message) {
    print('\n=== New Message in Room ${message['room']} ===');
    print('Raw message data: $message');
    print('Current room ID: ${message['room']}');
    print('Current chat room ID: "$_currentChatRoomId"');
    
    if (!mounted || _isDisposed) {
      print('Widget is not mounted, skipping message update');
      return;
    }

    // แปลง room ID และลบวงเล็บก้ามปูออก
    final messageRoomId = message['room']?.toString().replaceAll(RegExp(r'[\[\]]'), '');
    if (messageRoomId == null) {
      print('Invalid message room ID');
      return;
    }

    print('\n=== Room ID Comparison Debug ===');
    print('Original Message Room ID: "${message['room']}"');
    print('Cleaned Message Room ID: "$messageRoomId"');
    print('Message Room ID length: ${messageRoomId.length}');
    print('Message Room ID bytes: ${messageRoomId.codeUnits}');
    print('Current Chat Room ID: "$_currentChatRoomId"');
    print('Current Chat Room ID length: ${_currentChatRoomId?.length ?? 0}');
    print('Current Chat Room ID bytes: ${_currentChatRoomId?.codeUnits ?? []}');
    
    print('\nAvailable Rooms:');
    for (int i = 0; i < _chatRooms.length; i++) {
      final room = _chatRooms[i];
      print('Room $i: ID="${room.id}", Name="${room.name}"');
    }

    // Find and update the room
    final roomIndex = _chatRooms.indexWhere((room) {
      final isMatch = room.id == messageRoomId;
      print('Comparing "${room.id}" with "$messageRoomId": $isMatch');
      return isMatch;
    });

    if (roomIndex == -1) {
      print('No matching room found for message room ID: $messageRoomId');
      print('Available room IDs: ${_chatRooms.map((r) => r.id).join(', ')}');
      return;
    }

    final room = _chatRooms[roomIndex];
    print('Found matching room: ${room.id} (${room.name})');
    
    final sender = message['sender'];
    print('Message sender: $sender');
    final isCurrentUser = sender is Map && 
                        sender['employeeID']?.toString() == _currentUserEmployeeId;
    print('Is current user: $isCurrentUser');

    int newUnreadCount = room.unreadCount;
    if (!isCurrentUser) {
      newUnreadCount++;
      print('Incrementing unread count to: $newUnreadCount');
      
      // Check if user is currently in this chat room
      final isInChatRoom = _isUserInChatRoom(messageRoomId);
      print('Is user in chat room: $isInChatRoom');
      
      if (!isInChatRoom) {
        // Only notify if user is not in this chat room
        print('User not in chat room, showing notification');
        print('Calling onNewMessageNotification with count: $newUnreadCount');
        print('onNewMessageNotification callback exists: ${widget.onNewMessageNotification != null}');
        
        if (widget.onNewMessageNotification != null) {
          widget.onNewMessageNotification!(newUnreadCount);
          print('onNewMessageNotification called successfully');
        } else {
          print('ERROR: onNewMessageNotification callback is null!');
        }
      } else {
        print('User is in chat room, skipping notification');
      }
    }

    final newLastMessage = {
      'sender': sender ?? 'ยังไม่มีข้อความ',
      'message': message['message'] ?? '',
      'timestamp': message['timestamp'],
    };
    print('New last message: $newLastMessage');

    final updatedRoom = ChatRoom(
      id: room.id,
      name: room.name,
      description: room.description,
      admin: room.admin,
      lastMessage: newLastMessage,
      unreadCount: newUnreadCount,
      color: room.color,
      memberCount: room.memberCount,
      userRole: room.userRole,
      imageUrl: room.imageUrl,
    );

    setState(() {
      // Update only the specific room without removing others
      _chatRooms[roomIndex] = updatedRoom;
      
      // Move updated room to top of list if it has unread messages
      if (newUnreadCount > 0) {
        _chatRooms.removeAt(roomIndex);
        _chatRooms.insert(0, updatedRoom);
      }
    });
    
    // Update total unread count after modifying rooms
    _updateTotalUnreadCount();
    
    print('Room updated successfully');
  }

  void _updateRoomUnreadCount(String roomId, int unreadCount) {
    if (!mounted) return;

    print('DEBUG: Updating unread count for room $roomId to $unreadCount');

    setState(() {
      final roomIndex = _chatRooms.indexWhere((room) => room.id == roomId);
      if (roomIndex != -1) {
        // Create a new ChatRoom with updated unread count
        final oldRoom = _chatRooms[roomIndex];
        final updatedRoom = ChatRoom(
          id: oldRoom.id,
          name: oldRoom.name,
          description: oldRoom.description,
          admin: oldRoom.admin,
          lastMessage: oldRoom.lastMessage,
          unreadCount: unreadCount,
          color: oldRoom.color,
          memberCount: oldRoom.memberCount,
          userRole: oldRoom.userRole,
          imageUrl: oldRoom.imageUrl,
        );
        _chatRooms[roomIndex] = updatedRoom;
        print('✅ Updated room $roomId - unreadCount: $unreadCount');
        
        // Update total unread count
        _updateTotalUnreadCount();
      } else {
        print('❌ Room not found: $roomId');
      }
    });
  }

  // Method to calculate and update total unread count for rooms
  void _updateTotalUnreadCount() {
    final totalUnread = _chatRooms.fold<int>(0, (sum, room) {
      return sum + room.unreadCount;
    });
    
    print('🔍 DEBUG: Total unread count for rooms: $totalUnread');
    print('🔍 DEBUG: Individual room unread counts:');
    for (int i = 0; i < _chatRooms.length; i++) {
      final room = _chatRooms[i];
      print('  Room $i (${room.name}): ${room.unreadCount}');
    }
    
    // Notify parent widget about the change
    print('🔍 DEBUG: Calling onTotalUnreadCountChanged with count: $totalUnread');
    print('🔍 DEBUG: onTotalUnreadCountChanged callback exists: ${widget.onTotalUnreadCountChanged != null}');
    
    if (widget.onTotalUnreadCountChanged != null) {
      widget.onTotalUnreadCountChanged!(totalUnread);
      print('🔍 DEBUG: onTotalUnreadCountChanged called successfully');
    } else {
      print('🔍 ERROR: onTotalUnreadCountChanged callback is null!');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        if (mounted && !_isDisposed) {
          setState(() {
            _userName = userData['username'] ?? '';
          });
        }
      }
      await _fetchRooms();
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = 'Failed to load user data: $e';
        });
      }
    }
  }

  Future<void> _fetchRooms() async {
    try {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final rooms = await widget.apiService.fetchRooms();

      // Leave all rooms first
      await widget.apiService.leaveAllRooms();

      if (mounted && !_isDisposed) {
        setState(() {
          _chatRooms.clear();
          _chatRooms.addAll(rooms.map((room) => ChatRoom.fromJson(room)));
          _isLoading = false;
        });
        
        // Update total unread count after loading rooms
        _updateTotalUnreadCount();
      }

      // Join all rooms to receive notifications
      for (final room in _chatRooms) {
        print('Joining room: ${room.id}');
        await widget.apiService.joinRoom(room.id);
      }
    } catch (e) {
      print('Error fetching rooms: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = 'Failed to fetch rooms: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCurrentUserEmployeeId() async {
    print('\n=== Loading User ID ===');
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) {
      final userData = jsonDecode(userJson);
      final employeeId = userData['employeeID']?.toString();
      print('User ID loaded successfully: $employeeId');
      print('Full user data: $userData');
      
      _currentUserEmployeeId = employeeId;
      
      if (mounted) {
        setState(() {});
      }
      
      // Subscribe to chat list after getting employee ID
      if (employeeId != null && _socketListenersSetup) {
        _subscribeToChatList();
      }
    } else {
      print('No user data found in SharedPreferences');
    }
  }

  Future<void> _subscribeToChatList() async {
    print('\n=== Subscribing to Chat List ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');
    print('Employee ID: $_currentUserEmployeeId');
    
    // Check socket connection status
    _checkSocketConnection();
    
    if (_currentUserEmployeeId != null && widget.apiService.socket?.connected == true) {
      print('Subscribing to chat list for employee: $_currentUserEmployeeId');
      
      // Add a small delay to ensure proper cleanup from previous subscriptions
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Emit subscribe event
      widget.apiService.socket?.emit('subscribeChatList', {
        'empId': _currentUserEmployeeId
      });
      print('Subscribe request sent');
      
      // Also refresh all room subscriptions
      _refreshAllRoomSubscriptions();
    } else {
      print('Cannot subscribe: socket not connected or employee ID is null');
      print('Socket connected: ${widget.apiService.socket?.connected}');
      print('Employee ID: $_currentUserEmployeeId');
    }
  }

  // Check socket connection
  void _checkSocketConnection() {
    print('=== Socket Connection Check ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');
    print('Current user ID: $_currentUserEmployeeId');
    print('Socket listeners setup: $_socketListenersSetup');
  }

  /// Ensure all rooms are joined for real-time updates
  void _ensureAllRoomsJoined() {
    print('=== Ensuring All Rooms Are Joined ===');
    
    if (_currentUserEmployeeId == null || widget.apiService.socket?.connected != true) {
      print('Cannot join rooms: User ID or socket not ready');
      return;
    }
    
    try {
      for (final room in _chatRooms) {
        print('Ensuring room is joined: ${room.id}');
        widget.apiService.socket?.emit('joinRoom', {
          'roomId': room.id,
          'userId': _currentUserEmployeeId
        });
      }
      print('✅ All rooms join requests sent');
    } catch (e) {
      print('❌ Error joining rooms: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return WillPopScope(
      onWillPop: () async {
        await _refreshData();
        return true;
      },
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refreshData,
                            child: const Text('ลองใหม่'),
                          ),
                        ],
                      ),
                    )
                  : _chatRooms.isEmpty
                      ? const Center(child: Text('No chat rooms available'))
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _chatRooms.length,
                          itemBuilder: (context, index) {
                            final room = _chatRooms[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              child: Material(
                                color: Colors.white,
                                elevation: 2,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => _handleRoomTap(room),
                                  child: Container(
                                    height: 70,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.grey.withOpacity(0.2),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                            border: Border.all(color: Colors.grey.shade200, width: 2),
                                          ),
                                          child: CircleAvatar(
                                            radius: 28,
                                            backgroundColor: Color(int.parse(room.color.replaceAll('#', '0xFF'))),
                                            backgroundImage: (room.imageUrl != null && room.imageUrl!.isNotEmpty)
                                                ? NetworkImage('${ApiService.baseUrl}${room.imageUrl}')
                                                : null,
                                            child: (room.imageUrl == null || room.imageUrl!.isEmpty)
                                                ? Text(
                                                    room.name.substring(0, 1),
                                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                                  )
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            room.name,
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.w500,
                                                              fontSize: room.name.length > 20 ? 12 : 12,
                                                              color: room.name.length > 20 ? Colors.black : Colors.black,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                            maxLines: 1,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Icon(Icons.group, size: 14, color: Colors.grey.shade400),
                                                        Text(
                                                          ' (${room.memberCount})',
                                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    room.lastMessageTime,
                                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${room.lastMessageSender(_currentUserEmployeeId, room.name)}: ${room.lastMessageText}',
                                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (room.unreadCount > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 10),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: room.unreadCount > 99 ? 6 : 4,
                                              vertical: 2,
                                            ),
                                            constraints: BoxConstraints(
                                              minWidth: room.unreadCount > 99 ? 24 : 20,
                                              minHeight: 20,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade500,
                                              shape: room.unreadCount > 99 ? BoxShape.rectangle : BoxShape.circle,
                                              borderRadius: room.unreadCount > 99 ? BorderRadius.circular(12) : null,
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
                                              room.unreadCount > 99 ? '99+' : room.unreadCount.toString(),
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
      ),
    );
  }


Future<void> _handleRoomTap(ChatRoom room) async {
  print('\n=== Room Tap Handler ===');
  print('Room ID: ${room.id}');
  print('Room Name: ${room.name}');
  print('Current User ID: $_currentUserEmployeeId');
  
  // ป้องกันการกดซ้ำขณะกำลัง navigate
  if (_isNavigating) return;
  
  setState(() {
    _isNavigating = true;
  });
  
  // แสดง loading dialog
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false, // ป้องกันการกด back button
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'กำลังเข้าสู่ห้องแชท...',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  try {
    print('Attempting to mark room as read...');
    await widget.apiService.markRoomAsRead(room.id);
    print('Successfully marked room as read');

    // Update local state immediately
    _updateRoomUnreadCount(room.id, 0);

    if (mounted) {
      // ปิด loading dialog
      Navigator.of(context).pop();
      
      print('Navigating to chat page...');
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: room.id,
            roomName: room.name,
            apiService: widget.apiService,
            userRole: room.userRole,
            imageUrl: room.imageUrl,
            color: room.color,
            onEnterChatRoom: _handleChatRoomEntry,
          ),
        ),
      );
      
      // Refresh room data and subscriptions if returning from chat page
      if (result == true || result == null) {
        print('Refreshing room data and subscriptions after returning from chat...');
        
        // Add a small delay to ensure proper cleanup
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (mounted && !_isDisposed) {
          await _refreshData();
          
          // Also refresh socket subscriptions
          if (_currentUserEmployeeId != null && widget.apiService.socket?.connected == true) {
            print('Refreshing socket subscriptions after returning from chat');
            _subscribeToChatList();
            _refreshAllRoomSubscriptions();
          }
        }
      }
    }
  } catch (e) {
    print('❌ Error in room tap handler: $e');
    
    if (mounted) {
      // ปิด loading dialog ก่อนแสดง error
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถเข้าสู่ห้องแชทได้: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } finally {
    // รีเซ็ต loading state
    if (mounted) {
      setState(() {
        _isNavigating = false;
      });
    }
  }
}

  @override
  void dispose() {
    print('\n=== Disposing Room Page ===');
    WidgetsBinding.instance.removeObserver(this);
    _isDisposed = true;
    _removeSocketListeners();
    _socketListenersSetup = false;
    super.dispose();
  }

  Future<void> _refreshData() async {
    print('\n=== Refreshing Room Data ===');
    if (!_isDisposed && mounted) {
      setState(() {
        _isLoading = true;
      });
      
      print('Fetching rooms...');
      await _fetchRooms();
      print('Current rooms after fetch: ${_chatRooms.map((r) => '${r.id} (${r.name})').join(', ')}');
    }
  }
}