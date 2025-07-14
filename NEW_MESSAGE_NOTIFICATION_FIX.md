# การแก้ไขปัญหาการแจ้งเตือน "New Message"

## 🚨 ปัญหาที่พบ

ยังมีการแจ้งเตือน "New Message" แสดงขึ้นมาแม้ว่าจะปิดการแจ้งเตือนข้อความแล้ว

## 🔍 สาเหตุที่เป็นไปได้

1. **Test Notification** - มี test notification ที่ยังทำงานอยู่
2. **Server Notification** - Server ส่ง notification ผ่าน FCM
3. **Firebase Console** - มีการส่ง notification จาก Firebase Console
4. **Background Service** - Background service ส่ง notification

## ✅ การแก้ไขที่ทำ

### 1. **ปิด Test Notification**

#### ใน MainNavigation (`lib/pages/main_navigation.dart`):
```dart
// DISABLED: Test notification after 3 seconds
// Future.delayed(const Duration(seconds: 3), () {
//   _testNotification();
// });
```

#### ปิดการแจ้งเตือนข้อความ:
```dart
// DISABLED: Notifications temporarily disabled
print('Notifications disabled - skipping message notification');
```

### 2. **ปิดการแจ้งเตือนใน FCM Service**

#### ใน Background Handler:
```dart
// Skip "New Message" notifications
if (message.notification?.title == 'New Message') {
  print('FCMService: Skipping "New Message" notification in background');
  return;
}
```

#### ใน Foreground Handler:
```dart
// Skip "New Message" notifications
if (message.notification?.title == 'New Message') {
  print('FCMService: Skipping "New Message" notification in foreground');
  return;
}
```

### 3. **เพิ่ม Detailed Logging**

#### เพิ่มการ log เพื่อติดตามที่มาของ notification:
```dart
print('Background message data: ${message.data}');
print('Background message from: ${message.from}');
print('Background message messageId: ${message.messageId}');
print('Background message sentTime: ${message.sentTime}');
```

## 🔧 การตรวจสอบ

### วิธีตรวจสอบที่มาของ notification:

1. **เปิดแอปและดู log** - ดูว่า notification มาจากไหน
2. **ตรวจสอบ Firebase Console** - ดูว่ามีการส่ง notification หรือไม่
3. **ตรวจสอบ Server** - ดูว่ามีการส่ง notification จาก server หรือไม่

### Log ที่ควรดู:

```
FCMService: Background message received: New Message
FCMService: Background message data: {...}
FCMService: Background message from: ...
FCMService: Background message messageId: ...
FCMService: Background message sentTime: ...
```

## 📊 ผลลัพธ์ที่คาดหวัง

หลังจากแก้ไขแล้ว:

1. **ไม่มีการแจ้งเตือน "New Message"** - จะไม่มีการแจ้งเตือนข้อความใหม่
2. **ยังคงมีการแจ้งเตือนประกาศ** - การแจ้งเตือนประกาศยังทำงานได้ตามปกติ
3. **Badge counter ยังทำงาน** - แสดงจำนวนข้อความที่ยังไม่ได้อ่าน

## 🚀 การใช้งาน

การแก้ไขนี้จะ:

1. **ปิดการแจ้งเตือนข้อความ** - ไม่แสดง notification สำหรับข้อความใหม่
2. **ยังคงแสดง badge** - แสดงจำนวนข้อความที่ยังไม่ได้อ่าน
3. **ยังคงแจ้งเตือนประกาศ** - การแจ้งเตือนประกาศยังทำงานได้ตามปกติ

## 📝 ไฟล์ที่แก้ไข

1. `lib/pages/main_navigation.dart`
   - ปิด test notification
   - ปิดการแจ้งเตือนข้อความ

2. `lib/services/fcm_service.dart`
   - เพิ่มการข้าม "New Message" notifications
   - เพิ่ม detailed logging

## 🔍 การตรวจสอบเพิ่มเติม

หากยังมีการแจ้งเตือน "New Message" ให้ตรวจสอบ:

1. **Firebase Console** - ดูว่ามีการส่ง notification หรือไม่
2. **Server Logs** - ดูว่ามีการส่ง notification จาก server หรือไม่
3. **App Logs** - ดู log เพื่อหาที่มาของ notification 