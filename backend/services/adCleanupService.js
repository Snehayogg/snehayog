import AdCampaign from '../models/AdCampaign.js';
import AdCreative from '../models/AdCreative.js';

class AdCleanupService {
  /**
   * Automatically expires campaigns that have passed their end date
   */
  async runCleanup() {
    console.log('🧹 Starting ad cleanup job...');
    const now = new Date();

    try {
      // 1. Find active campaigns that have expired
      const expiredCampaigns = await AdCampaign.find({
        status: 'active',
        endDate: { $lt: now }
      });

      console.log(`🔍 Found ${expiredCampaigns.length} expired campaigns to process`);

      if (expiredCampaigns.length === 0) {
        return { processed: 0, success: true };
      }

      let processedCount = 0;
      for (const campaign of expiredCampaigns) {
        // Change campaign status to completed
        campaign.status = 'completed';
        await campaign.save();

        // 2. Deactivate all creatives associated with this campaign
        await AdCreative.updateMany(
          { campaignId: campaign._id },
          { $set: { isActive: false } }
        );

        processedCount++;
        console.log(`✅ Campaign ${campaign._id} marked as completed and creatives deactivated`);
      }

      console.log(`🎉 Ad cleanup complete. Processed ${processedCount} campaigns.`);
      return { processed: processedCount, success: true };
    } catch (error) {
      console.error('❌ Error during ad cleanup:', error);
      throw error;
    }
  }
}

const adCleanupService = new AdCleanupService();
export default adCleanupService;
