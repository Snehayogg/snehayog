import express from 'express';
import Feedback from '../models/Feedback.js';

const router = express.Router();

// Submit feedback
router.post('/submit', async (req, res) => {
  try {
    const { rating, comments, userEmail, userId } = req.body;

    // Validate required fields
    if (!rating || rating < 1 || rating > 5) {
      return res.status(400).json({
        success: false,
        error: 'Rating is required and must be between 1 and 5'
      });
    }

    if (!userEmail || !userEmail.trim()) {
      return res.status(400).json({
        success: false,
        error: 'User email is required'
      });
    }

    // Create feedback entry
    const feedback = new Feedback({
      rating: parseInt(rating),
      comments: comments ? comments.trim() : '',
      userEmail: userEmail.trim().toLowerCase(),
      userId: userId ? userId.trim() : null,
      userAgent: req.get('User-Agent') || '',
      ipAddress: req.ip || req.connection.remoteAddress || ''
    });

    await feedback.save();

    res.status(201).json({
      success: true,
      message: 'Feedback submitted successfully',
      feedbackId: feedback._id
    });
  } catch (error) {
    console.error('Error submitting feedback:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit feedback'
    });
  }
});

// Get feedback statistics (public endpoint)
router.get('/stats', async (req, res) => {
  try {
    const stats = await Feedback.getStats();
    
    res.json({
      success: true,
      stats: stats
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
