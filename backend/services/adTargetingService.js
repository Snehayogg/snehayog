import AdCreative from '../models/AdCreative.js';
import AdCampaign from '../models/AdCampaign.js';

/**
 * **AD TARGETING SERVICE**
 * Handles intelligent ad-video matching based on interests and categories
 * with fallback system for limited content
 */
class AdTargetingService {
  
  // **TARGETING CATEGORIES**
  static CATEGORY_MAPPING = {
    'yoga': ['yoga', 'meditation', 'wellness', 'fitness', 'mindfulness', 'spiritual', 'health'],
    'fitness': ['fitness', 'workout', 'exercise', 'gym', 'training', 'strength', 'cardio'],
    'cooking': ['cooking', 'recipe', 'food', 'kitchen', 'chef', 'baking', 'nutrition'],
    'education': ['education', 'learning', 'tutorial', 'course', 'study', 'knowledge', 'skill'],
    'entertainment': ['entertainment', 'fun', 'comedy', 'music', 'dance', 'art', 'creative'],
    'lifestyle': ['lifestyle', 'fashion', 'beauty', 'travel', 'home', 'decor', 'tips'],
    'technology': ['technology', 'tech', 'gadgets', 'software', 'programming', 'innovation'],
    'business': ['business', 'entrepreneur', 'finance', 'marketing', 'startup', 'career'],
    'sports': ['sports', 'football', 'cricket', 'basketball', 'tennis', 'athletics'],
    'travel': ['travel', 'tourism', 'adventure', 'exploration', 'vacation', 'places'],
  };

  // **INTEREST KEYWORDS**
  static INTEREST_KEYWORDS = {
    'health_wellness': ['health', 'wellness', 'medical', 'doctor', 'hospital', 'medicine', 'therapy'],
    'fitness_sports': ['fitness', 'sports', 'gym', 'workout', 'training', 'athlete', 'exercise'],
    'food_cooking': ['food', 'cooking', 'recipe', 'restaurant', 'chef', 'kitchen', 'nutrition'],
    'education_learning': ['education', 'school', 'college', 'university', 'learning', 'study', 'course'],
    'entertainment_media': ['entertainment', 'movie', 'music', 'dance', 'comedy', 'fun', 'party'],
    'technology_gadgets': ['technology', 'tech', 'gadgets', 'smartphone', 'computer', 'software'],
    'fashion_beauty': ['fashion', 'beauty', 'style', 'makeup', 'clothing', 'shopping', 'trends'],
    'travel_tourism': ['travel', 'tourism', 'vacation', 'adventure', 'exploration', 'places'],
    'business_finance': ['business', 'finance', 'money', 'investment', 'entrepreneur', 'startup'],
    'lifestyle_home': ['lifestyle', 'home', 'decor', 'interior', 'family', 'parenting', 'tips'],
  };

  /**
   * **GET TARGETED ADS FOR VIDEO**
   * Returns ads that match the video's category and interests
   */
  static async getTargetedAdsForVideo(videoData, options = {}) {
    const {
      limit = 3,
      useFallback = true,
      adType = 'banner'
    } = options;

    try {
      console.log('🎯 AdTargetingService: Getting targeted ads for video:', videoData.id);
      
      // Extract video categories and interests
      const videoCategories = this.extractVideoCategories(videoData);
      const videoInterests = this.extractVideoInterests(videoData);
      
      console.log('🎯 Video categories:', videoCategories);
      console.log('🎯 Video interests:', videoInterests);
      
      // Try to get targeted ads first
      const targetedAds = await this.getTargetedAds({
        categories: videoCategories,
        interests: videoInterests,
        limit,
        adType
      });
      
      if (targetedAds.length > 0) {
        console.log(`✅ Found ${targetedAds.length} targeted ads`);
        return targetedAds;
      }
      
      // Fallback: Get any available ads if no targeted ads found
      if (useFallback) {
        console.log('🔄 No targeted ads found, using fallback system');
        const fallbackAds = await this.getFallbackAds({ limit, adType });
        console.log(`✅ Found ${fallbackAds.length} fallback ads`);
        return fallbackAds;
      }
      
      return [];
    } catch (error) {
      console.error('❌ Error getting targeted ads:', error);
      return [];
    }
  }

  /**
   * **GET TARGETED ADS BY CATEGORY**
   * Returns ads that match specific categories
   */
  static async getTargetedAdsByCategory(categories, options = {}) {
    const { limit = 5, adType = 'banner' } = options;
    
    try {
      console.log('🎯 Getting targeted ads for categories:', categories);
      
      const ads = await AdCreative.aggregate([
        {
          $match: {
            adType: adType,
            isActive: true,
            reviewStatus: 'approved'
          }
        },
        {
          $lookup: {
            from: 'adcampaigns',
            localField: 'campaignId',
            foreignField: '_id',
            as: 'campaign'
          }
        },
        {
          $unwind: '$campaign'
        },
        {
          $match: {
            'campaign.status': 'active',
            'campaign.startDate': { $lte: new Date() },
            'campaign.endDate': { $gte: new Date() }
          }
        },
        {
          $addFields: {
            targetingScore: {
              $add: [
                {
                  $size: {
                    $setIntersection: [
                      categories,
                      { $ifNull: ['$campaign.target.interests', []] }
                    ]
                  }
                },
                {
                  $size: {
                    $setIntersection: [
                      categories,
                      { $ifNull: ['$campaign.target.locations', []] }
                    ]
                  }
                }
              ]
            }
          }
        },
        {
          $match: {
            targetingScore: { $gt: 0 }
          }
        },
        {
          $sort: { targetingScore: -1, impressions: -1 }
        },
        {
          $limit: limit
        }
      ]);
      
      return this.transformAdsForFrontend(ads);
    } catch (error) {
      console.error('❌ Error getting targeted ads by category:', error);
      return [];
    }
  }

  /**
   * **GET TARGETED ADS BY INTERESTS**
   * Returns ads that match specific interests
   */
  static async getTargetedAdsByInterests(interests, options = {}) {
    const { limit = 5, adType = 'banner' } = options;
    
    try {
      console.log('🎯 Getting targeted ads for interests:', interests);
      
      const ads = await AdCreative.aggregate([
        {
          $match: {
            adType: adType,
            isActive: true,
            reviewStatus: 'approved'
          }
        },
        {
          $lookup: {
            from: 'adcampaigns',
            localField: 'campaignId',
            foreignField: '_id',
            as: 'campaign'
          }
        },
        {
          $unwind: '$campaign'
        },
        {
          $match: {
            'campaign.status': 'active',
            'campaign.startDate': { $lte: new Date() },
            'campaign.endDate': { $gte: new Date() }
          }
        },
        {
          $addFields: {
            targetingScore: {
              $size: {
                $setIntersection: [
                  interests,
                  { $ifNull: ['$campaign.target.interests', []] }
                ]
              }
            }
          }
        },
        {
          $match: {
            targetingScore: { $gt: 0 }
          }
        },
        {
          $sort: { targetingScore: -1, impressions: -1 }
        },
        {
          $limit: limit
        }
      ]);
      
      return this.transformAdsForFrontend(ads);
    } catch (error) {
      console.error('❌ Error getting targeted ads by interests:', error);
      return [];
    }
  }

  /**
   * **GET TARGETED ADS**
   * Fetches ads that match the specified categories and interests
   */
  static async getTargetedAds({ categories, interests, limit, adType }) {
    try {
      const ads = await AdCreative.aggregate([
        {
          $match: {
            adType: adType,
            isActive: true,
            reviewStatus: 'approved'
          }
        },
        {
          $lookup: {
            from: 'adcampaigns',
            localField: 'campaignId',
            foreignField: '_id',
            as: 'campaign'
          }
        },
        {
          $unwind: '$campaign'
        },
        {
          $match: {
            'campaign.status': 'active',
            'campaign.startDate': { $lte: new Date() },
            'campaign.endDate': { $gte: new Date() }
          }
        },
        {
          $addFields: {
            targetingScore: {
              $add: [
                {
                  $size: {
                    $setIntersection: [
                      categories,
                      { $ifNull: ['$campaign.target.interests', []] }
                    ]
                  }
                },
                {
                  $size: {
                    $setIntersection: [
                      interests,
                      { $ifNull: ['$campaign.target.interests', []] }
                    ]
                  }
                }
              ]
            }
          }
        },
        {
          $match: {
            targetingScore: { $gt: 0 }
          }
        },
        {
          $sort: { targetingScore: -1, impressions: -1 }
        },
        {
          $limit: limit
        }
      ]);
      
      return this.transformAdsForFrontend(ads);
    } catch (error) {
      console.error('❌ Error getting targeted ads:', error);
      return [];
    }
  }

  /**
   * **GET FALLBACK ADS**
   * Returns any available ads when no targeted ads are found
   */
  static async getFallbackAds({ limit, adType }) {
    try {
      console.log('🔄 Getting fallback ads...');
      
      const ads = await AdCreative.aggregate([
        {
          $match: {
            adType: adType,
            isActive: true,
            reviewStatus: 'approved'
          }
        },
        {
          $lookup: {
            from: 'adcampaigns',
            localField: 'campaignId',
            foreignField: '_id',
            as: 'campaign'
          }
        },
        {
          $unwind: '$campaign'
        },
        {
          $match: {
            'campaign.status': 'active',
            'campaign.startDate': { $lte: new Date() },
            'campaign.endDate': { $gte: new Date() }
          }
        },
        {
          $sort: { impressions: -1, createdAt: -1 }
        },
        {
          $limit: limit
        }
      ]);
      
      return this.transformAdsForFrontend(ads);
    } catch (error) {
      console.error('❌ Error getting fallback ads:', error);
      return [];
    }
  }

  /**
   * **EXTRACT VIDEO CATEGORIES**
   * Analyzes video content to determine categories
   */
  static extractVideoCategories(videoData) {
    const categories = [];
    
    // Analyze video name
    const videoName = (videoData.videoName || '').toLowerCase();
    for (const category in this.CATEGORY_MAPPING) {
      if (this.CATEGORY_MAPPING[category].some(keyword => 
          videoName.includes(keyword.toLowerCase()))) {
        categories.push(category);
      }
    }
    
    // Analyze description
    if (videoData.description) {
      const description = videoData.description.toLowerCase();
      for (const category in this.CATEGORY_MAPPING) {
        if (this.CATEGORY_MAPPING[category].some(keyword => 
            description.includes(keyword.toLowerCase()))) {
          if (!categories.includes(category)) {
            categories.push(category);
          }
        }
      }
    }
    
    // Default to 'entertainment' if no categories found
    if (categories.length === 0) {
      categories.push('entertainment');
    }
    
    return categories;
  }

  /**
   * **EXTRACT VIDEO INTERESTS**
   * Analyzes video content to determine interests
   */
  static extractVideoInterests(videoData) {
    const interests = [];
    
    // Analyze video name
    const videoName = (videoData.videoName || '').toLowerCase();
    for (const interest in this.INTEREST_KEYWORDS) {
      if (this.INTEREST_KEYWORDS[interest].some(keyword => 
          videoName.includes(keyword.toLowerCase()))) {
        interests.push(interest);
      }
    }
    
    // Analyze description
    if (videoData.description) {
      const description = videoData.description.toLowerCase();
      for (const interest in this.INTEREST_KEYWORDS) {
        if (this.INTEREST_KEYWORDS[interest].some(keyword => 
            description.includes(keyword.toLowerCase()))) {
          if (!interests.includes(interest)) {
            interests.push(interest);
          }
        }
      }
    }
    
    // Default to 'entertainment_media' if no interests found
    if (interests.length === 0) {
      interests.push('entertainment_media');
    }
    
    return interests;
  }

  /**
   * **GET AD TARGETING SCORE**
   * Calculates how well an ad matches a video (0-100)
   */
  static getTargetingScore(ad, videoData) {
    const videoCategories = this.extractVideoCategories(videoData);
    const videoInterests = this.extractVideoInterests(videoData);
    
    let score = 0.0;
    
    // Check category match (40% weight)
    const adCategories = ad.campaign?.target?.interests || [];
    const categoryMatches = videoCategories.filter(cat => 
        adCategories.includes(cat)).length;
    score += (categoryMatches / videoCategories.length) * 40;
    
    // Check interest match (40% weight)
    const adInterests = ad.campaign?.target?.interests || [];
    const interestMatches = videoInterests.filter(interest => 
        adInterests.includes(interest)).length;
    score += (interestMatches / videoInterests.length) * 40;
    
    // Check ad performance (20% weight)
    const impressions = ad.impressions || 0;
    const clicks = ad.clicks || 0;
    const ctr = impressions > 0 ? (clicks / impressions) * 100 : 0;
    score += (ctr / 10) * 20; // Normalize CTR to 0-20
    
    return Math.min(Math.max(score, 0), 100);
  }

  /**
   * **TRANSFORM ADS FOR FRONTEND**
   * Converts backend ad data to frontend format
   */
  static transformAdsForFrontend(ads) {
    return ads.map(ad => ({
      _id: ad._id.toString(),
      id: ad._id.toString(),
      adType: ad.adType,
      imageUrl: ad.thumbnail || ad.cloudinaryUrl,
      link: ad.callToAction?.url,
      title: ad.title || ad.campaign?.name || 'Untitled Ad',
      description: ad.campaign?.description || '',
      callToAction: ad.callToAction?.label || 'Learn More',
      targetingScore: ad.targetingScore || 0,
      impressions: ad.impressions || 0,
      clicks: ad.clicks || 0,
      ctr: ad.ctr || 0,
      campaign: {
        id: ad.campaign?._id?.toString(),
        name: ad.campaign?.name,
        objective: ad.campaign?.objective,
        status: ad.campaign?.status
      }
    }));
  }

  /**
   * **GET TARGETING INSIGHTS**
   * Returns insights about ad-video matching
   */
  static getTargetingInsights(ads, videoData) {
    const videoCategories = this.extractVideoCategories(videoData);
    const videoInterests = this.extractVideoInterests(videoData);
    
    const insights = {
      videoCategories,
      videoInterests,
      totalAds: ads.length,
      targetedAds: 0,
      fallbackAds: 0,
      averageScore: 0.0,
      topCategories: {},
      topInterests: {}
    };
    
    if (ads.length === 0) return insights;
    
    let totalScore = 0.0;
    
    for (const ad of ads) {
      const score = this.getTargetingScore(ad, videoData);
      totalScore += score;
      
      if (score > 50) {
        insights.targetedAds++;
      } else {
        insights.fallbackAds++;
      }
      
      // Count categories and interests
      const adCategories = ad.campaign?.target?.interests || [];
      const adInterests = ad.campaign?.target?.interests || [];
      
      for (const category of adCategories) {
        insights.topCategories[category] = (insights.topCategories[category] || 0) + 1;
      }
      
      for (const interest of adInterests) {
        insights.topInterests[interest] = (insights.topInterests[interest] || 0) + 1;
      }
    }
    
    insights.averageScore = totalScore / ads.length;
    
    return insights;
  }
}

export default AdTargetingService;
