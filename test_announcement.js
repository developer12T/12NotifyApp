const io = require('socket.io-client');

// Connect to the server
const socket = io('http://localhost:3000', {
  transports: ['websocket']
});

console.log('Connecting to server...');

socket.on('connect', () => {
  console.log('Connected to server with ID:', socket.id);
  
  // Subscribe to announcements
  socket.emit('subscribeAnnouncements', {});
  
  // Listen for subscription confirmation
  socket.on('announcementsSubscribed', (data) => {
    console.log('Successfully subscribed to announcements:', data);
    
    // Send a test announcement after 2 seconds
    setTimeout(() => {
      console.log('Sending test announcement...');
      socket.emit('sendAnnouncement', {
        title: 'ประกาศทดสอบเรียลไทม์',
        content: 'นี่คือการทดสอบระบบประกาศแบบเรียลไทม์ ประกาศนี้จะปรากฏทันทีในแอปพลิเคชัน',
        createdBy: 'ผู้ทดสอบระบบ',
        department: 'IT',
        imageUrl: null
      });
    }, 2000);
  });
  
  // Listen for new announcements
  socket.on('newAnnouncement', (data) => {
    console.log('Received new announcement:', data);
  });
  
  // Listen for announcement sent confirmation
  socket.on('announcementSent', (data) => {
    console.log('Announcement sent successfully:', data);
    
    // Disconnect after sending
    setTimeout(() => {
      console.log('Disconnecting...');
      socket.disconnect();
      process.exit(0);
    }, 1000);
  });
  
  // Listen for errors
  socket.on('announcementError', (data) => {
    console.error('Announcement error:', data);
  });
});

socket.on('disconnect', () => {
  console.log('Disconnected from server');
});

socket.on('connect_error', (error) => {
  console.error('Connection error:', error);
});

// Handle process termination
process.on('SIGINT', () => {
  console.log('Disconnecting...');
  socket.disconnect();
  process.exit(0);
}); 