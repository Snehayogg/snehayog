import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import Video from '../../models/Video.js';
import { checkInterestCoverage, getAvailableCategories } from '../../config/categoryMap.js';

const router = express.Router();

// GET /ads/validate/interests - Check if interests have matching videos
router.get('/validate/interests', asyncHandler(async (req, res) => {
  const { interests } = req.query;
  
  if (!interests) {
    return res.status(400).json({ 
      error: 'interests parameter required',
      example: '/ads/validate/interests?interests=ai,travel,food'
    });
  }

  const interestList = interests.split(',').map(i => i.trim());
  const results = [];

  for (const interest of interestList) {
    const coverage = await checkInterestCoverage(interest, Video);
    results.push({
      interest,
      ...coverage
    });
  }

  const hasAllCoverage = results.every(r => r.hasVideos);
  const warningCount = results.filter(r => !r.hasVideos).length;

  res.json({
    success: true,
    hasAllCoverage,
    warningCount,
    results,
    recommendation: hasAllCoverage 
      ? '✅ All interests have matching videos!'
      : `⚠️ ${warningCount} interest(s) have no matching videos. Your ad might show less frequently.`
  });
}));

// GET /ads/available-categories - Get all available video categories
router.get('/available-categories', asyncHandler(async (req, res) => {
  const categories = await getAvailableCategories(Video);
  
  res.json({
    success: true,
    count: categories.length,
    categories: categories.sort(),
    message: categories.length > 0 
      ? `Found ${categories.length} video categories`
      : 'No videos with categories found. Upload videos with categories first.'
  });
}));

// GET /ads/suggest-interests - Suggest interests based on available videos
router.get('/suggest-interests', asyncHandler(async (req, res) => {
  const { category } = req.query;
  
  const categories = await getAvailableCategories(Video);
  
  if (!category) {
    // Return top categories as suggestions
    res.json({
      success: true,
      suggestions: categories.slice(0, 10),
      message: 'Popular categories with videos'
    });
    return;
  }

  // Find related categories
  const categoryLower = category.toLowerCase();
  const related = categories.filter(c => 
    c.toLowerCase().includes(categoryLower) || 
    categoryLower.includes(c.toLowerCase())
  );

  res.json({
    success: true,
    category,
    relatedCategories: related,
    allCategories: categories,
    message: related.length > 0 
      ? `Found ${related.length} related categories`
      : 'No related categories found'
  });
}));

export default router;

