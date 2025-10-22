import express from 'express';
import { verifyToken } from '../utils/verifytoken.js';
import AdCreative from '../models/AdCreative.js';
import Comment from '../models/Comment.js';

const router = express.Router();

// **GET AD COMMENTS: Fetch comments for a specific ad**
router.get('/:adId', verifyToken, async (req, res) => {
  try {
    const { adId } = req.params;
    const { page = 1, limit = 20 } = req.query;

    // Verify ad exists and is active
    const ad = await AdCreative.findById(adId).populate('campaign');
    if (!ad) {
      return res.status(404).json({
        success: false,
        message: 'Ad not found'
      });
    }

    if (!ad.isActive) {
      return res.status(400).json({
        success: false,
        message: 'Ad is not active'
      });
    }

    // Get comments for this ad
    const comments = await Comment.find({ 
      targetType: 'ad',
      targetId: adId 
    })
    .populate('user', 'name profilePic')
    .sort({ createdAt: -1 })
    .limit(limit * 1)
    .skip((page - 1) * limit);

    const totalComments = await Comment.countDocuments({ 
      targetType: 'ad',
      targetId: adId 
    });

    res.json({
      success: true,
      comments,
      pagination: {
        currentPage: parseInt(page),
        totalPages: Math.ceil(totalComments / limit),
        totalComments,
        hasNextPage: page * limit < totalComments,
        hasPrevPage: page > 1
      }
    });
  } catch (error) {
    console.error('❌ Error fetching ad comments:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch ad comments',
      error: error.message
    });
  }
});

// **POST AD COMMENT: Add comment to an ad**
router.post('/:adId', verifyToken, async (req, res) => {
  try {
    const { adId } = req.params;
    const { content } = req.body;
    const userId = req.user.id;

    // Validate input
    if (!content || content.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Comment content is required'
      });
    }

    if (content.length > 500) {
      return res.status(400).json({
        success: false,
        message: 'Comment too long (max 500 characters)'
      });
    }

    // Verify ad exists and is active
    const ad = await AdCreative.findById(adId).populate('campaign');
    if (!ad) {
      return res.status(404).json({
        success: false,
        message: 'Ad not found'
      });
    }

    if (!ad.isActive) {
      return res.status(400).json({
        success: false,
        message: 'Ad is not active'
      });
    }

    // Create comment
    const comment = new Comment({
      content: content.trim(),
      user: userId,
      targetType: 'ad',
      targetId: adId
    });

    await comment.save();
    await comment.populate('user', 'name profilePic');

    // Update ad comment count
    ad.comments = (ad.comments || 0) + 1;
    await ad.save();

    res.status(201).json({
      success: true,
      message: 'Comment added successfully',
      comment
    });
  } catch (error) {
    console.error('❌ Error adding ad comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add comment',
      error: error.message
    });
  }
});

// **DELETE AD COMMENT: Delete a comment (only by comment author or ad owner)**
router.delete('/:adId/:commentId', verifyToken, async (req, res) => {
  try {
    const { adId, commentId } = req.params;
    const userId = req.user.id;

    // Find comment
    const comment = await Comment.findById(commentId);
    if (!comment) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }

    // Verify comment belongs to this ad
    if (comment.targetType !== 'ad' || comment.targetId !== adId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this ad'
      });
    }

    // Check if user can delete (comment author or ad owner)
    const ad = await AdCreative.findById(adId).populate('campaign');
    const isCommentAuthor = comment.user.toString() === userId;
    const isAdOwner = ad?.campaign?.advertiser?.toString() === userId;

    if (!isCommentAuthor && !isAdOwner) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this comment'
      });
    }

    // Delete comment
    await Comment.findByIdAndDelete(commentId);

    // Update ad comment count
    if (ad) {
      ad.comments = Math.max((ad.comments || 1) - 1, 0);
      await ad.save();
    }

    res.json({
      success: true,
      message: 'Comment deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting ad comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete comment',
      error: error.message
    });
  }
});

// **LIKE AD COMMENT: Like/unlike a comment**
router.post('/:adId/:commentId/like', verifyToken, async (req, res) => {
  try {
    const { adId, commentId } = req.params;
    const userId = req.user.id;

    // Find comment
    const comment = await Comment.findById(commentId);
    if (!comment) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }

    // Verify comment belongs to this ad
    if (comment.targetType !== 'ad' || comment.targetId !== adId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this ad'
      });
    }

    // Toggle like
    const isLiked = comment.likedBy.includes(userId);
    if (isLiked) {
      comment.likedBy = comment.likedBy.filter(id => id.toString() !== userId);
      comment.likes = Math.max(comment.likes - 1, 0);
    } else {
      comment.likedBy.push(userId);
      comment.likes += 1;
    }

    await comment.save();

    res.json({
      success: true,
      message: isLiked ? 'Comment unliked' : 'Comment liked',
      comment
    });
  } catch (error) {
    console.error('❌ Error liking ad comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to like comment',
      error: error.message
    });
  }
});

export default router;
