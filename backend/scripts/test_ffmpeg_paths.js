
import ffmpegStatic from 'ffmpeg-static';
import ffprobeStatic from 'ffprobe-static';
import { spawnSync } from 'child_process';
import fs from 'fs';

console.log('🔍 Testing Local FFmpeg Configuration...');

// 1. Check Paths
console.log('\n1️⃣  Path Resolution:');
console.log('   ffmpeg-static path:', ffmpegStatic || '❌ NULL');
console.log('   ffprobe-static path:', ffprobeStatic.path || '❌ NULL');

// 2. Verify File Existence
console.log('\n2️⃣  File Existence Check:');
if (ffmpegStatic) {
    console.log('   ffmpeg exists?', fs.existsSync(ffmpegStatic) ? '✅ YES' : '❌ NO');
}
if (ffprobeStatic.path) {
    console.log('   ffprobe exists?', fs.existsSync(ffprobeStatic.path) ? '✅ YES' : '❌ NO');
}

// 3. Try Execution
console.log('\n3️⃣  Execution Test:');

if (ffmpegStatic && fs.existsSync(ffmpegStatic)) {
    try {
        const ff = spawnSync(ffmpegStatic, ['-version']);
        if (ff.error) {
             console.log('   ❌ FFmpeg Execution Error:', ff.error.message);
        } else {
             console.log('   ✅ FFmpeg Version:\n', ff.stdout.toString().split('\n')[0]);
        }
    } catch (e) {
        console.log('   ❌ FFmpeg Spawn Failed:', e.message);
    }
} else {
    console.log('   ⚠️ Skipping FFmpeg execution test (missing file)');
}

if (ffprobeStatic.path && fs.existsSync(ffprobeStatic.path)) {
    try {
        const fp = spawnSync(ffprobeStatic.path, ['-version']);
         if (fp.error) {
             console.log('   ❌ FFprobe Execution Error:', fp.error.message);
        } else {
             console.log('   ✅ FFprobe Version:\n', fp.stdout.toString().split('\n')[0]);
        }
    } catch (e) {
        console.log('   ❌ FFprobe Spawn Failed:', e.message);
    }
} else {
    console.log('   ⚠️ Skipping FFprobe execution test (missing file)');
}
