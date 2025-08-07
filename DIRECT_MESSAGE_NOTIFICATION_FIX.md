# การแก้ไขปัญหาการแจ้งเตือน Direct Message

## 🎯 ปัญหา
การแจ้งเตือนสำหรับ Direct Message กำลังส่งไปให้ทุกคนในระบบ แทนที่จะส่งเฉพาะระหว่างผู้ส่งและผู้รับเท่านั้น

## 🔧 การแก้ไขที่ทำ

### 1. **แก้ไขการ Subscribe ใน Direct Message List Page**
**ไฟล์:** `lib/pages/direct_message_list_page.dart`

**การเปลี่ยนแปลง:**
- เปลี่ยนจาก `senderId` เป็น `employeeId` ในการ subscribe
- ปรับปรุงการตรวจสอบว่าเป็นข้อความสำหรับผู้ใช้ปัจจุบัน

```dart
// ก่อน
final subscriptionData = {
  'senderId': currentUserId,
  'recipientId': currentUserId,
};

// หลัง
final subscriptionData = {
  'employeeId': currentUserId,
  'recipientId': currentUserId,
};
```

### 2. **แก้ไขการ Subscribe ใน UnifiedSocketService**
**ไฟล์:** `lib/services/unified_socket_service.dart`

**การเปลี่ยนแปลง:**
- เปลี่ยนจาก `senderId` เป็น `employeeId` ในการ subscribe และ unsubscribe

```dart
// ก่อน
socket.emit('subscribeDirectMessages', {
  'senderId': senderId,
  'recipientId': recipientId,
  'conversationId': conversationId,
});

// หลัง
socket.emit('subscribeDirectMessages', {
  'employeeId': senderId,
  'recipientId': recipientId,
  'conversationId': conversationId,
});
```

### 3. **แก้ไขการ Subscribe ใน ApiService**
**ไฟล์:** `lib/services/api_service.dart`

**การเปลี่ยนแปลง:**
- เปลี่ยนจาก `senderId` เป็น `employeeId` ในการ subscribe

```dart
// ก่อน
final directMessageData = {
  'senderId': userId,
  'recipientId': userId,
};

// หลัง
final directMessageData = {
  'employeeId': userId,
  'recipientId': userId,
};
```

### 4. **เพิ่มการตรวจสอบใน SocketService**
**ไฟล์:** `lib/services/socket_service.dart`

**การเปลี่ยนแปลง:**
- เพิ่ม method `_getCurrentUserId()` เพื่อดึง User ID ของผู้ใช้ปัจจุบัน
- เพิ่มการตรวจสอบใน `_handleDirectMessageNotification()` และ `_handleGroupChatNotification()`

#### การตรวจสอบที่เพิ่ม:
1. **ตรวจสอบ User ID:** ตรวจสอบว่ามี User ID หรือไม่
2. **ตรวจสอบ Recipient:** ตรวจสอบว่า `recipientId` ตรงกับ `currentUserId` หรือไม่
3. **ตรวจสอบ Sender:** ตรวจสอบว่าไม่ใช่ข้อความที่เราส่งเอง

```dart
// ตรวจสอบว่าเป็นข้อความสำหรับผู้ใช้ปัจจุบันหรือไม่
final currentUserId = await _getCurrentUserId();
if (currentUserId == null) {
  print('=== SocketService: Current user ID not found, skipping notification ===');
  return;
}

// ตรวจสอบว่า recipientId ตรงกับ currentUserId หรือไม่
if (recipientId != currentUserId) {
  print('=== SocketService: Notification not for current user ===');
  print('Recipient ID: $recipientId');
  print('Current User ID: $currentUserId');
  print('=== SocketService: Skipping notification ===');
  return;
}

// ตรวจสอบว่าไม่ใช่ข้อความที่เราส่งเอง
if (senderId == currentUserId) {
  print('=== SocketService: Message sent by current user, skipping notification ===');
  return;
}
```

## 📊 ผลลัพธ์ที่คาดหวัง

### ก่อนการแก้ไข:
- A คุยกับ B
- C, D, E, F ได้รับการแจ้งเตือน (ไม่ถูกต้อง)

### หลังการแก้ไข:
- A คุยกับ B
- เฉพาะ B เท่านั้นที่ได้รับการแจ้งเตือน (ถูกต้อง)

## 🔍 การตรวจสอบ

### 1. **ตรวจสอบ Log:**
```
=== SocketService: Handling Direct Message Notification ===
Recipient ID: user_123
Current User ID: user_456
=== SocketService: Notification not for current user ===
=== SocketService: Skipping notification ===
```

### 2. **ตรวจสอบการ Subscribe:**
```
📡 Subscribing to Direct Messages:
   - Sender ID: user_123
   - Recipient ID: user_456
   - Conversation ID: user_123_user_456
```

## 🚀 การทดสอบ

1. **ทดสอบการส่งข้อความ:**
   - ส่งข้อความจาก User A ไปยัง User B
   - ตรวจสอบว่าเฉพาะ User B เท่านั้นที่ได้รับการแจ้งเตือน

2. **ทดสอบการส่งข้อความกลับ:**
   - ส่งข้อความจาก User B ไปยัง User A
   - ตรวจสอบว่าเฉพาะ User A เท่านั้นที่ได้รับการแจ้งเตือน

3. **ทดสอบการส่งข้อความให้ตัวเอง:**
   - ส่งข้อความให้ตัวเอง
   - ตรวจสอบว่าไม่มีการแจ้งเตือน

## 📝 หมายเหตุ

- การแก้ไขนี้จะทำให้การแจ้งเตือน Direct Message ทำงานได้อย่างถูกต้อง
- การตรวจสอบจะทำทั้งในฝั่ง Frontend และ Backend
- Log จะแสดงรายละเอียดการตรวจสอบเพื่อการ Debug 