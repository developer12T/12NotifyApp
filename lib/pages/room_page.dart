import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import 'dart:math' as math;
import 'chat_page.dart';

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
  
  String get lastMessageTime =>
      lastMessage['timestamp'] != null
          ? DateTime.parse(
            lastMessage['timestamp'],
          ).toString().substring(11, 16)
          : '';
}

class RoomPage extends StatefulWidget {
  final ApiService apiService;

  const RoomPage({super.key, required this.apiService});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  String _userName = '';
  final List<ChatRoom> _chatRooms = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUserEmployeeId;
  bool _isDisposed = false;
  bool _isFirstLoad = true;
  bool _socketListenersSetup = false;

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
    }
    _isFirstLoad = false;
  }

  void _setupSocketListeners() {
    if (_socketListenersSetup || widget.apiService.socket == null) {
      print('Socket listeners already setup or socket is null');
      return;
    }

    print('\n=== Setting up Socket Listeners ===');
    print('Socket connected: ${widget.apiService.socket?.connected}');
    print('Socket ID: ${widget.apiService.socket?.id}');

    // Remove any existing listeners first
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
      }
    });

    _socketListenersSetup = true;
    print('Socket listeners setup completed');

    // Subscribe to chat list if we have user ID
    if (_currentUserEmployeeId != null) {
      _subscribeToChatList();
    }
  }

  void _removeSocketListeners() {
    print('Removing existing socket listeners');
    widget.apiService.socket?.off('newMessage');
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
    
    if (!mounted || _isDisposed) {
      print('Widget is not mounted, skipping message update');
      return;
    }

    final messageRoomId = message['room']?.toString();
    if (messageRoomId == null) {
      print('Invalid message room ID');
      return;
    }

    // Find and update the room
    final roomIndex = _chatRooms.indexWhere((room) => room.id == messageRoomId);
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
    }

    final newLastMessage = {
      'sender': sender ?? 'ยังไม่มีข้อความ',
      'message': message['message'] ?? '',
      'timestamp': message['timestamp'] ?? DateTime.now().toIso8601String(),
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
    
    print('Room updated successfully');
  }

  void _updateRoomUnreadCount(String roomId, int unreadCount) {
    final roomIndex = _chatRooms.indexWhere((room) => room.id == roomId);
    if (roomIndex != -1) {
      final room = _chatRooms[roomIndex];
      final updatedRoom = ChatRoom(
        id: room.id,
        name: room.name,
        description: room.description,
        admin: room.admin,
        lastMessage: room.lastMessage,
        unreadCount: unreadCount,
        color: room.color,
        memberCount: room.memberCount,
        userRole: room.userRole,
      );
      
      setState(() {
        _chatRooms[roomIndex] = updatedRoom;
      });
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
    
    if (_currentUserEmployeeId != null && widget.apiService.socket?.connected == true) {
      print('Subscribing to chat list for employee: $_currentUserEmployeeId');
      widget.apiService.socket?.emit('subscribeChatList', {
        'empId': _currentUserEmployeeId
      });
      print('Subscribe request sent');
    } else {
      print('Cannot subscribe: Employee ID: $_currentUserEmployeeId, Socket connected: ${widget.apiService.socket?.connected}');
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Material(
                                color: Colors.white,
                                elevation: 2,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => _handleRoomTap(room),
                                  child: Container(
                                    height: 80,
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
                                            child: Text(
                                              room.name.substring(0, 1),
                                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                            ),
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
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: room.name.length > 20 ? 14 : 17,
                                                              color: room.name.length > 20 ? Colors.grey.shade700 : Colors.black,
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
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${room.lastMessageSender(_currentUserEmployeeId, room.name)}: ${room.lastMessageText}',
                                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (room.unreadCount > 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 10),
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade400,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.green.withOpacity(0.2),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              room.unreadCount.toString(),
                                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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
    
    try {
      print('Attempting to mark room as read...');
      await widget.apiService.markRoomAsRead(room.id);
      print('Successfully marked room as read');

      // Update local state immediately
      _updateRoomUnreadCount(room.id, 0);

      if (mounted) {
        print('Navigating to chat page...');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              roomId: room.id,
              roomName: room.name,
              apiService: widget.apiService,
              userRole: room.userRole,
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Error in room tap handler: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถอัพเดทสถานะการอ่านได้: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
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