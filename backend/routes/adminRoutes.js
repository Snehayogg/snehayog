import express from 'express';
import Feedback from '../models/Feedback.js';

const router = express.Router();

// Get all feedback for admin
router.get('/feedback', async (req, res) => {
  try {
    const feedback = await Feedback.find()
      .sort({ createdAt: -1 })
      .limit(100); // Limit to recent 100 feedback entries

    res.json({
      success: true,
      feedback: feedback,
      total: feedback.length
    });
  } catch (error) {
    console.error('Error fetching feedback:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch feedback'
    });
  }
});

// Get specific feedback by ID
router.get('/feedback/:id', async (req, res) => {
  try {
    const feedback = await Feedback.findById(req.params.id);
    
    if (!feedback) {
      return res.status(404).json({
        success: false,
        error: 'Feedback not found'
      });
    }

    res.json({
      success: true,
      feedback: feedback
    });
  } catch (error) {
    console.error('Error fetching feedback details:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch feedback details'
    });
  }
});

// Mark feedback as read
router.put('/feedback/:id/read', async (req, res) => {
  try {
    const feedback = await Feedback.findByIdAndUpdate(
      req.params.id,
      { isRead: true, readAt: new Date() },
      { new: true }
    );

    if (!feedback) {
      return res.status(404).json({
        success: false,
        error: 'Feedback not found'
      });
    }

    res.json({
      success: true,
      message: 'Feedback marked as read',
      feedback: feedback
    });
  } catch (error) {
    console.error('Error marking feedback as read:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to mark feedback as read'
    });
  }
});

// Reply to feedback
router.post('/feedback/:id/reply', async (req, res) => {
  try {
    const { reply } = req.body;
    
    if (!reply || reply.trim().length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Reply content is required'
      });
    }

    const feedback = await Feedback.findByIdAndUpdate(
      req.params.id,
      { 
        adminReply: reply.trim(),
        repliedAt: new Date(),
        isReplied: true
      },
      { new: true }
    );

    if (!feedback) {
      return res.status(404).json({
        success: false,
        error: 'Feedback not found'
      });
    }

    res.json({
      success: true,
      message: 'Reply sent successfully',
      feedback: feedback
    });
  } catch (error) {
    console.error('Error replying to feedback:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to send reply'
    });
  }
});

// Export feedback as CSV
router.get('/feedback/export', async (req, res) => {
  try {
    const feedback = await Feedback.find()
      .sort({ createdAt: -1 })
      .select('rating comments userEmail createdAt isRead isReplied adminReply');

    // Create CSV content
    const csvHeader = 'Rating,User Email,Comments,Date,Read,Replied,Admin Reply\n';
    const csvRows = feedback.map(fb => {
      const rating = fb.rating || 0;
      const userEmail = (fb.userEmail || 'Anonymous').replace(/,/g, ';');
      const comments = (fb.comments || '').replace(/,/g, ';').replace(/\n/g, ' ');
      const date = new Date(fb.createdAt).toISOString();
      const isRead = fb.isRead ? 'Yes' : 'No';
      const isReplied = fb.isReplied ? 'Yes' : 'No';
      const adminReply = (fb.adminReply || '').replace(/,/g, ';').replace(/\n/g, ' ');
      
      return `${rating},${userEmail},"${comments}",${date},${isRead},${isReplied},"${adminReply}"`;
    }).join('\n');

    const csvContent = csvHeader + csvRows;

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', `attachment; filename="feedback-export-${new Date().toISOString().split('T')[0]}.csv"`);
    res.send(csvContent);
  } catch (error) {
    console.error('Error exporting feedback:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to export feedback'
    });
  }
});

// Get feedback statistics
router.get('/feedback/stats', async (req, res) => {
  try {
    const total = await Feedback.countDocuments();
    const unread = await Feedback.countDocuments({ isRead: false });
    const replied = await Feedback.countDocuments({ isReplied: true });
    
    // Average rating
    const avgRatingResult = await Feedback.aggregate([
      { $group: { _id: null, avgRating: { $avg: '$rating' } } }
    ]);
    const avgRating = avgRatingResult.length > 0 ? avgRatingResult[0].avgRating : 0;

    // Rating distribution
    const ratingDistribution = await Feedback.aggregate([
      { $group: { _id: '$rating', count: { $sum: 1 } } },
      { $sort: { _id: -1 } }
    ]);

    res.json({
      success: true,
      stats: {
        total,
        unread,
        replied,
        avgRating: Math.round(avgRating * 10) / 10,
        ratingDistribution
      }
    });
  } catch (error) {
    console.error('Error fetching feedback stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch feedback statistics'
    });
  }
});

export default router;
