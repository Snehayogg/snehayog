import CreatorDailyStats from '../models/CreatorDailyStats.js';

/**
 * Update daily stats for a creator using atomic upsert.
 * @param {string} creatorId - The creator's internal MongoDB ID
 * @param {Object} increments - Fields to increment (e.g., { views: 1, watchTime: 30 })
 */
export const updateCreatorDailyStats = async (creatorId, increments) => {
  try {
    if (!creatorId) return;

    // Get the start of the current day in UTC
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    // Atomic update: finds the doc for (creator, date) or creates it, then increments fields
    await CreatorDailyStats.findOneAndUpdate(
      { creatorId, date: today },
      { $inc: increments },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
  } catch (error) {
    // Only log if it's not a duplicate key error (which can happen under high concurrency)
    if (error.code !== 11000) {
      console.error('❌ Error updating CreatorDailyStats:', error.message);
    } else {
      // If it was a race condition for the upsert, try one more time
      try {
        const today = new Date();
        today.setUTCHours(0, 0, 0, 0);
        await CreatorDailyStats.findOneAndUpdate(
          { creatorId, date: today },
          { $inc: increments }
        );
      } catch (retryError) {
        console.error('❌ Retry error updating CreatorDailyStats:', retryError.message);
      }
    }
  }
};
