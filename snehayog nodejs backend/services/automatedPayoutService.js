import cron from 'node-cron';
import CreatorPayout from '../models/CreatorPayout.js';
import User from '../models/User.js';
import { processPayout } from './payoutProcessorService.js';

class AutomatedPayoutService {
  constructor() {
    this.isRunning = false;
  }

  // **NEW: Start the automated payout scheduler**
  startScheduler() {
    console.log('🚀 Starting automated payout scheduler...');
    
    // Schedule payout on 1st of every month at 9:00 AM IST
    cron.schedule('0 9 1 * *', async () => {
      console.log('📅 Monthly payout triggered - 1st of month');
      await this.processMonthlyPayouts();
    }, {
      timezone: 'Asia/Kolkata' // IST timezone
    });

    // Also run every day at 9:00 AM to check for pending payouts
    cron.schedule('0 9 * * *', async () => {
      console.log('🔍 Daily payout check triggered');
      await this.checkPendingPayouts();
    }, {
      timezone: 'Asia/Kolkata'
    });

    console.log('✅ Automated payout scheduler started successfully');
  }

  // **NEW: Process monthly payouts for all eligible creators**
  async processMonthlyPayouts() {
    if (this.isRunning) {
      console.log('⚠️ Payout process already running, skipping...');
      return;
    }

    this.isRunning = true;
    console.log('🚀 Starting monthly payout process...');

    try {
      const currentMonth = this.getCurrentMonth();
      console.log(`📅 Processing payouts for month: ${currentMonth}`);

      // Get all eligible payouts for the current month
      const eligiblePayouts = await this.getEligiblePayouts(currentMonth);
      console.log(`💰 Found ${eligiblePayouts.length} eligible payouts`);

      if (eligiblePayouts.length === 0) {
        console.log('ℹ️ No eligible payouts for this month');
        return;
      }

      // Process payouts in batches to avoid overwhelming the system
      const batchSize = 50;
      const batches = this.chunkArray(eligiblePayouts, batchSize);

      for (let i = 0; i < batches.length; i++) {
        const batch = batches[i];
        console.log(`📦 Processing batch ${i + 1}/${batches.length} (${batch.length} payouts)`);
        
        await this.processPayoutBatch(batch);
        
        // Wait between batches to avoid rate limiting
        if (i < batches.length - 1) {
          await this.sleep(2000); // 2 second delay
        }
      }

      console.log('✅ Monthly payout process completed successfully');

    } catch (error) {
      console.error('❌ Monthly payout process failed:', error);
      
      // Send notification to admin about failure
      await this.notifyAdminOfFailure(error);
    } finally {
      this.isRunning = false;
    }
  }

  // **NEW: Get all eligible payouts for a specific month**
  async getEligiblePayouts(month) {
    try {
      const eligiblePayouts = await CreatorPayout.find({
        month: month,
        status: 'pending',
        isEligibleForPayout: true
      }).populate('creatorId', 'name email preferredPaymentMethod paymentDetails country');

      console.log(`📊 Found ${eligiblePayouts.length} eligible payouts for ${month}`);
      return eligiblePayouts;

    } catch (error) {
      console.error('Error fetching eligible payouts:', error);
      throw error;
    }
  }

  // **NEW: Process payouts in batches**
  async processPayoutBatch(payouts) {
    const results = {
      successful: [],
      failed: [],
      skipped: []
    };

    for (const payout of payouts) {
      try {
        console.log(`💳 Processing payout for creator: ${payout.creatorId.name} (${payout.formattedPayableAmount})`);

        // Check if creator has valid payment details
        if (!this.hasValidPaymentDetails(payout.creatorId)) {
          console.log(`⚠️ Skipping payout - Invalid payment details for creator: ${payout.creatorId.name}`);
          results.skipped.push({
            payoutId: payout._id,
            creatorId: payout.creatorId._id,
            reason: 'Invalid payment details'
          });
          continue;
        }

        // Process the payout
        const result = await processPayout(payout);
        
        if (result.success) {
          results.successful.push({
            payoutId: payout._id,
            creatorId: payout.creatorId._id,
            amount: payout.payableInCreatorCurrency,
            currency: payout.currency,
            paymentMethod: payout.creatorId.preferredPaymentMethod
          });
          
          console.log(`✅ Payout successful for creator: ${payout.creatorId.name}`);
        } else {
          results.failed.push({
            payoutId: payout._id,
            creatorId: payout.creatorId._id,
            reason: result.error,
            amount: payout.payableInCreatorCurrency,
            currency: payout.currency
          });
          
          console.log(`❌ Payout failed for creator: ${payout.creatorId.name}: ${result.error}`);
        }

      } catch (error) {
        console.error(`❌ Error processing payout for creator ${payout.creatorId.name}:`, error);
        
        results.failed.push({
          payoutId: payout._id,
          creatorId: payout.creatorId._id,
          reason: error.message,
          amount: payout.payableInCreatorCurrency,
          currency: payout.currency
        });
      }
    }

    // Log batch results
    console.log(`📊 Batch Results: ${results.successful.length} successful, ${results.failed.length} failed, ${results.skipped.length} skipped`);

    // Send batch summary to admin
    await this.sendBatchSummary(results);

    return results;
  }

  // **NEW: Check for pending payouts that need attention**
  async checkPendingPayouts() {
    try {
      const pendingPayouts = await CreatorPayout.find({
        status: 'pending',
        isEligibleForPayout: true,
        createdAt: { $lt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) } // Older than 7 days
      }).populate('creatorId', 'name email');

      if (pendingPayouts.length > 0) {
        console.log(`⚠️ Found ${pendingPayouts.length} payouts pending for more than 7 days`);
        
        // Send notification to admin about pending payouts
        await this.notifyAdminOfPendingPayouts(pendingPayouts);
      }

    } catch (error) {
      console.error('Error checking pending payouts:', error);
    }
  }

  // **NEW: Validate payment details**
  hasValidPaymentDetails(user) {
    if (!user.preferredPaymentMethod) return false;

    switch (user.preferredPaymentMethod) {
      case 'upi':
        return user.paymentDetails?.upiId && user.paymentDetails.upiId.length > 0;
      
      case 'bank_transfer':
        return user.paymentDetails?.bankAccount?.accountNumber && 
               user.paymentDetails?.bankAccount?.ifscCode;
      
      case 'paypal':
        return user.paymentDetails?.paypalEmail && user.paymentDetails.paypalEmail.length > 0;
      
      case 'stripe':
        return user.paymentDetails?.stripeAccountId && user.paymentDetails.stripeAccountId.length > 0;
      
      case 'wise':
        return user.paymentDetails?.wiseEmail && user.paymentDetails.wiseEmail.length > 0;
      
      default:
        return false;
    }
  }

  // **NEW: Get current month in YYYY-MM format**
  getCurrentMonth() {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    return `${year}-${month}`;
  }

  // **NEW: Helper function to chunk array into batches**
  chunkArray(array, size) {
    const chunks = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }

  // **NEW: Helper function to sleep**
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // **NEW: Send batch summary to admin**
  async sendBatchSummary(results) {
    try {
      const summary = {
        timestamp: new Date().toISOString(),
        total: results.successful.length + results.failed.length + results.skipped.length,
        successful: results.successful.length,
        failed: results.failed.length,
        skipped: results.skipped.length,
        totalAmount: results.successful.reduce((sum, payout) => sum + payout.amount, 0),
        currency: 'INR'
      };

      console.log('📊 Batch Summary:', summary);
      
      // Here you would send this summary to admin dashboard or email
      // await this.sendAdminNotification(summary);

    } catch (error) {
      console.error('Error sending batch summary:', error);
    }
  }

  // **NEW: Notify admin of failure**
  async notifyAdminOfFailure(error) {
    try {
      const notification = {
        type: 'PAYOUT_FAILURE',
        timestamp: new Date().toISOString(),
        error: error.message,
        stack: error.stack
      };

      console.error('🚨 Admin Notification - Payout Failure:', notification);
      
      // Here you would send this notification to admin
      // await this.sendAdminNotification(notification);

    } catch (notifyError) {
      console.error('Error notifying admin:', notifyError);
    }
  }

  // **NEW: Notify admin of pending payouts**
  async notifyAdminOfPendingPayouts(payouts) {
    try {
      const notification = {
        type: 'PENDING_PAYOUTS',
        timestamp: new Date().toISOString(),
        count: payouts.length,
        payouts: payouts.map(p => ({
          id: p._id,
          creator: p.creatorId.name,
          amount: p.formattedPayableAmount,
          month: p.month
        }))
      };

      console.log('⚠️ Admin Notification - Pending Payouts:', notification);
      
      // Here you would send this notification to admin
      // await this.sendAdminNotification(notification);

    } catch (notifyError) {
      console.error('Error notifying admin:', notifyError);
    }
  }

  // **NEW: Stop the scheduler**
  stopScheduler() {
    console.log('🛑 Stopping automated payout scheduler...');
    cron.getTasks().forEach(task => task.stop());
    console.log('✅ Automated payout scheduler stopped');
  }
}

export default new AutomatedPayoutService();
