import 'dart:async';
import 'dart:collection';

/// MemoryManager สำหรับจัดการ memory leaks และ cleanup resources
class MemoryManager {
  static final MemoryManager _instance = MemoryManager._internal();
  factory MemoryManager() => _instance;
  MemoryManager._internal();

  // Track resources
  final Map<String, List<Function()>> _cleanupCallbacks = {};
  final Map<String, Timer> _timers = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, dynamic> _resources = {};
  
  // Configuration
  static const Duration _defaultCleanupDelay = Duration(seconds: 30);
  static const int _maxResourcesPerType = 100;

  /// เพิ่ม cleanup callback
  void addCleanupCallback(String type, String id, Function() callback) {
    final key = '${type}_$id';
    if (!_cleanupCallbacks.containsKey(key)) {
      _cleanupCallbacks[key] = [];
    }
    _cleanupCallbacks[key]!.add(callback);
    
    // จำกัดจำนวน resources
    _limitResources(type);
  }

  /// เพิ่ม timer
  void addTimer(String type, String id, Timer timer) {
    final key = '${type}_$id';
    _timers[key] = timer;
    _limitResources(type);
  }

  /// เพิ่ม subscription
  void addSubscription(String type, String id, StreamSubscription subscription) {
    final key = '${type}_$id';
    _subscriptions[key] = subscription;
    _limitResources(type);
  }

  /// เพิ่ม resource
  void addResource(String type, String id, dynamic resource) {
    final key = '${type}_$id';
    _resources[key] = resource;
    _limitResources(type);
  }

  /// จำกัดจำนวน resources ต่อประเภท
  void _limitResources(String type) {
    final resources = _cleanupCallbacks.keys.where((key) => key.startsWith('${type}_')).toList();
    if (resources.length > _maxResourcesPerType) {
      // ลบ resources เก่าที่สุด
      final toRemove = resources.take(resources.length - _maxResourcesPerType);
      for (final key in toRemove) {
        cleanup(key);
      }
    }
  }

  /// Cleanup resource ตาม key
  void cleanup(String key) {
    print('MemoryManager: Cleaning up resource: $key');
    
    // Cleanup callbacks
    final callbacks = _cleanupCallbacks[key];
    if (callbacks != null) {
      for (final callback in callbacks) {
        try {
          callback();
        } catch (e) {
          print('MemoryManager: Error in cleanup callback: $e');
        }
      }
      _cleanupCallbacks.remove(key);
    }
    
    // Cancel timer
    final timer = _timers[key];
    if (timer != null) {
      timer.cancel();
      _timers.remove(key);
    }
    
    // Cancel subscription
    final subscription = _subscriptions[key];
    if (subscription != null) {
      subscription.cancel();
      _subscriptions.remove(key);
    }
    
    // Dispose resource
    final resource = _resources[key];
    if (resource != null) {
      try {
        if (resource is StreamSubscription) {
          resource.cancel();
        } else if (resource is Timer) {
          resource.cancel();
        } else if (resource is Function) {
          resource();
        }
      } catch (e) {
        print('MemoryManager: Error disposing resource: $e');
      }
      _resources.remove(key);
    }
  }

  /// Cleanup resources ตามประเภท
  void cleanupType(String type) {
    print('MemoryManager: Cleaning up type: $type');
    
    final keys = _cleanupCallbacks.keys.where((key) => key.startsWith('${type}_')).toList();
    for (final key in keys) {
      cleanup(key);
    }
  }

  /// Cleanup resources ตาม ID
  void cleanupId(String id) {
    print('MemoryManager: Cleaning up ID: $id');
    
    final keys = _cleanupCallbacks.keys.where((key) => key.endsWith('_$id')).toList();
    for (final key in keys) {
      cleanup(key);
    }
  }

  /// Cleanup ทั้งหมด
  void cleanupAll() {
    print('MemoryManager: Cleaning up all resources');
    
    final allKeys = _cleanupCallbacks.keys.toList();
    for (final key in allKeys) {
      cleanup(key);
    }
  }

  /// Schedule cleanup หลังจาก delay
  void scheduleCleanup(String type, String id, {Duration? delay}) {
    final key = '${type}_$id';
    final timer = Timer(delay ?? _defaultCleanupDelay, () {
      cleanup(key);
    });
    addTimer('scheduled', key, timer);
  }

  /// ตรวจสอบจำนวน resources
  int getResourceCount(String type) {
    return _cleanupCallbacks.keys.where((key) => key.startsWith('${type}_')).length;
  }

  /// ตรวจสอบจำนวน resources ทั้งหมด
  int get totalResourceCount => _cleanupCallbacks.length;

  /// ดึงรายการ types ที่มีอยู่
  Set<String> get resourceTypes {
    return _cleanupCallbacks.keys.map((key) => key.split('_').first).toSet();
  }

  /// ตรวจสอบว่ามี resource อยู่หรือไม่
  bool hasResource(String type, String id) {
    final key = '${type}_$id';
    return _cleanupCallbacks.containsKey(key);
  }

  /// Dispose MemoryManager
  void dispose() {
    print('MemoryManager: Disposing all resources');
    cleanupAll();
  }

  /// Debug: แสดงสถานะ resources
  void debugPrint() {
    print('=== MemoryManager Debug Info ===');
    print('Total resources: $totalResourceCount');
    print('Resource types: ${resourceTypes.join(', ')}');
    
    for (final type in resourceTypes) {
      final count = getResourceCount(type);
      print('$type: $count resources');
    }
    
    print('Timers: ${_timers.length}');
    print('Subscriptions: ${_subscriptions.length}');
    print('Resources: ${_resources.length}');
    print('===============================');
  }
} 