import ffmpeg from 'fluent-ffmpeg';
import path from 'path';
import fs from 'fs';

class VideoClippingService {
    /**
     * Generate a 9:16 vertical clip with a blurry background from a horizontal video.
     * @param {string} inputPath - Local path to source video
     * @param {string} outputPath - Local path for output video
     * @param {Object} options - { startTime, duration, width, height }
     */
    async generateBlurryVerticalClip(inputPath, outputPath, options = {}) {
        let { startTime = 0, duration = 30, width = 1080, height = 1920 } = options;

        // **FIX: Handle special characters in URLs (like Hindi script)**
        const normalizedInput = inputPath.startsWith('http') ? encodeURI(inputPath) : inputPath;

        // Auto-assign random start time if requested
        if (startTime === 'random') {
            try {
                const metadata = await new Promise((resolve, reject) => {
                    ffmpeg.ffprobe(normalizedInput, (err, data) => {
                        if (err) reject(err);
                        else resolve(data);
                    });
                });
                const totalDuration = metadata.format.duration;
                if (totalDuration > duration) {
                    // Start at least 'duration' seconds before the end
                    startTime = Math.floor(Math.random() * (totalDuration - duration));
                } else {
                    startTime = 0;
                }
                console.log(`🎲 Random start time selected: ${startTime}s for video of ${totalDuration}s`);
            } catch (err) {
                console.error('⚠️ Failed to calculate random start time, defaulting to 0:', err.message);
                startTime = 0;
            }
        }

        return new Promise((resolve, reject) => {
            // **PERFORMANCE OPTIMIZATION: Blurry Background**
            // 1. Split input into two streams [v1] and [v2]
            // 2. [v1] Scale to LOW resolution first (speed!), blur, then scale up -> [bg]
            // 3. [v2] Scale to fit width (1080:-1) -> [fg]
            // 4. Overlay [fg] on top of [bg], centered.
            const filter = [
                'split[v1][v2]',
                `[v1]scale=320:568,boxblur=20:10,scale=${width}:${height}[bg]`,
                `[v2]scale=${width}:-1[fg]`,
                `[bg][fg]overlay=(W-w)/2:(H-h)/2`
            ].join(';');

            ffmpeg(normalizedInput)
                .setStartTime(startTime)
                .setDuration(duration)
                .videoFilters(filter)
                .outputOptions([
                    '-c:v libx264',
                    '-preset ultrafast', // MAX SPEED
                    '-crf 23',
                    '-threads 0',        // Use all CPU cores
                    '-c:a copy'
                ])
                .output(outputPath)
                .on('start', (cmd) => {
                    console.log('🎬 Executing FFmpeg clipping command:', cmd);
                })
                .on('progress', (progress) => {
                    console.log(`⏳ Clipping progress: ${progress.percent}%`);
                })
                .on('end', () => {
                    console.log('✅ Blurry vertical clip generated successfully.');
                    resolve(outputPath);
                })
                .on('error', (err) => {
                    console.error('❌ FFmpeg clipping error:', err.message);
                    reject(err);
                })
                .run();
        });
    }
}

export default new VideoClippingService();
