import 'dart:async';
import 'dart:math';

/// RetryManager สำหรับจัดการการ retry operations อย่างชาญฉลาด
class RetryManager {
  static final RetryManager _instance = RetryManager._internal();
  factory RetryManager() => _instance;
  RetryManager._internal();

  /// Retry configuration
  static const int _defaultMaxAttempts = 3;
  static const Duration _defaultBaseDelay = Duration(seconds: 1);
  static const Duration _defaultMaxDelay = Duration(seconds: 30);
  static const double _defaultBackoffMultiplier = 2.0;

  /// Retry operation ด้วย exponential backoff
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = _defaultMaxAttempts,
    Duration baseDelay = _defaultBaseDelay,
    Duration maxDelay = _defaultMaxDelay,
    double backoffMultiplier = _defaultBackoffMultiplier,
    bool Function(Exception)? shouldRetry,
    Function(int attempt, Exception error)? onRetry,
  }) async {
    Exception? lastException;
    
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        
        // ตรวจสอบว่าควร retry หรือไม่
        if (shouldRetry != null && !shouldRetry(lastException!)) {
          print('RetryManager: Should not retry - ${lastException.toString()}');
          rethrow;
        }
        
        // ถ้าเป็นครั้งสุดท้ายแล้ว ให้ throw exception
        if (attempt == maxAttempts) {
          print('RetryManager: Max attempts reached ($maxAttempts)');
          print('RetryManager: Last error - ${lastException.toString()}');
          rethrow;
        }
        
        // คำนวณ delay สำหรับครั้งถัดไป
        final delay = _calculateDelay(attempt, baseDelay, maxDelay, backoffMultiplier);
        
        print('RetryManager: Attempt $attempt failed');
        print('RetryManager: Error - ${lastException.toString()}');
        print('RetryManager: Retrying in ${delay.inMilliseconds}ms');
        
        // เรียก callback onRetry ถ้ามี
        onRetry?.call(attempt, lastException!);
        
        // รอก่อน retry
        await Future.delayed(delay);
      }
    }
    
    // ไม่ควรมาถึงจุดนี้ แต่ถ้ามาให้ throw exception สุดท้าย
    throw lastException ?? Exception('Unknown error occurred');
  }

  /// คำนวณ delay ด้วย exponential backoff
  static Duration _calculateDelay(
    int attempt,
    Duration baseDelay,
    Duration maxDelay,
    double backoffMultiplier,
  ) {
    final exponentialDelay = baseDelay * pow(backoffMultiplier, attempt - 1);
    final jitter = Duration(milliseconds: Random().nextInt(1000));
    final totalDelay = exponentialDelay + jitter;
    
    // จำกัด delay ไม่ให้เกิน maxDelay
    return totalDelay > maxDelay ? maxDelay : totalDelay;
  }

  /// Retry สำหรับ network operations
  static Future<T> withNetworkRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(seconds: 1),
  }) async {
    return withRetry<T>(
      operation,
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
      shouldRetry: (error) {
        // Retry เฉพาะ network errors
        return error.toString().contains('SocketException') ||
               error.toString().contains('TimeoutException') ||
               error.toString().contains('Connection refused') ||
               error.toString().contains('Network is unreachable');
      },
      onRetry: (attempt, error) {
        print('RetryManager: Network retry attempt $attempt');
        print('RetryManager: Network error - ${error.toString()}');
      },
    );
  }

  /// Retry สำหรับ socket operations
  static Future<T> withSocketRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 5,
    Duration baseDelay = const Duration(seconds: 2),
  }) async {
    return withRetry<T>(
      operation,
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
      shouldRetry: (error) {
        // Retry เฉพาะ socket errors และ connection errors
        final errorMessage = error.toString().toLowerCase();
        return errorMessage.contains('socket') ||
               errorMessage.contains('connection') ||
               errorMessage.contains('failed to establish') ||
               errorMessage.contains('not connected') ||
               errorMessage.contains('timeout') ||
               errorMessage.contains('network') ||
               errorMessage.contains('unreachable') ||
               errorMessage.contains('refused');
      },
      onRetry: (attempt, error) {
        print('RetryManager: Socket retry attempt $attempt');
        print('RetryManager: Socket error - ${error.toString()}');
        print('RetryManager: Attempting to reconnect...');
      },
    );
  }

  /// Retry สำหรับ API operations
  static Future<T> withApiRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(seconds: 1),
  }) async {
    return withRetry<T>(
      operation,
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
      shouldRetry: (error) {
        // Retry เฉพาะ server errors (5xx) และ network errors
        return error.toString().contains('500') ||
               error.toString().contains('502') ||
               error.toString().contains('503') ||
               error.toString().contains('504') ||
               error.toString().contains('SocketException') ||
               error.toString().contains('TimeoutException');
      },
      onRetry: (attempt, error) {
        print('RetryManager: API retry attempt $attempt');
        print('RetryManager: API error - ${error.toString()}');
      },
    );
  }

  /// Retry ด้วย custom condition
  static Future<T> withConditionalRetry<T>(
    Future<T> Function() operation, {
    required bool Function(Exception) shouldRetry,
    int maxAttempts = 3,
    Duration baseDelay = const Duration(seconds: 1),
    Function(int attempt, Exception error)? onRetry,
  }) async {
    return withRetry<T>(
      operation,
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
      shouldRetry: shouldRetry,
      onRetry: onRetry,
    );
  }

  /// Retry แบบ immediate (ไม่ delay)
  static Future<T> withImmediateRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
  }) async {
    return withRetry<T>(
      operation,
      maxAttempts: maxAttempts,
      baseDelay: Duration.zero,
      maxDelay: Duration.zero,
    );
  }

  /// Retry แบบ linear (delay เพิ่มขึ้นแบบเส้นตรง)
  static Future<T> withLinearRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(seconds: 1),
  }) async {
    return withRetry<T>(
      operation,
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
      backoffMultiplier: 1.0, // ไม่มี exponential backoff
    );
  }
} 