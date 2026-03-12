/**
 * reprobe_videos.js
 * 
 * Re-probes actual video files from CDN using ffprobe to get GROUND TRUTH dimensions.
 * Then updates videoType and aspectRatio in MongoDB if they are wrong.
 * 
 * Use cases:
 *   --auto       : Scan all videos in DB, re-probe each one from CDN
 *   --vayu-only  : Only re-probe videos currently labelled 'vayu'
 *   --yog-only   : Only re-probe videos currently labelled 'yog'
 *   --dry-run    : Show what would change, don't save anything
 *   --limit N    : Only process first N videos (for testing)
 * 
 * Usage:
 *   node scripts/reprobe_videos.js --vayu-only --dry-run
 *   node scripts/reprobe_videos.js --auto
 */

import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import ffmpeg from 'fluent-ffmpeg';
import ffmpegPath from 'ffmpeg-static';
import ffprobePath from 'ffprobe-static';

// Setup environment
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env');
if (fs.existsSync(envPath)) dotenv.config({ path: envPath });
else dotenv.config();

// Configure ffmpeg binaries
if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);
if (ffprobePath?.path) ffmpeg.setFfprobePath(ffprobePath.path);

import '../models/index.js';
const Video = mongoose.model('Video');

const MONGODB_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/snehayog';

// ─────────────────────────────────────────────────────────
// Probe a video URL and return real dimensions + aspect ratio
// ─────────────────────────────────────────────────────────
function probeUrl(url) {
    return new Promise((resolve, reject) => {
        ffmpeg.ffprobe(url, (err, metadata) => {
            if (err) return reject(new Error(`ffprobe failed: ${err.message}`));

            try {
                const videoStream = metadata.streams.find(s => s.codec_type === 'video');
                if (!videoStream) return reject(new Error('No video stream found'));

                let width  = parseInt(videoStream.width, 10)  || 0;
                let height = parseInt(videoStream.height, 10) || 0;

                // Handle rotation metadata (critical for mobile recordings)
                let rotation = 0;
                if (videoStream.tags?.rotate) {
                    rotation = parseInt(videoStream.tags.rotate, 10) || 0;
                }
                if (videoStream.side_data_list?.length > 0) {
                    const dm = videoStream.side_data_list.find(sd => sd.side_data_type === 'Display Matrix');
                    if (dm?.rotation) rotation = parseInt(dm.rotation, 10) || 0;
                }

                // Swap width/height if rotated 90° or 270° (portrait shot on mobile)
                if (Math.abs(rotation) === 90 || Math.abs(rotation) === 270) {
                    [width, height] = [height, width];
                }

                const aspectRatio = (width > 0 && height > 0) ? width / height : null;
                const videoType   = (aspectRatio !== null && aspectRatio >= 1.0) ? 'vayu' : 'yog';

                resolve({ width, height, aspectRatio, videoType, rotation });
            } catch (e) {
                reject(new Error(`Parse error: ${e.message}`));
            }
        });
    });
}

// ─────────────────────────────────────────────────────────
// Process one video: probe → compare → update
// ─────────────────────────────────────────────────────────
async function processVideo(video, dryRun = false) {
    const probeUrl_str = video.videoUrl || video.hlsPlaylistUrl;
    if (!probeUrl_str) {
        return { status: 'skipped', reason: 'no URL' };
    }

    let real;
    try {
        real = await probeUrl(probeUrl_str);
    } catch (e) {
        return { status: 'error', reason: e.message };
    }

    if (real.aspectRatio === null) {
        return { status: 'skipped', reason: 'could not get dimensions' };
    }

    const storedAR   = video.aspectRatio;
    const storedType = video.videoType;
    const realType   = real.videoType;

    // Significant difference threshold: if stored AR differs by > 10% from real → fix it
    const ARdiff = Math.abs((storedAR - real.aspectRatio) / (real.aspectRatio || 1));
    const typeWrong = storedType !== realType;
    const arWrong   = ARdiff > 0.10;

    if (!typeWrong && !arWrong) {
        return { status: 'ok' };
    }

    // Log what changed
    const changes = [];
    if (typeWrong) changes.push(`videoType: ${storedType} → ${realType}`);
    if (arWrong)   changes.push(`AR: ${storedAR?.toFixed(4)} → ${real.aspectRatio.toFixed(4)}`);

    if (!dryRun) {
        video.videoType = realType;
        video.aspectRatio = real.aspectRatio;
        if (video.originalResolution) {
            video.originalResolution.width  = real.width;
            video.originalResolution.height = real.height;
        }
        await video.save();
    }

    return { status: dryRun ? 'would-fix' : 'fixed', changes };
}

// ─────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────
const args      = process.argv.slice(2);
const dryRun    = args.includes('--dry-run');
const vayuOnly  = args.includes('--vayu-only');
const yogOnly   = args.includes('--yog-only');
const limitArg  = args.find(a => a.startsWith('--limit='));
const limit     = limitArg ? parseInt(limitArg.split('=')[1]) : 0;

const filter = {};
if (vayuOnly) filter.videoType = 'vayu';
if (yogOnly)  filter.videoType = 'yog';
// Only target videos that have a URL (required for probing)
filter.videoUrl = { $exists: true, $ne: '' };

console.log('🔌 Connecting to MongoDB...');
await mongoose.connect(MONGODB_URI);
console.log('✅ Connected\n');

let query = Video.find(filter).select('videoName videoUrl hlsPlaylistUrl videoType aspectRatio originalResolution');
if (limit > 0) query = query.limit(limit);

const videos = await query.exec();
console.log(`📊 Found ${videos.length} videos to probe${limit ? ` (limited to ${limit})` : ''}`);
console.log(dryRun ? '⚠️  DRY-RUN mode — no changes will be saved\n' : '');

let fixed = 0, ok = 0, errors = 0, skipped = 0;

for (let i = 0; i < videos.length; i++) {
    const video = videos[i];
    const prefix = `[${i + 1}/${videos.length}]`;

    process.stdout.write(`${prefix} "${video.videoName?.substring(0, 50)}..." `);

    const result = await processVideo(video, dryRun);

    if (result.status === 'ok') {
        process.stdout.write('✅ ok\n');
        ok++;
    } else if (result.status === 'fixed' || result.status === 'would-fix') {
        process.stdout.write(`🔄 ${result.status}: ${result.changes.join(', ')}\n`);
        fixed++;
    } else if (result.status === 'error') {
        process.stdout.write(`❌ error: ${result.reason}\n`);
        errors++;
    } else {
        process.stdout.write(`⏭️  skipped: ${result.reason}\n`);
        skipped++;
    }
}

console.log(`
════════════════════════════════
📊 Summary:
  ✅ Already correct : ${ok}
  🔄 Fixed           : ${fixed}
  ⏭️  Skipped         : ${skipped}
  ❌ Errors           : ${errors}
  Total              : ${videos.length}
════════════════════════════════`);

await mongoose.disconnect();
console.log('👋 Disconnected');
