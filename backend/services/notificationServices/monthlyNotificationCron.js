import cron from 'node-cron';
import { sendNotificationToAll } from './notificationService.js';
import User from '../../models/User.js';

/**
 * Monthly Notification Cron Job
 * Sends notification to all users on the 1st of every month at 9:00 AM
 * 
 * Cron expression: '0 9 1 * *'
 * - 0: minute (0th minute)
 * - 9: hour (9 AM)
 * - 1: day of month (1st day)
 * - *: month (every month)
 * - *: day of week (any day)
 */
class MonthlyNotificationCron {
  constructor() {
    this.job = null;
    this.isRunning = false;
  }

  /**
   * Start the monthly notification cron job
   */
  start() {
    if (this.job) {
      console.log('⚠️ Monthly notification cron job is already running');
      return;
    }

    // Schedule job to run on 1st of every month at 9:00 AM
    // Cron format: minute hour day month dayOfWeek
    // '0 9 1 * *' = At 09:00 on day-of-month 1 (1st of every month)
    this.job = cron.schedule('0 9 1 * *', async () => {
      await this.sendMonthlyNotification();
    }, {
      scheduled: true,
      timezone: 'Asia/Kolkata' // Adjust timezone as needed
    });

    this.isRunning = true;
    console.log('✅ Monthly notification cron job started');
    console.log('📅 Will run on the 1st of every month at 9:00 AM');
  }

  /**
   * Stop the monthly notification cron job
   */
  stop() {
    if (this.job) {
      this.job.stop();
      this.job = null;
      this.isRunning = false;
      console.log('🛑 Monthly notification cron job stopped');
    }
  }

  /**
   * Send monthly notification to all users
   */
  async sendMonthlyNotification() {
    try {
      console.log('📅 Monthly notification cron: Starting...');
      const startTime = Date.now();

      // Get current month name
      const monthNames = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      const currentDate = new Date();
      const monthName = monthNames[currentDate.getMonth()];
      const year = currentDate.getFullYear();

      // Count total users with FCM tokens
      const userCount = await User.countDocuments({ 
        fcmToken: { $ne: null } 
      });

      console.log(`📊 Found ${userCount} users with FCM tokens`);

      if (userCount === 0) {
        console.log('⚠️ No users with FCM tokens found. Skipping notification.');
        return;
      }

      // Customize your notification message here
      const notification = {
        title: `Welcome to ${monthName}! 🎉`,
        body: `Start your month with amazing content! Check out what's new on Vayug.`,
        data: {
          type: 'monthly_update',
          month: monthName,
          year: year.toString(),
          timestamp: currentDate.toISOString()
        }
      };

      // Send notification to all users
      const result = await sendNotificationToAll(notification);

      const endTime = Date.now();
      const duration = ((endTime - startTime) / 1000).toFixed(2);

      if (result.success) {
        console.log(`✅ Monthly notification sent successfully!`);
        console.log(`   📊 Success: ${result.successCount} users`);
        console.log(`   ❌ Failed: ${result.failureCount} users`);
        console.log(`   ⏱️ Duration: ${duration} seconds`);
      } else {
        console.error(`❌ Monthly notification failed: ${result.error}`);
      }
    } catch (error) {
      console.error('❌ Error in monthly notification cron:', error);
    }
  }

  /**
   * Manually trigger monthly notification (for testing)
   */
  async triggerManually() {
    console.log('🔧 Manually triggering monthly notification...');
    await this.sendMonthlyNotification();
  }

  /**
   * Get cron job status
   */
  getStatus() {
    return {
      isRunning: this.isRunning,
      schedule: '0 9 1 * * (1st of every month at 9:00 AM)',
      timezone: 'Asia/Kolkata'
    };
  }
}

// Export singleton instance
const monthlyNotificationCron = new MonthlyNotificationCron();
export default monthlyNotificationCron;

