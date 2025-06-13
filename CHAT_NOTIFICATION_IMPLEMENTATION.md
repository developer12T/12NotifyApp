# การเพิ่มการแจ้งเตือนแชทกลุ่มและ Direct Message

## 🎯 เป้าหมาย
เพิ่มการรองรับการแจ้งเตือนสำหรับแชทกลุ่มและ direct message ใน background service

## 📝 การเปลี่ยนแปลงที่ทำ

### 1. **ปรับปรุง Background Service (lib/main.dart)**

#### เพิ่ม Event Listeners ใหม่:
- `showGroupChatNotification`: สำหรับการแจ้งเตือนแชทกลุ่ม
- `showDirectMessageNotification`: สำหรับการแจ้งเตือน direct message
- `showGeneralNotification`: สำหรับการแจ้งเตือนทั่วไป

#### การทำงาน:
```dart
// รับคำสั่งแสดง notification สำหรับแชทกลุ่ม
service.on('showGroupChatNotification').listen((event) {
  final title = 'ข้อความใหม่ในกลุ่ม $roomName';
  final body = '$senderName: $message';
  // แสดงการแจ้งเตือนผ่าน NotiService
});

// รับคำสั่งแสดง notification สำหรับ direct message
service.on('showDirectMessageNotification').listen((event) {
  final title = 'ข้อความใหม่จาก $senderName';
  final body = message.length > 50 ? '${message.substring(0, 50)}...' : message;
  // แสดงการแจ้งเตือนผ่าน NotiService
});
```

#### เพิ่มการ Subscribe:
```dart
// Subscribe to all notifications for background
socketService.subscribeToAllNotifications();
```

### 2. **ปรับปรุง SocketService (lib/services/socket_service.dart)**

#### เพิ่ม Methods ใหม่:

##### การจัดการการแจ้งเตือน:
- `_handleGroupChatNotification()`: จัดการการแจ้งเตือนแชทกลุ่ม
- `_handleDirectMessageNotification()`: จัดการการแจ้งเตือน direct message
- `_sendToBackgroundService()`: ส่งคำสั่งไปยัง background service

##### การ Subscribe:
- `subscribeToGroupChatNotifications()`: Subscribe ไปยังการแจ้งเตือนแชทกลุ่ม
- `subscribeToDirectMessageNotifications()`: Subscribe ไปยังการแจ้งเตือน direct message
- `subscribeToAllNotifications()`: Subscribe ไปยังการแจ้งเตือนทั้งหมด

#### การทำงาน:
```dart
// จัดการการแจ้งเตือนแชทกลุ่ม
void _handleGroupChatNotification(dynamic data) {
  // ตรวจสอบว่าเป็น background service หรือไม่
  bool isInBackgroundService = _isInBackgroundService();
  
  if (isInBackgroundService) {
    // ส่งคำสั่งไปยัง background service
    _sendToBackgroundService('showGroupChatNotification', data);
  } else {
    // ใช้ NotiService ปกติ
    _notiService.showNotification(...);
  }
}
```

### 3. **การจัดการ Event Listeners**

#### แชทกลุ่ม:
```dart
_unifiedSocketService.onMessage('newMessageNotification', (data) {
  _handleGroupChatNotification(data);
});
```

#### Direct Message:
```dart
_unifiedSocketService.onMessage('newDirectMessageNotification', (data) {
  _handleDirectMessageNotification(data);
});
```

## 🔧 การทำงานของระบบ

### 1. **เมื่อแอปอยู่ใน Background:**
1. Background service ทำงานและ subscribe ไปยังการแจ้งเตือนทั้งหมด
2. เมื่อได้รับข้อความใหม่ SocketService ตรวจสอบว่าเป็น background service
3. ส่งคำสั่งไปยัง background service ผ่าน `FlutterBackgroundService.invoke()`
4. Background service รับคำสั่งและแสดงการแจ้งเตือนผ่าน `NotiService.showNotificationWithoutInit()`

### 2. **เมื่อแอปอยู่ใน Foreground:**
1. SocketService ตรวจสอบว่าไม่ใช่ background service
2. แสดงการแจ้งเตือนโดยตรงผ่าน `NotiService.showNotification()`

### 3. **การตรวจสอบ Background Service:**
```dart
bool _isInBackgroundService() {
  final stackTrace = StackTrace.current.toString();
  return stackTrace.contains('flutter_background_service') || 
         stackTrace.contains('BackgroundService') ||
         stackTrace.contains('onStart');
}
```

## 📊 ข้อมูลการแจ้งเตือน

### แชทกลุ่ม:
```json
{
  "type": "group_chat",
  "roomId": "room_123",
  "roomName": "กลุ่มทดสอบ",
  "senderName": "ผู้ใช้ทดสอบ",
  "message": "สวัสดีครับ",
  "unreadCount": 1,
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

### Direct Message:
```json
{
  "type": "direct_message",
  "senderId": "user_456",
  "senderName": "ผู้ใช้ส่วนตัว",
  "message": "สวัสดีครับ",
  "unreadCount": 1,
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

## 🚀 การใช้งาน

### การเรียกใช้จากแอปหลัก:
```dart
// ส่งการแจ้งเตือนแชทกลุ่ม
final service = FlutterBackgroundService();
service.invoke('showGroupChatNotification', {
  'roomId': 'room_123',
  'roomName': 'กลุ่มทดสอบ',
  'senderName': 'ผู้ใช้ทดสอบ',
  'message': 'สวัสดีครับ',
  'unreadCount': 1,
  'timestamp': DateTime.now().toIso8601String(),
});

// ส่งการแจ้งเตือน Direct Message
service.invoke('showDirectMessageNotification', {
  'senderId': 'user_456',
  'senderName': 'ผู้ใช้ส่วนตัว',
  'message': 'สวัสดีครับ',
  'unreadCount': 1,
  'timestamp': DateTime.now().toIso8601String(),
});
```

## ✅ ผลลัพธ์ที่ได้

1. **การแจ้งเตือนแชทกลุ่ม**: แสดงชื่อกลุ่มและชื่อผู้ส่งพร้อมข้อความ
2. **การแจ้งเตือน Direct Message**: แสดงชื่อผู้ส่งและข้อความ (ตัดข้อความยาว)
3. **การทำงานใน Background**: แจ้งเตือนได้แม้ว่าแอปจะไม่ได้เปิดอยู่
4. **การทำงานใน Foreground**: แจ้งเตือนได้เมื่อแอปเปิดอยู่
5. **Payload ที่ถูกต้อง**: ข้อมูลครบถ้วนสำหรับการนำทางไปยังหน้าที่เหมาะสม

## 🔍 การทดสอบ

ดูไฟล์ `test_chat_notifications.md` สำหรับขั้นตอนการทดสอบที่ละเอียด

## 📝 หมายเหตุ

- การแจ้งเตือนจะทำงานทั้งใน foreground และ background
- ระบบจะตรวจสอบสถานะของแอปและเลือกวิธีการแสดงการแจ้งเตือนที่เหมาะสม
- Payload ของการแจ้งเตือนมีข้อมูลครบถ้วนสำหรับการนำทางไปยังหน้าที่เหมาะสม
- การจัดการข้อผิดพลาดครอบคลุมทุกขั้นตอน 