# Backend Server Setup Guide

## 🚀 การติดตั้ง Backend Server

### 1. ติดตั้ง Dependencies
```bash
npm install
```

### 2. สร้างไฟล์ .env
สร้างไฟล์ `.env` ในโฟลเดอร์ root และเพิ่ม:
```env
# Server Configuration
PORT=3000

# MongoDB Configuration
MONGODB_URI=mongodb://localhost:27017/chat_app

# Socket.IO Configuration
SOCKET_PATH=/chatio/socket.io/

# Environment
NODE_ENV=development
```

### 3. ติดตั้ง MongoDB
- ติดตั้ง MongoDB บนเครื่อง
- หรือใช้ MongoDB Atlas (cloud)

### 4. รัน Server
```bash
# Development mode
npm run dev

# Production mode
npm start
```

## 📡 Socket Events ที่รองรับ

### Direct Messages
- `subscribeDirectMessages` - สมัครรับ Direct Messages
- `unsubscribeDirectMessages` - ยกเลิกการสมัครรับ
- `sendDirectMessage` - ส่ง Direct Message
- `markDirectMessagesRead` - มาร์คข้อความเป็นอ่าน

### Chat Rooms
- `subscribeChatList` - สมัครรับรายการห้องแชท
- `joinRoom` - เข้าร่วมห้อง
- `leaveRoom` - ออกจากห้อง
- `sendMessage` - ส่งข้อความในห้อง
- `markMessagesRead` - มาร์คข้อความเป็นอ่าน

### User Management
- `userConnected` - ผู้ใช้เชื่อมต่อ

## 🔧 การทดสอบ

### Health Check
```bash
curl http://localhost:3000/health
```

### Socket Connection Test
ใช้ Socket.IO client หรือ Postman เพื่อทดสอบ events

## 📊 Monitoring

Server จะแสดง logs สำหรับ:
- การเชื่อมต่อ/ตัดการเชื่อมต่อ
- การส่งข้อความ
- การ subscribe/unsubscribe
- Errors และ warnings

## 🛠️ Troubleshooting

### ปัญหาที่พบบ่อย:
1. **MongoDB ไม่เชื่อมต่อ** - ตรวจสอบ MONGODB_URI
2. **Port ถูกใช้งาน** - เปลี่ยน PORT ใน .env
3. **CORS Error** - ตรวจสอบ CORS configuration

### Logs ที่สำคัญ:
- `User connected: [socketId]`
- `User [userId] subscribed to conversation: [conversationId]`
- `Direct message sent from [senderId] to [recipientId]`
- `Message sent to room [roomId]` 