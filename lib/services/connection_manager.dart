import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'dart:convert';

/// ConnectionManager สำหรับจัดการการเชื่อมต่อ Socket แบบรวมศูนย์
class ConnectionManager {
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  final Map<String, IO.Socket> _connections = {};
  final Map<String, List<Function(dynamic)>> _eventListeners = {};
  final Map<String, bool> _connectionStatus = {};
  final Map<String, Timer> _reconnectTimers = {};
  
  // Configuration
  static const int _maxReconnectAttempts = 5;
  static const Duration _baseReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  /// ดึงการเชื่อมต่อ Socket สำหรับ URL ที่กำหนด
  IO.Socket getConnection(String url, {Map<String, dynamic>? options}) {
    if (!_connections.containsKey(url)) {
      _createConnection(url, options);
    }
    return _connections[url]!;
  }

  /// สร้างการเชื่อมต่อใหม่
  void _createConnection(String url, Map<String, dynamic>? options) {
    print('=== ConnectionManager: Creating new connection ===');
    print('URL: $url');
    
    final defaultOptions = <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'path': '/socket.io/',
      // 'path': '/chatio/socket.io/',
      'reconnection': true,
      'reconnectionAttempts': _maxReconnectAttempts,
      'reconnectionDelay': _baseReconnectDelay.inMilliseconds,
      'reconnectionDelayMax': _maxReconnectDelay.inMilliseconds,
      'timeout': 30000,
      'forceNew': true,
      'autoConnect': true,
      'upgrade': true,
      'rememberUpgrade': true,
    };

    final finalOptions = {...defaultOptions, ...?options};
    
    final socket = IO.io(url, finalOptions);
    _connections[url] = socket;
    _connectionStatus[url] = false;
    _eventListeners[url] = [];

    _setupConnectionListeners(url, socket);
    _setupReconnectionLogic(url, socket);
  }

  /// ตั้งค่า listeners สำหรับการเชื่อมต่อ
  void _setupConnectionListeners(String url, IO.Socket socket) {
    socket.onConnect((_) {
      print('=== ConnectionManager: Connected ===');
      print('URL: $url');
      print('Socket ID: ${socket.id}');
      print('Transport: ${socket.io.engine?.transport?.name ?? 'unknown'}');
      _connectionStatus[url] = true;
      _clearReconnectTimer(url);
      _emitConnectionEvent(url, 'connected', socket.id);
    });

    socket.onDisconnect((_) {
      print('=== ConnectionManager: Disconnected ===');
      print('URL: $url');
      _connectionStatus[url] = false;
      _emitConnectionEvent(url, 'disconnected', null);
    });

    socket.onConnectError((error) {
      print('=== ConnectionManager: Connection Error ===');
      print('URL: $url');
      print('Error: $error');
      _connectionStatus[url] = false;
      _emitConnectionEvent(url, 'error', error);
    });

    socket.onError((error) {
      print('=== ConnectionManager: Socket Error ===');
      print('URL: $url');
      print('Error: $error');
      _emitConnectionEvent(url, 'error', error);
    });

    socket.onReconnect((_) {
      print('=== ConnectionManager: Reconnected ===');
      print('URL: $url');
      print('Socket ID: ${socket.id}');
      _connectionStatus[url] = true;
      _clearReconnectTimer(url);
      _emitConnectionEvent(url, 'connected', socket.id);
    });

    socket.onReconnectError((error) {
      print('=== ConnectionManager: Reconnection Error ===');
      print('URL: $url');
      print('Error: $error');
      _emitConnectionEvent(url, 'error', error);
    });

    socket.onReconnectFailed((_) {
      print('=== ConnectionManager: Reconnection Failed ===');
      print('URL: $url');
      _emitConnectionEvent(url, 'error', 'Reconnection failed');
    });
  }

  /// ตั้งค่าการ reconnect อัตโนมัติ
  void _setupReconnectionLogic(String url, IO.Socket socket) {
    socket.onDisconnect((_) {
      if (_reconnectTimers.containsKey(url)) {
        _reconnectTimers[url]?.cancel();
      }
      
      final timer = Timer(_baseReconnectDelay, () {
        if (!_connectionStatus[url]! && socket.connected != true) {
          print('=== ConnectionManager: Attempting to reconnect ===');
          print('URL: $url');
          socket.connect();
        }
      });
      
      _reconnectTimers[url] = timer;
    });
  }

  /// ล้าง timer การ reconnect
  void _clearReconnectTimer(String url) {
    _reconnectTimers[url]?.cancel();
    _reconnectTimers.remove(url);
  }

  /// ส่ง event การเชื่อมต่อ
  void _emitConnectionEvent(String url, String event, dynamic data) {
    final listeners = _eventListeners[url] ?? [];
    for (final listener in listeners) {
      try {
        listener({
          'event': event,
          'url': url,
          'data': data,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        print('Error in connection event listener: $e');
      }
    }
  }

  /// เพิ่ม listener สำหรับการเชื่อมต่อ
  void addConnectionListener(String url, Function(dynamic) listener) {
    if (!_eventListeners.containsKey(url)) {
      _eventListeners[url] = [];
    }
    _eventListeners[url]!.add(listener);
  }

  /// ลบ listener สำหรับการเชื่อมต่อ
  void removeConnectionListener(String url, Function(dynamic) listener) {
    _eventListeners[url]?.remove(listener);
  }

  /// ตรวจสอบสถานะการเชื่อมต่อ
  bool isConnected(String url) {
    return _connectionStatus[url] ?? false;
  }

  /// ดึง Socket ID
  String? getSocketId(String url) {
    return _connections[url]?.id;
  }

  /// ปิดการเชื่อมต่อ
  void disconnect(String url) {
    print('=== ConnectionManager: Disconnecting ===');
    print('URL: $url');
    
    _clearReconnectTimer(url);
    _connections[url]?.disconnect();
    _connections[url]?.dispose();
    _connections.remove(url);
    _connectionStatus.remove(url);
    _eventListeners.remove(url);
  }

  /// ปิดการเชื่อมต่อทั้งหมด
  void disconnectAll() {
    print('=== ConnectionManager: Disconnecting all connections ===');
    
    for (final url in _connections.keys.toList()) {
      disconnect(url);
    }
  }

  /// ตรวจสอบว่ามีการเชื่อมต่ออยู่หรือไม่
  bool hasConnection(String url) {
    return _connections.containsKey(url);
  }

  /// ดึงจำนวนการเชื่อมต่อที่ใช้งานอยู่
  int get activeConnectionCount => _connections.length;

  /// ดึงรายการ URL ที่เชื่อมต่ออยู่
  List<String> get connectedUrls {
    return _connections.keys.where((url) => _connectionStatus[url] ?? false).toList();
  }

  /// Cleanup resources
  void dispose() {
    disconnectAll();
  }
} 