# การทดสอบการแจ้งเตือน - Debug Guide

## ปัญหาที่พบ
- ไม่มีการแจ้งเตือนเลย

## การแก้ไขที่ทำ

### 1. เพิ่มการทดสอบการแจ้งเตือน
- เพิ่มการทดสอบการแจ้งเตือนใน `main_navigation.dart` หลังจาก 3 วินาที
- เพิ่ม logging ใน `handleNewMessageNotification`
- เพิ่ม logging ใน `_handleNewMessage` ของ `room_page.dart`

### 2. เพิ่มการตั้งค่า iOS
- เพิ่ม `NSUserNotificationUsageDescription` ใน `Info.plist`

### 3. ตรวจสอบการทำงาน
- ตรวจสอบว่า `NotificationService` ถูก initialize หรือไม่
- ตรวจสอบว่า `handleNewMessageNotification` ถูกเรียกหรือไม่
- ตรวจสอบว่า `onNewMessageNotification` ถูกเรียกหรือไม่

## วิธีทดสอบ

### ขั้นตอนที่ 1: ทดสอบการแจ้งเตือนพื้นฐาน
1. รันแอป
2. รอ 3 วินาที
3. ตรวจสอบ: ควรมีการแจ้งเตือน "ทดสอบการแจ้งเตือน"

### ขั้นตอนที่ 2: ทดสอบการแจ้งเตือนข้อความใหม่
1. เข้าห้องแชท A
2. ออกจากห้อง A
3. ส่งข้อความในห้อง A จากอุปกรณ์อื่น
4. ตรวจสอบ: ควรมีการแจ้งเตือน "ข้อความใหม่ในกลุ่ม"

### ขั้นตอนที่ 3: ตรวจสอบ Logs
ตรวจสอบ logs ต่อไปนี้:
- `Testing notification...`
- `=== handleNewMessageNotification called ===`
- `User not in chat room, showing notification`
- `Calling onNewMessageNotification with count: X`

## การแก้ไขเพิ่มเติม

### หากไม่มีการแจ้งเตือนทดสอบ
1. ตรวจสอบการตั้งค่า notification permissions ในอุปกรณ์
2. ตรวจสอบว่าแอปได้รับอนุญาตให้แสดงการแจ้งเตือนหรือไม่
3. ตรวจสอบ logs ของ `NotificationService`

### หากไม่มีการแจ้งเตือนข้อความใหม่
1. ตรวจสอบว่า `_handleNewMessage` ถูกเรียกหรือไม่
2. ตรวจสอบว่า `onNewMessageNotification` ถูกเรียกหรือไม่
3. ตรวจสอบว่า `handleNewMessageNotification` ถูกเรียกหรือไม่

## การตั้งค่าที่จำเป็น

### Android
- `POST_NOTIFICATIONS` permission (Android 13+)
- Notification channel setup

### iOS
- `NSUserNotificationUsageDescription` ใน Info.plist
- Request notification permissions

## การ Debug เพิ่มเติม

### ตรวจสอบ Notification Permissions
```dart
// เพิ่มใน main_navigation.dart
Future<void> checkNotificationPermissions() async {
  final androidPlugin = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    final granted = await androidPlugin.requestNotificationsPermission();
    print('Android notification permission granted: $granted');
  }

  final iOSPlugin = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
  if (iOSPlugin != null) {
    final granted = await iOSPlugin.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    print('iOS notification permission granted: $granted');
  }
}
```

### ตรวจสอบ Socket Connection
```dart
// เพิ่มใน room_page.dart
void _checkSocketConnection() {
  print('Socket connected: ${widget.apiService.socket?.connected}');
  print('Socket ID: ${widget.apiService.socket?.id}');
  print('Current user ID: $_currentUserEmployeeId');
}
``` 