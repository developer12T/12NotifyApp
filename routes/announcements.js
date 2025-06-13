const express = require('express');
const router = express.Router();
const Announcement = require('../models/Announcement');
const { findUserByEmployeeId } = require('../services/ldapServices');

// Store announcement subscribers
const announcementSubscribers = new Set();

// Get all announcements with pagination
router.get('/', async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;

    const announcements = await Announcement.find()
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate('createdBy', 'employeeID fullNameThai department');

    const totalAnnouncements = await Announcement.countDocuments();
    const totalPages = Math.ceil(totalAnnouncements / limit);

    res.json({
      announcements,
      pagination: {
        currentPage: page,
        totalPages,
        totalItems: totalAnnouncements,
        itemsPerPage: limit
      }
    });
  } catch (error) {
    console.error('Error fetching announcements:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get announcement by ID
router.get('/:id', async (req, res) => {
  try {
    const announcement = await Announcement.findById(req.params.id)
      .populate('createdBy', 'employeeID fullNameThai department');

    if (!announcement) {
      return res.status(404).json({ error: 'Announcement not found' });
    }

    res.json(announcement);
  } catch (error) {
    console.error('Error fetching announcement:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create new announcement
router.post('/', async (req, res) => {
  try {
    const { title, content, createdBy, department, imageUrl } = req.body;

    if (!title || !content) {
      return res.status(400).json({ error: 'Title and content are required' });
    }

    // Get user details if createdBy is provided
    let userDetails = null;
    if (createdBy) {
      const userResult = await findUserByEmployeeId(createdBy);
      if (userResult.success && userResult.user) {
        userDetails = userResult.user;
      }
    }

    const announcement = new Announcement({
      title,
      content,
      createdBy: userDetails ? {
        employeeID: userDetails.employeeID,
        fullNameThai: userDetails.fullNameThai,
        department: userDetails.department
      } : createdBy,
      department: department || (userDetails ? userDetails.department : 'General'),
      imageUrl: imageUrl || null,
      createdAt: new Date(),
      updatedAt: new Date()
    });

    await announcement.save();

    // Emit to all announcement subscribers via socket
    const io = req.app.get('io');
    if (io) {
      announcementSubscribers.forEach(socketId => {
        io.to(socketId).emit('newAnnouncement', announcement);
      });
      console.log(`New announcement sent to ${announcementSubscribers.size} subscribers`);
    }

    res.status(201).json({
      success: true,
      announcement
    });
  } catch (error) {
    console.error('Error creating announcement:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update announcement
router.put('/:id', async (req, res) => {
  try {
    const { title, content, department, imageUrl } = req.body;

    const announcement = await Announcement.findById(req.params.id);
    if (!announcement) {
      return res.status(404).json({ error: 'Announcement not found' });
    }

    announcement.title = title || announcement.title;
    announcement.content = content || announcement.content;
    announcement.department = department || announcement.department;
    announcement.imageUrl = imageUrl !== undefined ? imageUrl : announcement.imageUrl;
    announcement.updatedAt = new Date();

    await announcement.save();

    res.json({
      success: true,
      announcement
    });
  } catch (error) {
    console.error('Error updating announcement:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete announcement
router.delete('/:id', async (req, res) => {
  try {
    const announcement = await Announcement.findByIdAndDelete(req.params.id);
    
    if (!announcement) {
      return res.status(404).json({ error: 'Announcement not found' });
    }

    res.json({
      success: true,
      message: 'Announcement deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting announcement:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Function to add socket to announcement subscribers
const addAnnouncementSubscriber = (socketId) => {
  announcementSubscribers.add(socketId);
  console.log(`Socket ${socketId} subscribed to announcements`);
  console.log(`Total announcement subscribers: ${announcementSubscribers.size}`);
};

// Function to remove socket from announcement subscribers
const removeAnnouncementSubscriber = (socketId) => {
  announcementSubscribers.delete(socketId);
  console.log(`Socket ${socketId} unsubscribed from announcements`);
  console.log(`Total announcement subscribers: ${announcementSubscribers.size}`);
};

// Function to get announcement subscribers count
const getAnnouncementSubscribersCount = () => {
  return announcementSubscribers.size;
};

module.exports = {
  router,
  addAnnouncementSubscriber,
  removeAnnouncementSubscriber,
  getAnnouncementSubscribersCount
}; 