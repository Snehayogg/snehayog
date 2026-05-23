import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../.env') });

// Import Video Model (using full path since we are in scripts/)
import Video from '../models/Video.js';

async function viewAnalysis() {
    try {
        console.log('🔌 Connecting to MongoDB...');
        await mongoose.connect(process.env.MONGO_URI);
        console.log('✅ Connected.\n');

        console.log('🔍 Fetching latest AI Analyzed videos...\n');
        
        const analyzedVideos = await Video.find({ 
            aiContextGenerated: true 
        }).sort({ updatedAt: -1 }).limit(5);

        if (analyzedVideos.length === 0) {
            console.log('❌ No AI analyzed videos found yet.');
            process.exit(0);
        }

        analyzedVideos.forEach((video, index) => {
            console.log(`🎬 --- [Video ${index + 1}] ---`);
            console.log(`📌 Title: ${video.videoName || 'Untitled'}`);
            console.log(`🌐 Language: ${video.language || 'Unknown'}`);
            console.log(`📍 Region: ${video.detectedRegion || 'Unknown'}`);
            console.log(`📝 AI Summary: ${video.aiContext || 'No summary'}`);
            console.log(`🏷️ Tags: ${video.tags ? video.tags.join(', ') : 'None'}`);
            console.log(`-----------------------------------\n`);
        });

        process.exit(0);
    } catch (error) {
        console.error('💥 Error:', error.message);
        process.exit(1);
    }
}

viewAnalysis();
