import AdCampaign from '../models/AdCampaign.js';
import AdCreative from '../models/AdCreative.js';

class AdCleanupService {
  /**
   * Delete expired ads (ads whose endDate has passed)
   * This should be called periodically (e.g., every hour)
   */
  async cleanupExpiredAds() {
    try {
      console.log('🧹 AdCleanupService: Starting expired ads cleanup...');
      
      const now = new Date();
      
      // Find all ads with endDate < now
      const expiredCampaigns = await AdCampaign.find({
        endDate: { $lt: now }
      });
      
      if (expiredCampaigns.length === 0) {
        console.log('✅ AdCleanupService: No expired ads found');
        return {
          success: true,
          deletedCount: 0,
          campaigns: []
        };
      }
      
      console.log(`🔄 AdCleanupService: Found ${expiredCampaigns.length} expired campaigns`);
      
      // Delete associated creatives first
      const campaignIds = expiredCampaigns.map(c => c._id.toString());
      const deleteCreativeResult = await AdCreative.deleteMany({
        campaignId: { $in: campaignIds }
      });
      
      console.log(`🗑️ AdCleanupService: Deleted ${deleteCreativeResult.deletedCount} creatives`);
      
      // Delete expired campaigns
      const deleteCampaignResult = await AdCampaign.deleteMany({
        endDate: { $lt: now }
      });
      
      console.log(`🗑️ AdCleanupService: Deleted ${deleteCampaignResult.deletedCount} campaigns`);
      
      // Log deleted campaign details
      const deletedCampaigns = expiredCampaigns.map(c => ({
        id: c._id.toString(),
        name: c.name,
        endDate: c.endDate,
        status: c.status
      }));
      
      console.log('📋 AdCleanupService: Deleted campaigns:', deletedCampaigns);
      
      return {
        success: true,
        deletedCount: deleteCampaignResult.deletedCount,
        creativeDeletedCount: deleteCreativeResult.deletedCount,
        campaigns: deletedCampaigns
      };
    } catch (error) {
      console.error('❌ AdCleanupService: Error cleaning up expired ads:', error);
      throw error;
    }
  }

  /**
   * Update campaign status based on dates
   * Marks campaigns as 'completed' if they've passed endDate
   */
  async updateCampaignStatuses() {
    try {
      console.log('🔄 AdCleanupService: Updating campaign statuses...');
      
      const now = new Date();
      
      // Find campaigns that should be marked as completed
      const expiredCampaigns = await AdCampaign.find({
        status: { $in: ['active', 'paused'] },
        endDate: { $lt: now }
      });
      
      if (expiredCampaigns.length === 0) {
        console.log('✅ AdCleanupService: No campaigns need status update');
        return {
          success: true,
          updatedCount: 0
        };
      }
      
      console.log(`🔄 AdCleanupService: Found ${expiredCampaigns.length} campaigns to update`);
      
      // Update status to completed
      const updateResult = await AdCampaign.updateMany(
        {
          status: { $in: ['active', 'paused'] },
          endDate: { $lt: now }
        },
        {
          $set: { status: 'completed' }
        }
      );
      
      console.log(`✅ AdCleanupService: Updated ${updateResult.modifiedCount} campaigns to 'completed'`);
      
      return {
        success: true,
        updatedCount: updateResult.modifiedCount
      };
    } catch (error) {
      console.error('❌ AdCleanupService: Error updating campaign statuses:', error);
      throw error;
    }
  }

  /**
   * Run both cleanup operations
   */
  async runCleanup() {
    try {
      console.log('🚀 AdCleanupService: Running full cleanup...');
      
      const statusUpdateResult = await this.updateCampaignStatuses();
      const deletionResult = await this.cleanupExpiredAds();
      
      return {
        success: true,
        statusUpdate: statusUpdateResult,
        deletion: deletionResult
      };
    } catch (error) {
      console.error('❌ AdCleanupService: Error in runCleanup:', error);
      throw error;
    }
  }
}

export default new AdCleanupService();
