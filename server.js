const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Serve uploaded files
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Socket connection handling
io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  // Join DirectMessage room
  socket.on('joinDirectMessageRoom', async (data) => {
    try {
      const { employeeId, recipientId } = data;
      if (!employeeId || !recipientId) {
        throw new Error('Employee ID and Recipient ID are required');
      }

      // สร้าง room ID สำหรับ direct message
      const [id1, id2] = [employeeId, recipientId].sort();
      const directMessageRoomId = `dm-${id1}-${id2}`;

      socket.join(directMessageRoomId);
      console.log(`User ${employeeId} joined DirectMessage room: ${directMessageRoomId}`);
      
      // Acknowledge successful join
      socket.emit('directMessageRoomJoined', { 
        roomId: directMessageRoomId, 
        success: true,
        participants: [employeeId, recipientId]
      });

      // Notify other participant
      socket.to(directMessageRoomId).emit('userJoinedDirectMessage', {
        roomId: directMessageRoomId,
        userId: employeeId,
        timestamp: new Date()
      });
    } catch (error) {
      console.error('Error joining DirectMessage room:', error);
      socket.emit('directMessageRoomJoined', { 
        success: false, 
        error: error.message 
      });
    }
  });

  // Handle disconnection
  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
  });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
}); 