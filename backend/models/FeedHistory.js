import mongoose from 'mongoose';

/**
 * FeedHistory Model
 * Tracks which videos have been "impressed" (shown in feed) to a user.
 * This is stricter than WatchHistory - if it appeared in their feed, we count it as "seen"
 * to avoid showing it again until we run out of fresh content (LRU fallback).
 */
const FeedHistorySchema = new mongoose.Schema({
    userId: {
        type: String, // Google ID (for authenticated users) or deviceId (for anonymous users)
        required: true,
        index: true
    },
    videoId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Video',
        required: true,
        index: true
    },
    seenAt: {
        type: Date,
        default: Date.now,
        index: true
    }
}, {
    timestamps: true
});

// **Composite Indexes for Performance**

// 1. Unique constraint: A user should only have ONE entry per video.
// If they see it again (via LRU fallback), we just update 'seenAt'.
FeedHistorySchema.index({ userId: 1, videoId: 1 }, { unique: true });

// 2. LRU Sort Index: Quickly find "oldest seen" videos for a user
FeedHistorySchema.index({ userId: 1, seenAt: 1 });

/**
 * Static method to mark videos as seen
 * Uses bulkWrite for performance since we might mark batch of 10 videos at once
 */
FeedHistorySchema.statics.markAsSeen = async function (userId, videoIds) {
    if (!videoIds || videoIds.length === 0) return;

    const uniqueVideoIds = [...new Set(videoIds.map(id => id.toString()))];
    const ops = uniqueVideoIds.map(videoId => ({
        updateOne: {
            filter: { userId, videoId },
            update: { $set: { seenAt: new Date() } }, // Update timestamp to NOW (becomes "most recently used")
            upsert: true
        }
    }));

    try {
        await this.bulkWrite(ops, { ordered: false });
    } catch (error) {
        console.error('❌ Error marking videos as seen:', error);
        // Non-critical error, don't throw
    }
};

/**
 * Get all seen video IDs for a user
 * Returns Set<String> for O(1) lookups
 */
FeedHistorySchema.statics.getSeenVideoIds = async function (userId) {
    try {
        const docs = await this.find({ userId }).select('videoId').lean();
        return new Set(docs.map(d => d.videoId.toString()));
    } catch (error) {
        console.error('❌ Error fetching seen history:', error);
        return new Set();
    }
};

/**
 * Get LRU (Least Recently Used) videos for fallback
 * Returns videoIds sorted by seenAt ASC (Oldest seen first)
 */
FeedHistorySchema.statics.getLRUVideos = async function (userId, limit = 10, excludeIds = []) {
    try {
        const docs = await this.find({
            userId,
            videoId: { $nin: excludeIds }
        })
            .sort({ seenAt: 1 }) // Oldest first
            .limit(limit)
            .select('videoId')
            .lean();

        return docs.map(d => d.videoId);
    } catch (error) {
        console.error('❌ Error fetching LRU videos:', error);
        return [];
    }
};

const FeedHistory = mongoose.model('FeedHistory', FeedHistorySchema);

export default FeedHistory;
