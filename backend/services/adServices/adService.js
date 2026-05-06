import mongoose from 'mongoose';
import AdCreative from '../../models/AdCreative.js';
import AdCampaign from '../../models/AdCampaign.js';
import Invoice from '../../models/Invoice.js';
import { 
  calculateEstimatedImpressions, 
  calculateRevenueSplit, 
  generateOrderId 
} from '../../utils/common.js';
import { AD_CONFIG, PAYMENT_CONFIG } from '../../constants/index.js';
import { calculateCategoryRelevance } from '../../config/categoryMap.js';

class AdService {
  async createAdWithPayment(adData) {
    console.log('🔍 AdService: Received ad data:', JSON.stringify(adData, null, 2));
    console.log('🔍 AdService: deviceType from request:', adData.deviceType);
    console.log('🔍 AdService: deviceType type:', typeof adData.deviceType);
    
    const {
      title,
      description,
      imageUrl,
      videoUrl,
      link,
      adType,
      budget,
      uploaderId,
      startDate,
      endDate,
      minAge,
      maxAge,
      gender,
      locations,
      interests,
      platforms,
      deviceType,
      optimizationGoal,
      frequencyCap,
      timeZone,
      dayParting,
      imageUrls // **NEW: Support multiple image URLs for carousel ads**
    } = adData;

    // **NEW: Validate required fields**
    if (!title || !description || !adType || !budget || !uploaderId) {
      throw new Error('Missing required fields: title, description, adType, budget, and uploaderId are required');
    }

    // **NEW: Find User by googleId to get ObjectId**
    const User = mongoose.model('User');
    const user = await User.findOne({ googleId: uploaderId });
    if (!user) {
      throw new Error(`User not found with googleId: ${uploaderId}`);
    }
    
    const campaign = new AdCampaign({
      name: title,
      advertiserUserId: user._id, 
      objective: 'awareness',
      status: 'active', // **FIX: Set campaign as active immediately after payment**
      startDate: startDate ? new Date(startDate) : new Date(),
      endDate: endDate ? new Date(endDate) : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      dailyBudget: Math.max(budget, 100),
      totalBudget: Math.max(budget * 30, 1000), 
      bidType: 'CPM',
      cpmINR: adType === 'banner' ? 20 : 30,
      target: {
        age: { 
          min: minAge || 18, 
          max: maxAge || 65 
        },
        gender: gender || 'all',
        locations: locations || [],
        interests: interests || [],
        platforms: platforms && platforms.length > 0 ? platforms : ['android', 'ios', 'web'],
        deviceType: deviceType || 'all'
      },
      optimizationGoal: optimizationGoal || 'impressions',
      timeZone: timeZone || 'Asia/Kolkata',
      dayParting: dayParting || {},
      pacing: 'smooth',
      frequencyCap: frequencyCap || 3
    });

    try {
      await campaign.save();
      console.log('✅ AdService: Created campaign:', campaign._id);
    } catch (campaignError) {
      console.error('❌ AdService: Campaign creation failed:', campaignError);
      throw new Error(`Campaign creation failed: ${campaignError.message}`);
    }

    // **NEW: Determine media type and aspect ratio**
    const mediaType = videoUrl ? 'video' : 'image';
    const cloudinaryUrl = videoUrl || imageUrl;
    
    const aspectRatio = '9:16'; // This should be calculated from actual image/video dimensions
    
    // **NEW: Determine call to action label and URL**
    let callToActionLabel = 'Learn More';
    let callToActionUrl = ''; // **FIX: Don't set default URL - let it be empty if no link provided**
    
    // Only use link if it's a valid URL
    if (link && link.trim().startsWith('http')) {
      callToActionUrl = link.trim();
      // Determine label based on URL content
      if (link.includes('shop') || link.includes('buy') || link.includes('purchase')) {
        callToActionLabel = 'Shop Now';
      } else if (link.includes('download')) {
        callToActionLabel = 'Download';
      } else if (link.includes('signup') || link.includes('register')) {
        callToActionLabel = 'Sign Up';
      }
    } else {
      // If link is not a valid URL, keep it empty
      console.log('⚠️ AdService: Link is not a valid URL, keeping empty:', link);
      callToActionUrl = '';
    }

    // **NEW: Create AdCreative with correct field mapping**
    const creativeData = {
      campaignId: campaign._id,
      adType: adType === 'banner' ? 'banner' : adType === 'carousel' ? 'carousel' : 'video feed ad',
      type: mediaType,
      title: title, // **FIX: Add title field for banner ads**
      callToAction: {
        label: callToActionLabel,
        url: callToActionUrl
      },
      reviewStatus: 'approved', // **FIX: Auto-approve ads with payment**
      isActive: true // **FIX: Activate ads immediately after payment**
    };

    // **NEW: Handle carousel ads with multiple images**
    if (adType === 'carousel' && imageUrls && imageUrls.length > 0) {
      console.log(`🔍 AdService: Creating carousel ad with ${imageUrls.length} images`);
      creativeData.slides = imageUrls.map(url => ({
        mediaUrl: url,
        thumbnail: url,
        mediaType: 'image',
        aspectRatio: '9:16',
        title: title,
        description: description
      }));
    } else {
      // **Traditional single media creative**
      creativeData.cloudinaryUrl = cloudinaryUrl;
      creativeData.thumbnail = imageUrl; // Use image as thumbnail for videos
      creativeData.aspectRatio = aspectRatio;
      creativeData.durationSec = mediaType === 'video' ? 15 : undefined; // Default 15 seconds for videos
    }

    const adCreative = new AdCreative(creativeData);

    try {
      await adCreative.save();
      console.log('✅ AdService: Created ad creative:', adCreative._id);
    } catch (creativeError) {
      console.error('❌ AdService: AdCreative creation failed:', creativeError);
      throw new Error(`AdCreative creation failed: ${creativeError.message}`);
    }

    // Create invoice for payment
    const invoice = new Invoice({
      campaignId: campaign._id,
      orderId: generateOrderId(),
      amountINR: budget,
      status: 'created',
      description: `Payment for ad: ${title}`,
      dueDate: new Date(Date.now() + PAYMENT_CONFIG.INVOICE_DUE_HOURS * 60 * 60 * 1000),
      totalAmount: budget,
      // **FIXED: Add required invoiceNumber field**
      invoiceNumber: `INV-${Date.now()}-${Math.floor(Math.random() * 1000)}`
    });

    try {
      await invoice.save();
      console.log('✅ AdService: Created invoice:', invoice._id);
    } catch (invoiceError) {
      console.error('❌ AdService: Invoice creation failed:', invoiceError);
      throw new Error(`Invoice creation failed: ${invoiceError.message}`);
    }

    return {
      ad: adCreative,
      campaign: campaign,
      invoice: {
        id: invoice._id,
        orderId: invoice.orderId,
        amount: invoice.amountINR,
        status: invoice.status
      }
    };
  }

  async processPayment(paymentData) {
    const { orderId, paymentId, signature, adId } = paymentData;

    // Update invoice status
    const invoice = await Invoice.findOne({ orderId });
    if (!invoice) {
      throw new Error('Invoice not found');
    }

    invoice.status = 'paid';
    invoice.razorpayPaymentId = paymentId;
    invoice.razorpaySignature = signature;
    invoice.paymentDate = new Date();
    await invoice.save();

    // Activate the ad
    const adCreative = await AdCreative.findById(adId);
    if (!adCreative) {
      throw new Error('Ad not found');
    }

    // Ensure all activation fields are consistent
    adCreative.status = 'active';
    adCreative.isActive = true;
    adCreative.reviewStatus = 'approved';
    adCreative.activatedAt = new Date();
    await adCreative.save();

    return {
      ad: adCreative,
      invoice: invoice
    };
  }

  /**
   * Get active ads for serving with proper targeting
   */
  async getActiveAds(targetingCriteria = {}) {
    try {
      const { userId, platform, location, videoCategory, videoTags, videoKeywords, adType } = targetingCriteria;

      console.log('🎯 AdService: getActiveAds called with:', { 
        userId, platform, location, videoCategory, videoTags, videoKeywords, adType 
      });

      // Build query for active ads
      const query = {
        isActive: true,
        reviewStatus: 'approved'
      };
      
      // Add adType filter if specified
      if (adType) {
        query.adType = adType;
      }
      
      // Find ads with active campaigns
      const activeCreatives = await AdCreative.find(query)
        .sort({ createdAt: -1 })
        .populate({
          path: 'campaignId',
          match: { 
            status: 'active',
            startDate: { $lte: new Date() },
            endDate: { $gte: new Date() }
          }
        })
        .limit(50);

      // Filter out ads with null campaign (campaign not active or not in date range)
      const validCreatives = activeCreatives.filter(ad => ad.campaignId !== null);

      console.log(`🔍 AdService: Found ${validCreatives.length} active and valid ad creatives`);

      // **STEP 2: Filter ads based on targeting if contextual signals are provided**
      const hasContext = Boolean(videoCategory) ||
        (Array.isArray(videoTags) && videoTags.length > 0) ||
        (Array.isArray(videoKeywords) && videoKeywords.length > 0);

      if (!hasContext) {
        console.log('ℹ️ AdService: No video context provided; returning all active ads');
        return validCreatives.map(ad => this.transformAdForFrontend(ad));
      }

      const targetedAds = [];
      
      for (const creative of validCreatives) {
        const campaign = creative.campaignId;
        let relevanceScore = 0;
        let matchReasons = [];

        // **TARGETING LOGIC: Match ad interests with video context**
        
        // 1. Check if campaign has interests defined
        const campaignInterests = campaign.target?.interests || [];
        
        if (campaignInterests.length === 0) {
          // If no interests specified, show to all (universal ad)
          relevanceScore = 50;
          matchReasons.push('universal_ad');
        } else {
          // Check interest matching with video category using smart category map
          if (videoCategory) {
            for (const interest of campaignInterests) {
              const relevance = calculateCategoryRelevance(interest, videoCategory);
              
              if (relevance.score > 0) {
                relevanceScore += relevance.score;
                matchReasons.push(`category_${relevance.level}:${interest}(${relevance.score})`);
              }
            }
          }

          // Check interest matching with video tags
          if (videoTags && videoTags.length > 0) {
            for (const interest of campaignInterests) {
              const interestLower = interest.toLowerCase();
              for (const tag of videoTags) {
                const tagLower = tag.toLowerCase();
                
                if (tagLower === interestLower || tagLower.includes(interestLower) || interestLower.includes(tagLower)) {
                  relevanceScore += 60;
                  matchReasons.push(`tag_match:${tag}`);
                }
              }
            }
          }

          // Check interest matching with video keywords
          if (videoKeywords && videoKeywords.length > 0) {
            for (const interest of campaignInterests) {
              const interestLower = interest.toLowerCase();
              for (const keyword of videoKeywords) {
                const keywordLower = keyword.toLowerCase();
                
                if (keywordLower === interestLower || keywordLower.includes(interestLower) || interestLower.includes(keywordLower)) {
                  relevanceScore += 40;
                  matchReasons.push(`keyword_match:${keyword}`);
                }
              }
            }
          }
        }

        // **DECISION: Only show ads with relevance score > 0**
        if (relevanceScore > 0) {
          targetedAds.push({
            creative,
            relevanceScore,
            matchReasons: matchReasons.join(', ')
          });
        }
      }

      // **FALLBACK: If nothing matched but we have active ads, return them sorted by score or newest**
      if (targetedAds.length === 0) {
        console.log('⚠️ AdService: No targeted ads matched; returning all active ads as fallback');
        return validCreatives.map(ad => this.transformAdForFrontend(ad));
      }

      // **STEP 3: Sort by relevance score (highest first)**
      targetedAds.sort((a, b) => b.relevanceScore - a.relevanceScore);

      console.log(`✅ AdService: ${targetedAds.length} ads matched targeting criteria`);

      // **STEP 4: Return top ads**
      const finalAds = targetedAds.slice(0, 10).map(item => item.creative);

      // Transform raw AdCreative documents to frontend-expected format
      return finalAds.map(ad => this.transformAdForFrontend(ad));
    } catch (error) {
      console.error('❌ AdService: Error getting active ads:', error);
      return [];
    }
  }

  /**
   * Transform raw AdCreative document to frontend-expected format
   */
  transformAdForFrontend(adCreative) {
    const campaign = adCreative.campaignId;
    
    // Extract image URL based on ad type
    let imageUrl = null;
    if (adCreative.adType === 'carousel') {
      imageUrl = adCreative.slides?.[0]?.thumbnail || adCreative.slides?.[0]?.mediaUrl || null;
    } else {
      imageUrl = adCreative.thumbnail || adCreative.cloudinaryUrl || null;
    }
    
    // Extract call-to-action link
    const link = adCreative.callToAction?.url || null;
    
    // Base response object
    const response = {
      _id: adCreative._id.toString(),
      id: adCreative._id.toString(),
      adType: adCreative.adType,
      imageUrl: imageUrl,
      link: link,
      cloudinaryUrl: adCreative.cloudinaryUrl,
      thumbnail: adCreative.thumbnail,
      impressions: adCreative.impressions || 0,
      clicks: adCreative.clicks || 0,
      createdAt: adCreative.createdAt,
      updatedAt: adCreative.updatedAt,
    };
    
    // Add title for all ad types, description only for non-banner ads
    response.title = adCreative.title || campaign?.name || 'Untitled Ad';
    if (adCreative.adType !== 'banner') {
      response.description = campaign?.objective || '';
    }
    
    return response;
  }

  /**
   * Track ad click
   */
  async trackAdClick(adId, clickData = {}) {
    try {
      console.log('🖱️ AdService: Tracking click for ad:', adId);
      
      const ad = await AdCreative.findById(adId);
      if (!ad) {
        throw new Error('Ad not found');
      }
      
      // Increment click count
      ad.clicks = (ad.clicks || 0) + 1;
      await ad.save();
      
      // Also increment campaign clicks if available
      if (ad.campaignId) {
        const campaign = await AdCampaign.findById(ad.campaignId);
        if (campaign) {
          campaign.clicks = (campaign.clicks || 0) + 1;
          await campaign.save();
        }
      }
      
      console.log('✅ AdService: Click tracked successfully');
      return { success: true, clicks: ad.clicks };
      
    } catch (error) {
      console.error('❌ AdService: Error tracking click:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Get ad analytics
   */
  async getAdAnalytics(adId, userId = null) {
    try {
      console.log('📊 AdService: Getting analytics for ad:', adId, 'userId:', userId);
      
      // **FIX: Try to find by AdCreative ID first, then by Campaign ID**
      let ad = await AdCreative.findById(adId).populate('campaignId');
      
      // If not found as AdCreative, try finding by Campaign ID
      if (!ad) {
        console.log('🔍 AdService: Not found as AdCreative, trying Campaign ID...');
        const campaign = await AdCampaign.findById(adId);
        if (campaign) {
          // Find the creative for this campaign
          ad = await AdCreative.findOne({ campaignId: campaign._id }).populate('campaignId');
        }
      }
      
      if (!ad) {
        console.error('❌ AdService: Ad not found for ID:', adId);
        throw new Error('Ad not found');
      }

      console.log('✅ AdService: Found ad:', ad._id, 'Campaign:', ad.campaignId?._id);

      // **FIX: Verify user owns this ad via campaign's advertiserUserId**
      if (userId) {
        const campaign = ad.campaignId;
        if (!campaign) {
          throw new Error('Campaign not found for this ad');
        }

        // Get user's googleId to match with advertiserUserId
        const User = mongoose.model('User');
        const user = await User.findOne({ googleId: userId });
        
        if (!user) {
          console.error('❌ AdService: User not found for googleId:', userId);
          throw new Error('User not found');
        }

        // Compare campaign's advertiserUserId with user's _id
        if (campaign.advertiserUserId.toString() !== user._id.toString()) {
          console.error('❌ AdService: Access denied. Campaign advertiserUserId:', campaign.advertiserUserId, 'User _id:', user._id);
          throw new Error('Access denied');
        }

        console.log('✅ AdService: User verification passed');
      }

      // **FIX: Get campaign data for proper metrics**
      const campaign = ad.campaignId;
      const cpm = campaign?.cpmINR || 30;
      const ctr = this.calculateCTR(ad.clicks || 0, ad.impressions || 0);
      const spend = this.calculateSpend((ad.adType === 'carousel' ? (ad.views || 0) : (ad.impressions || 0)), cpm);
      const revenue = spend * 0.7; // 70% to advertiser, 30% to platform

      // **FIX: Get imageUrl based on ad type**
      let imageUrl = null;
      if (ad.adType === 'carousel' && ad.slides && ad.slides.length > 0) {
        imageUrl = ad.slides[0].thumbnail || ad.slides[0].mediaUrl || null;
      } else {
        imageUrl = ad.thumbnail || ad.cloudinaryUrl || null;
      }

      const result = {
        ad: {
          id: ad._id.toString(),
          campaignId: campaign?._id?.toString(),
          title: ad.title || campaign?.name || 'Unknown Ad',
          status: ad.isActive ? 'active' : 'inactive',
          impressions: ad.impressions || 0,
          views: ad.views || 0,
          clicks: ad.clicks || 0,
          ctr: ctr.toFixed(2),
          spend: spend.toFixed(2),
          revenue: revenue.toFixed(2),
          cpm: cpm.toFixed(2),
          adType: ad.adType || 'banner',
          imageUrl: imageUrl, // **FIX: Include imageUrl for proper display**
          createdAt: ad.createdAt,
          updatedAt: ad.updatedAt
        }
      };

      console.log('✅ AdService: Analytics calculated successfully:', result);
      return result;
      
    } catch (error) {
      console.error('❌ AdService: Error getting analytics:', error);
      throw error; // Re-throw to let route handle it
    }
  }

  /**
   * Get granular breakdown of ad performance per video
   */
  async getAdVideoBreakdown(adId) {
    try {
      console.log('📊 AdService: Getting video breakdown for ad:', adId);
      
      const AdImpression = mongoose.model('AdImpression');
      const Video = mongoose.model('Video');
      
      const adObjectId = new mongoose.Types.ObjectId(adId);
      
      // Aggregate impressions and views grouped by videoId
      const breakdownData = await AdImpression.aggregate([
        { $match: { adId: adObjectId } },
        { 
          $group: { 
            _id: '$videoId',
            impressions: { $sum: 1 },
            views: { 
              $sum: { $cond: [{ $eq: ['$isViewed', true] }, 1, 0] } 
            },
            totalDuration: { $sum: '$viewDuration' }
          } 
        },
        { $sort: { impressions: -1 } }
      ]);
      
      if (!breakdownData || breakdownData.length === 0) {
        return [];
      }
      
      // Populate video titles and info
      const results = [];
      const cpm = 30; // Default CPM for calculation
      
      for (const item of breakdownData) {
        const video = await Video.findById(item._id).select('title uploader').lean();
        if (video) {
          const spend = (item.views / 1000) * cpm;
          results.push({
            videoId: item._id,
            videoTitle: video.title || 'Untitled Video',
            impressions: item.impressions,
            views: item.views,
            spend: spend.toFixed(2),
            ctr: item.impressions > 0 ? ((item.views / item.impressions) * 100).toFixed(2) : '0.00'
          });
        }
      }
      
      return results;
    } catch (error) {
      console.error('❌ AdService: Error getting video breakdown:', error);
      throw error;
    }
  }

  /**
   * Calculate CTR
   */
  calculateCTR(clicks, impressions) {
    if (impressions === 0) return 0;
    return (clicks / impressions) * 100;
  }

  /**
   * Calculate spend
   */
  calculateSpend(impressions, cpm) {
    return (impressions / 1000) * cpm;
  }
}

export default new AdService();
