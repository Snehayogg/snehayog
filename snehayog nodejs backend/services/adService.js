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
      uploaderProfilePic
    } = adData;

    // Calculate estimated metrics based on ad type
    const cpm = adType === 'banner' ? AD_CONFIG.BANNER_CPM : AD_CONFIG.DEFAULT_CPM;
    const estimatedImpressions = calculateEstimatedImpressions(budget, cpm);
    const { creatorRevenue, platformRevenue } = calculateRevenueSplit(budget, AD_CONFIG.CREATOR_REVENUE_SHARE);

    // Create ad creative
    const adCreative = new AdCreative({
      title,
      description,
      imageUrl,
      videoUrl,
      link,
      adType,
      uploaderId,
      uploaderName,
      uploaderProfilePic,
      targetAudience: targetAudience || 'all',
      targetKeywords: targetKeywords || [],
      estimatedImpressions,
      fixedCpm: cpm,
      creatorRevenue,
      platformRevenue,
      status: 'draft'
    });

    await adCreative.save();

    // Create invoice for payment
    const invoice = new Invoice({
      campaignId: adCreative._id,
      orderId: generateOrderId(),
      amountINR: budget,
      status: 'created',
      description: `Payment for ad: ${title}`,
      dueDate: new Date(Date.now() + PAYMENT_CONFIG.INVOICE_DUE_HOURS * 60 * 60 * 1000),
      totalAmount: budget
    });

    await invoice.save();

    return {
      ad: adCreative,
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
