import 'dotenv/config';
import mongoose from 'mongoose';
import User from '../models/User.js';
import Follower from '../models/Follower.js';
import SavedVideo from '../models/SavedVideo.js';
import databaseManager from '../config/database.js';

async function migrate() {
    try {
        console.log('🚀 Starting Data Migration: User Arrays to Collections');
        await databaseManager.connect();
        
        const users = await User.find({});
        console.log(`📊 Found ${users.length} users to process`);
        
        let totalFollowsMigrated = 0;
        let totalSavesMigrated = 0;
        
        for (const user of users) {
            console.log(`\n👤 Processing User: ${user.name} (${user.googleId})`);
            
            // 1. Migrate Following (from the user's following array)
            // Note: We only need to migrate the 'following' relationship from the perspective of the user.
            // The 'followers' collection is bidirectional by design ({ follower, following }).
            if (user.following && user.following.length > 0) {
                console.log(`  🔗 Migrating ${user.following.length} following entries...`);
                for (const targetId of user.following) {
                    try {
                        await Follower.findOneAndUpdate(
                            { follower: user._id, following: targetId },
                            { follower: user._id, following: targetId },
                            { upsert: true }
                        );
                        totalFollowsMigrated++;
                    } catch (e) {
                        console.error(`    ❌ Failed to migrate follow to ${targetId}:`, e.message);
                    }
                }
            }
            
            // 2. Migrate Saved Videos
            if (user.savedVideos && user.savedVideos.length > 0) {
                console.log(`  🔖 Migrating ${user.savedVideos.length} saved videos...`);
                for (const videoId of user.savedVideos) {
                    try {
                        await SavedVideo.findOneAndUpdate(
                            { user: user._id, video: videoId },
                            { user: user._id, video: videoId },
                            { upsert: true }
                        );
                        totalSavesMigrated++;
                    } catch (e) {
                        console.error(`    ❌ Failed to migrate saved video ${videoId}:`, e.message);
                    }
                }
            }
            
            // 3. Initialize/Correction Counters
            // We'll calculate the accurate counts now
            const followingCount = await Follower.countDocuments({ follower: user._id });
            const followerCount = await Follower.countDocuments({ following: user._id });
            const savedVideosCount = await SavedVideo.countDocuments({ user: user._id });
            
            await User.updateOne(
                { _id: user._id },
                { 
                    $set: { 
                        followingCount, 
                        followerCount, 
                        savedVideosCount 
                    } 
                }
            );
            
            console.log(`  ✅ Updated counters: Following: ${followingCount}, Followers: ${followerCount}, Saved: ${savedVideosCount}`);
        }
        
        console.log('\n--- Migration Summary ---');
        console.log(`✅ Total Follow documents created/updated: ${totalFollowsMigrated}`);
        console.log(`✅ Total SavedVideo documents created/updated: ${totalSavesMigrated}`);
        console.log('🚀 Migration finished successfully');
        
        process.exit(0);
    } catch (error) {
        console.error('❌ Migration failed:', error);
        process.exit(1);
    }
}

migrate();
