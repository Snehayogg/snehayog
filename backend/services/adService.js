import mongoose from 'mongoose';
import AdCreative from '../models/AdCreative.js';
import AdCampaign from '../models/AdCampaign.js';
import Invoice from '../models/Invoice.js';
import { 
  calculateEstimatedImpressions, 
  calculateRevenueSplit, 
  generateOrderId 
} from '../utils/common.js';
import { AD_CONFIG, PAYMENT_CONFIG } from '../constants/index.js';
import { calculateCategoryRelevance } from '../config/categoryMap.js';

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
      targetAudience,
      targetKeywords,
      uploaderId,
      uploaderName,
      uploaderProfilePic,
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

    console.log('🔍 AdService: deviceType after destructuring:', deviceType);
    console.log('🔍 AdService: deviceType type after destructuring:', typeof deviceType);
    console.log('🔍 AdService: Link field value:', link);
    console.log('🔍 AdService: Link field type:', typeof link);
    console.log('🔍 AdService: Link field length:', link ? link.length : 'null');

    // **NEW: Validate required fields**
    if (!title || !description || !adType || !budget || !uploaderId) {
      console.log('❌ AdService: Missing required fields:');
      console.log('   Title:', !!title);
      console.log('   Description:', !!description);
      console.log('   Ad Type:', !!adType);
      console.log('   Budget:', !!budget);
      console.log('   Uploader ID:', !!uploaderId);
      throw new Error('Missing required fields: title, description, adType, budget, and uploaderId are required');
    }

    // **NEW: Find User by googleId to get ObjectId**
    const User = mongoose.model('User');
    const user = await User.findOne({ googleId: uploaderId });
    if (!user) {
      throw new Error(`User not found with googleId: ${uploaderId}`);
    }
    console.log('✅ AdService: Found user:', user._id);

    // **NEW: Create AdCampaign with all targeting fields**
    console.log('🔍 AdService: About to create campaign with deviceType:', deviceType);
    console.log('🔍 AdService: deviceType condition check:', deviceType && { deviceType: deviceType });
    
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
      cpmINR: adType === 'banner' ? 10 : 30,
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
    let callToActionUrl = 'https://example.com'; // Default URL
    
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
      // If link is not a valid URL, use default
      console.log('⚠️ AdService: Link is not a valid URL, using default:', link);
    }

    // **NEW: Create AdCreative with correct field mapping**
    const creativeData = {
      campaignId: campaign._id,
      adType: adType === 'banner' ? 'banner' : adType === 'carousel' ? 'carousel' : 'video feed ad',
      type: mediaType,
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
  async getActiveAds(targetingCriteria) {
    const { userId, platform, location, videoCategory, videoTags, videoKeywords } = targetingCriteria;

    console.log('🎯 AdService: getActiveAds called with:', { 
      userId, platform, location, videoCategory, videoTags, videoKeywords 
    });

    // **STEP 1: Get ads with their campaigns**
    // Only include active and approved ads
    const activeCreatives = await AdCreative.find({
      isActive: true,
      reviewStatus: 'approved'
    })
      .sort({ createdAt: -1 })
      .populate('campaignId')
      .limit(50);

    console.log(`🔍 AdService: Found ${activeCreatives.length} active ad creatives`);

    // **FAST PATH: If no contextual signals were provided, return empty array**
    const hasContext = Boolean(videoCategory) ||
      (Array.isArray(videoTags) && videoTags.length > 0) ||
      (Array.isArray(videoKeywords) && videoKeywords.length > 0);

    if (!hasContext) {
      console.log('ℹ️ AdService: No video context provided; returning empty array');
      return [];
    }

    // **STEP 2: Filter ads based on targeting**
    const targetedAds = [];
    
    for (const creative of activeCreatives) {
      // Skip if campaign is deleted
      if (!creative.campaignId) {
        console.log(`⚠️ Skipping creative ${creative._id} - no campaign`);
        continue;
      }

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
        console.log(`   📢 Ad ${creative._id}: Universal ad (no targeting)`);
      } else {
        // Check interest matching with video category using smart category map
        if (videoCategory) {
          for (const interest of campaignInterests) {
            const relevance = calculateCategoryRelevance(interest, videoCategory);
            
            if (relevance.score > 0) {
              relevanceScore += relevance.score;
              
              let matchType = '';
              switch (relevance.level) {
                case 'exact':
                  matchType = 'EXACT';
                  break;
                case 'primary':
                  matchType = 'PRIMARY';
                  break;
                case 'related':
                  matchType = 'RELATED';
                  break;
                case 'fallback':
                  matchType = 'FALLBACK';
                  break;
                case 'partial':
                  matchType = 'PARTIAL';
                  break;
              }
              
              matchReasons.push(`category_${relevance.level}:${interest}(${relevance.score})`);
              console.log(`   ✅ Ad ${creative._id}: ${matchType} category match - ${interest} → ${videoCategory} (Score: +${relevance.score})`);
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
                console.log(`   ✅ Ad ${creative._id}: Tag match - ${tag} ~ ${interest}`);
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
                console.log(`   ✅ Ad ${creative._id}: Keyword match - ${keyword} ~ ${interest}`);
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
        console.log(`   ✅ Ad ${creative._id} SELECTED - Score: ${relevanceScore}, Reasons: ${matchReasons.join(', ')}`);
      } else {
        console.log(`   ❌ Ad ${creative._id} REJECTED - No relevance (interests: ${campaignInterests.join(', ')})`);
      }
    }

    // **FALLBACK: If nothing matched, return empty array**
    if (targetedAds.length === 0) {
      console.log('⚠️ AdService: No targeted ads matched; returning empty array');
      return [];
    }

    // **STEP 3: Sort by relevance score (highest first)**
    targetedAds.sort((a, b) => b.relevanceScore - a.relevanceScore);

    console.log(`✅ AdService: ${targetedAds.length} ads matched targeting criteria`);

    // **STEP 4: Return top ads and update impression count**
    const finalAds = targetedAds.slice(0, 10).map(item => item.creative);
    
    for (const ad of finalAds) {
      ad.impressions = (ad.impressions || 0) + 1;
      await ad.save();
    }

    // Transform raw AdCreative documents to frontend-expected format
    return finalAds.map(ad => this.transformAdForFrontend(ad));
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
    
    // Add title and description only for non-banner ads
    if (adCreative.adType !== 'banner') {
      response.title = campaign?.name || 'Untitled Ad';
      response.description = campaign?.objective || '';
    }
    
    return response;
  }

  /**
   * Track ad click
   */
  async trackAdClick(adId, clickData) {
    const { userId, platform, location } = clickData;

    const ad = await AdCreative.findById(adId);
    if (!ad) {
      throw new Error('Ad not found');
    }

    // Update click count
    ad.clicks = (ad.clicks || 0) + 1;
    await ad.save();

    // Log click event for analytics
    console.log(`Ad click tracked: ${adId} by user ${userId} on ${platform}`);

    return { message: 'Click tracked successfully' };
  }

  /**
   * Get ad analytics
   */
  async getAdAnalytics(adId, userId) {
    const ad = await AdCreative.findById(adId);
    if (!ad) {
      throw new Error('Ad not found');
    }

    // Verify user owns this ad
    if (ad.uploaderId.toString() !== userId) {
      throw new Error('Access denied');
    }

    // Calculate metrics
    const ctr = this.calculateCTR(ad.clicks || 0, ad.impressions || 0);
    const spend = this.calculateSpend(ad.impressions || 0, ad.fixedCpm);
    const revenue = spend * AD_CONFIG.CREATOR_REVENUE_SHARE;

    return {
      ad: {
        id: ad._id,
        title: ad.title,
        status: ad.status,
        impressions: ad.impressions || 0,
        clicks: ad.clicks || 0,
        ctr: ctr.toFixed(2),
        spend: spend.toFixed(2),
        revenue: revenue.toFixed(2),
        estimatedImpressions: ad.estimatedImpressions,
        fixedCpm: ad.fixedCpm
      }
    };
  }

  /**
   * Get active ads for serving with targeting
   */
  async getActiveAds(targetingCriteria = {}) {
    try {
      console.log('🎯 AdService: Getting active ads with criteria:', targetingCriteria);
      
      const { userId, platform, location, videoCategory, videoTags, videoKeywords, adType } = targetingCriteria;
      
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
      const ads = await AdCreative.find(query)
        .populate({
          path: 'campaignId',
          match: { 
            status: 'active',
            startDate: { $lte: new Date() },
            endDate: { $gte: new Date() }
          }
        })
        .lean();
      
      // Filter out ads with null campaign (campaign not active)
      const activeAds = ads.filter(ad => ad.campaignId !== null);
      
      console.log(`✅ AdService: Found ${activeAds.length} active ads`);
      
      // Apply additional targeting if provided
      let targetedAds = activeAds;
      
      if (videoCategory && videoTags && videoKeywords) {
        // Apply content-based targeting
        targetedAds = activeAds.filter(ad => {
          const campaign = ad.campaignId;
          if (!campaign || !campaign.target) return true;
          
          // Check if campaign targets this category
          if (campaign.target.interests && campaign.target.interests.length > 0) {
            const hasRelevantInterest = campaign.target.interests.some(interest => 
              interest.toLowerCase().includes(videoCategory.toLowerCase()) ||
              videoTags.some(tag => tag.toLowerCase().includes(interest.toLowerCase())) ||
              videoKeywords.some(keyword => keyword.toLowerCase().includes(interest.toLowerCase()))
            );
            if (!hasRelevantInterest) return false;
          }
          
          return true;
        });
      }
      
      console.log(`🎯 AdService: After targeting: ${targetedAds.length} ads`);
      
      return targetedAds;
      
    } catch (error) {
      console.error('❌ AdService: Error getting active ads:', error);
      return [];
    }
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
      const ad = await AdCreative.findById(adId).populate('campaignId');
      if (!ad) {
        throw new Error('Ad not found');
      }
      
      const ctr = this.calculateCTR(ad.clicks || 0, ad.impressions || 0);
      const spend = this.calculateSpend(ad.impressions || 0, ad.campaignId?.cpmINR || 30);
      const revenue = spend * 0.7; // 70% to advertiser, 30% to platform
      
      return {
        adId: ad._id,
        title: ad.campaignId?.name || 'Unknown Ad',
        impressions: ad.impressions || 0,
        clicks: ad.clicks || 0,
        ctr: ctr.toFixed(2),
        spend: spend.toFixed(2),
        revenue: revenue.toFixed(2),
        status: ad.isActive ? 'active' : 'inactive'
      };
      
    } catch (error) {
      console.error('❌ AdService: Error getting analytics:', error);
      return { error: error.message };
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
