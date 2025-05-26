// Handle notifications
socket.on('sendNotification', (data) => {
  console.log('Received notification:', data); // Debug log
  
  if (Array.isArray(data.roomId)) {
    // Send to multiple rooms
    data.roomId.forEach(roomId => {
      console.log(`Broadcasting to room: ${roomId}`); // Debug log
      io.to(roomId).emit('newNotification', {
        roomId: roomId,
        message: data.message,
        sender: data.sender,
        timestamp: new Date()
      });
    });
  } else {
    // Send to single room
    console.log(`Broadcasting to room: ${data.roomId}`); // Debug log
    io.to(data.roomId).emit('newNotification', {
      roomId: data.roomId,
      message: data.message,
      sender: data.sender,
      timestamp: new Date()
    });
  }
});

// Add connection status logging
socket.on('connect', () => {
  console.log('Client connected:', socket.id);
});

socket.on('disconnect', () => {
  console.log('Client disconnected:', socket.id);
});

socket.on('error', (error) => {
  console.error('Socket error:', error);
});

// API endpoint for sending notifications
app.post('/api/notifications/send', async (req, res) => {
  try {
    const { roomId, message, adminId } = req.body;
    
    // Check if roomId is array or single value
    const roomIds = Array.isArray(roomId) ? roomId : [roomId];
    
    const notifications = [];
    
    // Create notifications for each room
    for (const roomId of roomIds) {
      const notification = new Notification({
        room: roomId,
        sender: adminId,
        message: message,
        isRead: false,
        readBy: []
      });
      
      await notification.save();
      notifications.push(notification);
      
      // Emit socket event for each room
      io.to(roomId).emit('newNotification', {
        roomId: roomId,
        message: message,
        sender: 'admin',
        timestamp: notification.createdAt
      });
    }

    res.json({
      message: 'Notifications sent successfully',
      notifications: notifications
    });
  } catch (error) {
    console.error('Error sending notifications:', error);
    res.status(500).json({ error: 'Failed to send notifications' });
  }
});

// Handle room joining
socket.on('joinRoom', (data) => {
  console.log('Client joining room:', data);
  const { roomId, userId } = data;
  
  if (!roomId || !userId) {
    socket.emit('roomJoined', { success: false, error: 'Missing roomId or userId' });
    return;
  }

  try {
    // Leave any existing rooms first
    const rooms = Array.from(socket.rooms);
    rooms.forEach(room => {
      if (room !== socket.id) {
        socket.leave(room);
      }
    });

    // Join the new room
    socket.join(roomId);
    console.log(`Client ${socket.id} joined room ${roomId}`);
    socket.emit('roomJoined', { success: true, roomId });
  } catch (error) {
    console.error('Error joining room:', error);
    socket.emit('roomJoined', { success: false, error: error.message });
  }
});

// Handle message broadcasting
socket.on('messageBroadcast', (data) => {
  console.log('Received message broadcast:', data);
  const { roomId, message, employeeId, timestamp } = data;

  if (!roomId || !message) {
    console.error('Invalid message broadcast data:', data);
    return;
  }

  try {
    // Broadcast to all clients in the room except sender
    socket.to(roomId).emit('newMessage', {
      room: roomId,
      message: message,
      sender: {
        employeeID: employeeId,
        // You might want to fetch user details from database here
      },
      timestamp: timestamp || new Date().toISOString(),
      isRead: false
    });

    // Also emit to sender for confirmation
    socket.emit('newMessage', {
      room: roomId,
      message: message,
      sender: {
        employeeID: employeeId,
      },
      timestamp: timestamp || new Date().toISOString(),
      isRead: true
    });

    console.log(`Message broadcasted to room ${roomId}`);
  } catch (error) {
    console.error('Error broadcasting message:', error);
  }
});

// Handle room leaving
socket.on('leaveRoom', (data) => {
  console.log('Client leaving room:', data);
  const { roomId } = data;
  
  if (!roomId) {
    socket.emit('roomLeft', { success: false, error: 'Missing roomId' });
    return;
  }

  try {
    socket.leave(roomId);
    console.log(`Client ${socket.id} left room ${roomId}`);
    socket.emit('roomLeft', { success: true, roomId });
  } catch (error) {
    console.error('Error leaving room:', error);
    socket.emit('roomLeft', { success: false, error: error.message });
  }
});

// Handle leaving all rooms
socket.on('leaveAll', () => {
  console.log('Client leaving all rooms');
  try {
    const rooms = Array.from(socket.rooms);
    rooms.forEach(room => {
      if (room !== socket.id) {
        socket.leave(room);
      }
    });
    console.log(`Client ${socket.id} left all rooms`);
    socket.emit('leftAllRooms', { success: true });
  } catch (error) {
    console.error('Error leaving all rooms:', error);
    socket.emit('leftAllRooms', { success: false, error: error.message });
  }
}); 