# การทดสอบการแจ้งเตือนแชทกลุ่มและ Direct Message

## 🎯 เป้าหมาย
ทดสอบการแจ้งเตือนสำหรับแชทกลุ่มและ direct message ใน background service

## 📋 ขั้นตอนการทดสอบ

### ขั้นตอนที่ 1: เตรียมการ
1. รันแอป
2. ตรวจสอบ logs ต่อไปนี้:
   ```
   === Background Service: Subscribed to all notifications ===
   === SocketService: Subscribing to All Notifications ===
   === SocketService: Subscribing to Group Chat Notifications ===
   === SocketService: Subscribing to Direct Message Notifications ===
   ```

### ขั้นตอนที่ 2: ทดสอบการแจ้งเตือนแชทกลุ่ม
1. ใช้อุปกรณ์อื่นส่งข้อความในห้องแชทกลุ่ม
2. ตรวจสอบ logs:
   ```
   === SocketService: New Group Chat Message Received ===
   === SocketService: Handling Group Chat Notification ===
   === SocketService: Is in background service: true ===
   === SocketService: Sending to Background Service ===
   Command: showGroupChatNotification
   === Background Service: Show Group Chat Notification Command ===
   === Background Service: Group chat notification shown successfully ===
   ```

### ขั้นตอนที่ 3: ทดสอบการแจ้งเตือน Direct Message
1. ใช้อุปกรณ์อื่นส่งข้อความส่วนตัวถึงผู้ใช้ปัจจุบัน
2. ตรวจสอบ logs:
   ```
   === SocketService: New Direct Message Received ===
   === SocketService: Handling Direct Message Notification ===
   === SocketService: Is in background service: true ===
   === SocketService: Sending to Background Service ===
   Command: showDirectMessageNotification
   === Background Service: Show Direct Message Notification Command ===
   === Background Service: Direct message notification shown successfully ===
   ```

### ขั้นตอนที่ 4: ตรวจสอบการแจ้งเตือน
1. ตรวจสอบว่าการแจ้งเตือนปรากฏบนหน้าจอ
2. ตรวจสอบ payload ของการแจ้งเตือน:
   - **แชทกลุ่ม**: `type: 'group_chat'`, `roomId`, `roomName`, `senderName`, `message`
   - **Direct Message**: `type: 'direct_message'`, `senderId`, `senderName`, `message`

### ขั้นตอนที่ 5: ทดสอบเมื่อแอปอยู่ใน foreground
1. เปิดแอปและอยู่ในหน้าแชท
2. ใช้อุปกรณ์อื่นส่งข้อความ
3. ตรวจสอบ logs:
   ```
   === SocketService: Is in background service: false ===
   === SocketService: Using normal NotiService ===
   ```

## 🔍 การ Debug

### หากไม่มีการแจ้งเตือน:

#### 1. ตรวจสอบ Socket Connection
```dart
// ตรวจสอบใน logs
Socket connected: true
Socket ID: [socket_id]
```

#### 2. ตรวจสอบ Subscription
```dart
// ตรวจสอบใน logs
=== SocketService: Subscribing to All Notifications ===
=== SocketService: All notifications subscribed ===
```

#### 3. ตรวจสอบ Event Reception
```dart
// ตรวจสอบใน logs
=== SocketService: New Group Chat Message Received ===
=== SocketService: New Direct Message Received ===
```

#### 4. ตรวจสอบ Background Service Detection
```dart
// ตรวจสอบใน logs
=== SocketService: Is in background service: true ===
```

## 📝 ข้อมูลการทดสอบ

### ข้อมูลสำหรับแชทกลุ่ม:
```json
{
  "roomId": "room_123",
  "roomName": "กลุ่มทดสอบ",
  "senderName": "ผู้ใช้ทดสอบ",
  "message": "สวัสดีครับ นี่คือข้อความทดสอบ",
  "unreadCount": 1
}
```

### ข้อมูลสำหรับ Direct Message:
```json
{
  "senderId": "user_456",
  "senderName": "ผู้ใช้ส่วนตัว",
  "message": "สวัสดีครับ นี่คือข้อความส่วนตัว",
  "unreadCount": 1
}
```

## 🚀 การใช้งาน

### การเรียกใช้ในแอป:
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

## ✅ ผลลัพธ์ที่คาดหวัง

1. **การแจ้งเตือนแชทกลุ่ม**: แสดงชื่อกลุ่มและชื่อผู้ส่งพร้อมข้อความ
2. **การแจ้งเตือน Direct Message**: แสดงชื่อผู้ส่งและข้อความ (ตัดข้อความยาว)
3. **Payload ที่ถูกต้อง**: ข้อมูลครบถ้วนสำหรับการนำทางไปยังหน้าที่เหมาะสม
4. **การทำงานใน Background**: แจ้งเตือนได้แม้ว่าแอปจะไม่ได้เปิดอยู่
5. **การทำงานใน Foreground**: แจ้งเตือนได้เมื่อแอปเปิดอยู่ 