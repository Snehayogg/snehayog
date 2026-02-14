import hlsEncodingService from '../services/hlsEncodingService.js';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function getDirSize(dir) {
    const files = fs.readdirSync(dir, { recursive: true });
    let totalSize = 0;
    for (const file of files) {
        const filePath = path.join(dir, file);
        if (fs.statSync(filePath).isFile()) {
            totalSize += fs.statSync(filePath).size;
        }
    }
    return totalSize;
}

async function runBenchmark() {
    console.log('🚀 FFmpeg Quality & Size Comparison Benchmark');
    console.log('-------------------------------------------');

    // Use the largest file found: instagram_1761317653131_720p__1766323593729.mp4 (~4.3MB)
    const testVideo = path.join(__dirname, '../uploads/public/instagram_1761317653131_720p__1766323593729.mp4');
    
    if (!fs.existsSync(testVideo)) {
        console.error('❌ Test video not found');
        process.exit(1);
    }

    console.log(`📹 Using test video: ${path.basename(testVideo)} (~4.3MB)`);
    
    const presets = ['medium', 'fast', 'veryfast', 'ultrafast'];
    const results = [];

    for (const preset of presets) {
        console.log(`\n⏱️ Testing preset: ${preset.toUpperCase()}...`);
        const videoId = `bench_q_${preset}_${Date.now()}`;
        
        const startTime = Date.now();
        try {
            const result = await hlsEncodingService.convertToHLS(testVideo, videoId, {
                quality: 'medium',
                codec: 'h265',
                preset: preset
            });

            const duration = (Date.now() - startTime) / 1000;
            const outputSize = getDirSize(result.outputDir);
            
            results.push({ 
                preset, 
                duration, 
                sizeKB: (outputSize / 1024).toFixed(2),
                sizeMB: (outputSize / (1024 * 1024)).toFixed(2)
            });
            
            console.log(`✅ ${preset.toUpperCase()} completed in ${duration.toFixed(2)}s | Size: ${results[results.length-1].sizeMB} MB`);
            
            await hlsEncodingService.cleanupHLS(videoId);
        } catch (error) {
            console.error(`❌ ${preset.toUpperCase()} failed: ${error.message}`);
        }
    }

    console.log('\n📊 Detailed Comparison for 4.3MB input:');
    console.log('---------------------------------------');
    console.log('Preset    | Time (s) | Output Size (MB) | Extrapolated (40MB Input)');
    console.log('----------|----------|------------------|--------------------------');
    
    results.forEach(r => {
        const scaleFactor = 40 / 4.3;
        const estTime = (r.duration * scaleFactor).toFixed(2);
        const estSize = (parseFloat(r.sizeMB) * scaleFactor).toFixed(2);
        
        console.log(`${r.preset.padEnd(9)} | ${r.duration.toString().padEnd(8)} | ${r.sizeMB.toString().padEnd(16)} | Time: ~${estTime}s, Size: ~${estSize}MB`);
    });
    
    process.exit(0);
}

runBenchmark();
