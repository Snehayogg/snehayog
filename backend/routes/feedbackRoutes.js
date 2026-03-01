import express from 'express';
import Feedback from '../models/Feedback.js';

const router = express.Router();

// Submit feedback
router.post('/submit', async (req, res) => {
  try {
    const { rating, comments, userEmail, userId, type } = req.body;

    console.log('📝 Feedback submission attempt:', { 
      rating, 
      userEmail, 
      userId, 
      type,
      commentsLength: comments?.length 
    });

    // Validate required fields
    if (!rating || rating < 1 || rating > 5) {
      console.log('⚠️ Invalid rating:', rating);
      return res.status(400).json({
        success: false,
        error: 'Rating must be between 1 and 5'
      });
    }

    if (!userEmail || !userEmail.trim()) {
      console.log('⚠️ Missing user email');
      return res.status(400).json({
        success: false,
        error: 'User email is required'
      });
    }

    // Create feedback entry
    const feedback = new Feedback({
      rating,
      comments: comments || '',
      type: type || 'general',
      userEmail: userEmail.trim().toLowerCase(),
      userId: userId || null,
      userAgent: req.headers['user-agent'] || '',
      ipAddress: req.ip || req.connection?.remoteAddress || ''
    });

    await feedback.save();
    console.log('✅ Feedback saved successfully:', feedback._id);

    res.status(201).json({
      success: true,
      message: 'Feedback submitted successfully',
      feedbackId: feedback._id
    });
  } catch (error) {
    console.error('❌ Error submitting feedback:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to submit feedback',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
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
