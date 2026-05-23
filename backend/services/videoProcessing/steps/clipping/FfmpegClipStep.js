import IBaseStep from '../../IBaseStep.js';
import videoClippingService from '../../../uploadServices/videoClippingService.js';
import path from 'path';
import fs from 'fs';

/**
 * Step 2: Generate the blurry vertical clip using FFmpeg
 */
export default class FfmpegClipStep extends IBaseStep {
  constructor() {
    super('FfmpegClip');
  }

  async execute(context) {
    const tempDir = path.join(process.cwd(), 'temp_raw_downloads');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

    const localClipPath = path.join(tempDir, `${context.clipId}_clip.mp4`);
    
    console.log(`🎬 Streaming and clipping from: ${context.sourceUrl}`);

    await videoClippingService.generateBlurryVerticalClip(context.sourceUrl, localClipPath, {
      startTime: context.startTime,
      duration: context.duration
    });

    context.localClipPath = localClipPath;
  }
}
