import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

// Setup environment
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env');

if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath });
} else {
    dotenv.config();
}

import '../models/index.js';
const Video = mongoose.model('Video');

const MONGODB_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/snehayog';

// ─────────────────────────────────────────────
// Fix ONE video's metadata
// ─────────────────────────────────────────────
async function fixOneVideo(video, targetType, dryRun = false) {
    const originalType = video.videoType;
    const originalAR   = video.aspectRatio;

    if (targetType === 'yog') {
        // Swap dimensions if stored as landscape
        if (video.originalResolution?.width > video.originalResolution?.height) {
            [video.originalResolution.width, video.originalResolution.height] =
                [video.originalResolution.height, video.originalResolution.width];
        }
        // Invert aspect ratio
        if (video.aspectRatio > 1) {
            video.aspectRatio = 1 / video.aspectRatio;
        } else if (!video.aspectRatio || video.aspectRatio === 0) {
            video.aspectRatio = 9 / 16;
        }
        video.videoType = 'yog';

    } else if (targetType === 'vayu') {
        // Swap dimensions if stored as portrait
        if (video.originalResolution?.height > video.originalResolution?.width) {
            [video.originalResolution.width, video.originalResolution.height] =
                [video.originalResolution.height, video.originalResolution.width];
        }
        if (video.aspectRatio < 1 && video.aspectRatio > 0) {
            video.aspectRatio = 1 / video.aspectRatio;
        } else if (!video.aspectRatio || video.aspectRatio === 0) {
            video.aspectRatio = 16 / 9;
        }
        video.videoType = 'vayu';
    }

    if (!dryRun) await video.save();

    console.log(`  ${dryRun ? '[DRY-RUN] Would fix' : '✅ Fixed'}: "${video.videoName}"`);
    console.log(`    ${originalType} (AR: ${originalAR?.toFixed(4)}) → ${video.videoType} (AR: ${video.aspectRatio?.toFixed(4)})`);
}

// ─────────────────────────────────────────────
// AUTO mode: find all mismatched videos in DB
// ─────────────────────────────────────────────
async function autoFix(dryRun = false) {
    console.log(`\n🔍 Scanning all videos for type/aspectRatio mismatch...`);
    console.log(dryRun ? '⚠️  DRY-RUN mode: no changes will be saved\n' : '');

    // Mismatch type 1: labelled 'vayu' (landscape) but AR < 1 (portrait)
    const wronglyVayu = await Video.find({
        videoType: 'vayu',
        aspectRatio: { $lt: 1, $gt: 0 }
    });

    // Mismatch type 2: labelled 'yog' (portrait) but AR > 1 (landscape)
    const wronglyYog = await Video.find({
        videoType: 'yog',
        aspectRatio: { $gt: 1 }
    });

    console.log(`📊 Found ${wronglyVayu.length} videos labelled "vayu" but with portrait aspect ratio`);
    console.log(`📊 Found ${wronglyYog.length} videos labelled "yog" but with landscape aspect ratio`);
    console.log('');

    let fixed = 0, errors = 0;

    for (const video of wronglyVayu) {
        try {
            await fixOneVideo(video, 'yog', dryRun);
            fixed++;
        } catch (e) {
            console.error(`  ❌ Failed: ${video._id} - ${e.message}`);
            errors++;
        }
    }

    for (const video of wronglyYog) {
        try {
            await fixOneVideo(video, 'vayu', dryRun);
            fixed++;
        } catch (e) {
            console.error(`  ❌ Failed: ${video._id} - ${e.message}`);
            errors++;
        }
    }

    console.log(`\n📊 Summary: ${fixed} fixed, ${errors} errors`);
}

// ─────────────────────────────────────────────
// MANUAL mode: fix specific video IDs
// ─────────────────────────────────────────────
async function manualFix(videoIds, targetType, dryRun = false) {
    console.log(`\n🔧 Manual fix for ${videoIds.length} video(s) → target type: ${targetType}`);
    console.log(dryRun ? '⚠️  DRY-RUN mode: no changes will be saved\n' : '');

    let fixed = 0, errors = 0;

    for (const id of videoIds) {
        const video = await Video.findById(id);
        if (!video) {
            console.error(`  ❌ Video not found: ${id}`);
            errors++;
            continue;
        }
        try {
            await fixOneVideo(video, targetType, dryRun);
            fixed++;
        } catch (e) {
            console.error(`  ❌ Failed: ${id} - ${e.message}`);
            errors++;
        }
    }

    console.log(`\n📊 Summary: ${fixed} fixed, ${errors} errors`);
}

// ─────────────────────────────────────────────
// MAIN: parse CLI and run
// ─────────────────────────────────────────────
const args      = process.argv.slice(2);
const isAuto    = args.includes('--auto');
const isDryRun  = args.includes('--dry-run');
const isVayu    = args.includes('--vayu');
const targetType = isVayu ? 'vayu' : 'yog';
const videoIds   = args.filter(a => !a.startsWith('--'));

if (!isAuto && videoIds.length === 0) {
    console.log(`
Usage:
  Auto-fix all mismatched videos:
    node scripts/fix_video_metadata.js --auto
    node scripts/fix_video_metadata.js --auto --dry-run   (preview only)

  Fix specific video IDs:
    node scripts/fix_video_metadata.js <id1> <id2> --yog
    node scripts/fix_video_metadata.js <id1> <id2> --vayu
`);
    process.exit(1);
}

try {
    console.log('🔌 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected\n');

    if (isAuto) {
        await autoFix(isDryRun);
    } else {
        await manualFix(videoIds, targetType, isDryRun);
    }

} catch (err) {
    console.error('❌ Fatal error:', err.message);
} finally {
    await mongoose.disconnect();
    console.log('\n👋 Disconnected');
}
