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

class AdService {
  /**
   * Create a new ad with payment processing
   */
  async createAdWithPayment(adData) {
    console.log('🔍 AdService: Received ad data:', JSON.stringify(adData, null, 2));
    
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
      // **NEW: Advanced targeting fields**
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
      hourParting
    } = adData;

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
    const campaign = new AdCampaign({
      name: title,
      advertiserUserId: user._id, // Use the actual User ObjectId
      objective: 'awareness',
      startDate: startDate ? new Date(startDate) : new Date(),
      endDate: endDate ? new Date(endDate) : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      dailyBudget: Math.max(budget, 100), // Ensure minimum ₹100
      totalBudget: Math.max(budget * 30, 1000), // Ensure minimum ₹1000
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
        // **NEW: Additional targeting fields**
        deviceType: deviceType || null
      },
      // **NEW: Advanced campaign settings**
      optimizationGoal: optimizationGoal || 'impressions',
      timeZone: timeZone || 'Asia/Kolkata',
      dayParting: dayParting || {},
      hourParting: hourParting || {},
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
    
    // **NEW: Calculate aspect ratio (default to 16:9 for now)**
    const aspectRatio = '16:9'; // This should be calculated from actual image/video dimensions
    
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
    const adCreative = new AdCreative({
      campaignId: campaign._id,
      adType: adType === 'banner' ? 'banner' : adType === 'carousel' ? 'carousel ads' : 'video feeds',
      type: mediaType,
      cloudinaryUrl: cloudinaryUrl,
      thumbnail: imageUrl, // Use image as thumbnail for videos
      aspectRatio: aspectRatio,
      durationSec: mediaType === 'video' ? 15 : undefined, // Default 15 seconds for videos
      callToAction: {
        label: callToActionLabel,
        url: callToActionUrl
      },
      reviewStatus: 'pending',
      isActive: false
    });

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

  /**
   * Process payment and activate ad
   */
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

    adCreative.status = 'active';
    adCreative.activatedAt = new Date();
    await adCreative.save();

    return {
      ad: adCreative,
      invoice: invoice
    };
  }

  /**
   * Get active ads for serving
   */
  async getActiveAds(targetingCriteria) {
    const { userId, platform, location } = targetingCriteria;

    const query = {
      status: 'active',
      $or: [
        { targetAudience: 'all' },
        { targetAudience: { $in: [userId, platform, location] } }
      ]
    };

    const activeAds = await AdCreative.find(query).limit(10);

    // Update impression count
    for (const ad of activeAds) {
      ad.impressions = (ad.impressions || 0) + 1;
      await ad.save();
    }

    return activeAds;
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
