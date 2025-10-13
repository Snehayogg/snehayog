/**
 * Category Relationship Map
 * यह map related categories को connect करता है
 * 
 * Example: अगर "AI" ad है लेकिन "AI" video नहीं,
 * तो "Technology" या "Programming" videos पर show हो सकता है
 */

export const CATEGORY_RELATIONSHIPS = {
  // Technology & AI Group
  'artificial intelligence': {
    primary: ['ai', 'machine learning', 'deep learning', 'neural networks'],
    related: ['technology', 'tech', 'programming', 'computer science', 'data science', 'robotics'],
    fallback: ['education', 'science', 'innovation']
  },
  'ai': {
    primary: ['artificial intelligence', 'machine learning', 'deep learning'],
    related: ['technology', 'tech', 'programming', 'data science'],
    fallback: ['education', 'science']
  },
  'technology': {
    primary: ['tech', 'gadgets', 'innovation'],
    related: ['artificial intelligence', 'programming', 'computer science', 'software', 'hardware'],
    fallback: ['education', 'business', 'science']
  },
  'programming': {
    primary: ['coding', 'software development', 'developer'],
    related: ['technology', 'computer science', 'artificial intelligence'],
    fallback: ['education', 'tech']
  },

  // Gaming Group
  'gaming': {
    primary: ['games', 'video games', 'esports'],
    related: ['pc gaming', 'console gaming', 'mobile gaming', 'streaming'],
    fallback: ['entertainment', 'technology']
  },
  'pc gaming': {
    primary: ['gaming', 'computer games'],
    related: ['console gaming', 'esports', 'streaming'],
    fallback: ['gaming', 'entertainment', 'technology']
  },
  'console gaming': {
    primary: ['gaming', 'playstation', 'xbox'],
    related: ['pc gaming', 'esports'],
    fallback: ['gaming', 'entertainment']
  },
  'mobile gaming': {
    primary: ['gaming', 'mobile games', 'android games'],
    related: ['casual gaming'],
    fallback: ['gaming', 'entertainment', 'mobile']
  },

  // Health & Fitness Group
  'fitness': {
    primary: ['health', 'workout', 'exercise', 'gym'],
    related: ['yoga', 'wellness', 'sports', 'nutrition'],
    fallback: ['lifestyle', 'health']
  },
  'yoga': {
    primary: ['meditation', 'wellness', 'mindfulness'],
    related: ['fitness', 'health', 'exercise'],
    fallback: ['lifestyle', 'health', 'spirituality']
  },
  'health': {
    primary: ['wellness', 'healthcare', 'medical'],
    related: ['fitness', 'nutrition', 'mental health'],
    fallback: ['lifestyle', 'education']
  },

  // Travel & Adventure Group
  'travel': {
    primary: ['tourism', 'vacation', 'trip'],
    related: ['adventure', 'explore', 'destinations', 'hotels', 'flights'],
    fallback: ['lifestyle', 'entertainment']
  },
  'tourism': {
    primary: ['travel', 'vacation', 'holiday'],
    related: ['adventure', 'destinations'],
    fallback: ['travel', 'lifestyle']
  },

  // Food & Cooking Group
  'food': {
    primary: ['cooking', 'recipe', 'cuisine'],
    related: ['restaurant', 'chef', 'baking', 'nutrition'],
    fallback: ['lifestyle', 'health']
  },
  'cooking': {
    primary: ['food', 'recipe', 'chef'],
    related: ['baking', 'cuisine'],
    fallback: ['food', 'lifestyle']
  },

  // Entertainment Group
  'entertainment': {
    primary: ['fun', 'comedy', 'music', 'movies'],
    related: ['gaming', 'streaming', 'shows'],
    fallback: ['lifestyle']
  },
  'music': {
    primary: ['songs', 'concert', 'band', 'artist'],
    related: ['entertainment', 'dance'],
    fallback: ['entertainment', 'art']
  },
  'movies': {
    primary: ['cinema', 'films', 'bollywood', 'hollywood'],
    related: ['entertainment', 'shows', 'streaming'],
    fallback: ['entertainment', 'art']
  },

  // Education Group
  'education': {
    primary: ['learning', 'tutorial', 'course', 'study'],
    related: ['technology', 'programming', 'science'],
    fallback: ['lifestyle']
  },
  'tutorial': {
    primary: ['education', 'learning', 'how-to'],
    related: ['programming', 'technology'],
    fallback: ['education']
  },

  // Business & Finance Group
  'business': {
    primary: ['entrepreneurship', 'startup', 'company'],
    related: ['finance', 'marketing', 'investment'],
    fallback: ['education', 'technology']
  },
  'finance': {
    primary: ['money', 'investment', 'stock market', 'trading'],
    related: ['business', 'economics'],
    fallback: ['business', 'education']
  },

  // Fashion & Beauty Group
  'fashion': {
    primary: ['style', 'clothing', 'trends'],
    related: ['beauty', 'lifestyle'],
    fallback: ['lifestyle', 'entertainment']
  },
  'beauty': {
    primary: ['makeup', 'skincare', 'cosmetics'],
    related: ['fashion', 'lifestyle'],
    fallback: ['lifestyle', 'health']
  },

  // Lifestyle Group
  'lifestyle': {
    primary: ['living', 'daily life', 'vlog'],
    related: ['fashion', 'food', 'travel', 'fitness'],
    fallback: ['entertainment']
  }
};

/**
 * Get related categories for a given interest
 */
export function getRelatedCategories(interest, level = 'all') {
  const interestLower = interest.toLowerCase().trim();
  const relationships = CATEGORY_RELATIONSHIPS[interestLower];
  
  if (!relationships) {
    // If no relationship defined, return the interest itself
    return [interestLower];
  }

  switch (level) {
    case 'primary':
      return [interestLower, ...relationships.primary];
    case 'related':
      return [interestLower, ...relationships.primary, ...relationships.related];
    case 'all':
      return [interestLower, ...relationships.primary, ...relationships.related, ...relationships.fallback];
    default:
      return [interestLower];
  }
}

/**
 * Calculate relevance between ad interest and video category
 */
export function calculateCategoryRelevance(adInterest, videoCategory) {
  const interestLower = adInterest.toLowerCase().trim();
  const categoryLower = videoCategory.toLowerCase().trim();

  // Exact match
  if (interestLower === categoryLower) {
    return { score: 100, level: 'exact' };
  }

  const relationships = CATEGORY_RELATIONSHIPS[interestLower];
  if (!relationships) {
    // No relationship defined - check partial match
    if (categoryLower.includes(interestLower) || interestLower.includes(categoryLower)) {
      return { score: 70, level: 'partial' };
    }
    return { score: 0, level: 'none' };
  }

  // Check primary relationships
  if (relationships.primary.includes(categoryLower)) {
    return { score: 90, level: 'primary' };
  }

  // Check related relationships
  if (relationships.related.includes(categoryLower)) {
    return { score: 60, level: 'related' };
  }

  // Check fallback relationships
  if (relationships.fallback.includes(categoryLower)) {
    return { score: 30, level: 'fallback' };
  }

  // Partial text match
  if (categoryLower.includes(interestLower) || interestLower.includes(categoryLower)) {
    return { score: 50, level: 'partial' };
  }

  return { score: 0, level: 'none' };
}

/**
 * Get available video categories from database
 */
export async function getAvailableCategories(Video) {
  try {
    const categories = await Video.distinct('category');
    return categories.filter(c => c && c.trim().length > 0);
  } catch (error) {
    console.error('Error getting available categories:', error);
    return [];
  }
}

/**
 * Check if interest has matching videos
 * Returns: { hasVideos: boolean, matchingCategories: [], suggestedCategories: [] }
 */
export async function checkInterestCoverage(interest, Video) {
  try {
    const interestLower = interest.toLowerCase().trim();
    const availableCategories = await getAvailableCategories(Video);
    
    if (availableCategories.length === 0) {
      return {
        hasVideos: false,
        matchingCategories: [],
        suggestedCategories: [],
        warning: 'No videos available in database'
      };
    }

    // Check for exact and related matches
    const matchingCategories = [];
    const relatedCategories = getRelatedCategories(interestLower, 'all');
    
    for (const category of availableCategories) {
      const categoryLower = category.toLowerCase();
      
      if (relatedCategories.includes(categoryLower)) {
        matchingCategories.push(category);
      }
    }

    if (matchingCategories.length > 0) {
      return {
        hasVideos: true,
        matchingCategories,
        suggestedCategories: [],
        message: `Found ${matchingCategories.length} matching categories`
      };
    }

    // No matches found - suggest popular categories
    return {
      hasVideos: false,
      matchingCategories: [],
      suggestedCategories: availableCategories.slice(0, 5),
      warning: `No videos found for "${interest}". Consider these popular categories: ${availableCategories.slice(0, 5).join(', ')}`
    };

  } catch (error) {
    console.error('Error checking interest coverage:', error);
    return {
      hasVideos: false,
      matchingCategories: [],
      suggestedCategories: [],
      error: error.message
    };
  }
}

export default {
  CATEGORY_RELATIONSHIPS,
  getRelatedCategories,
  calculateCategoryRelevance,
  getAvailableCategories,
  checkInterestCoverage
};

