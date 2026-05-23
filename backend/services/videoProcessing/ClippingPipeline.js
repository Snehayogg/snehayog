import ResolveSourceStep from './steps/clipping/ResolveSourceStep.js';
import FfmpegClipStep from './steps/clipping/FfmpegClipStep.js';
import UploadAndSaveStep from './steps/clipping/UploadAndSaveStep.js';
import NotifyAndCleanupStep from './steps/clipping/NotifyAndCleanupStep.js';

/**
 * ClippingPipeline
 * Orchestrates the creation of short clips from long videos.
 */
class ClippingPipeline {
  constructor() {
    this.steps = [
      new ResolveSourceStep(),
      new FfmpegClipStep(),
      new UploadAndSaveStep(),
      new NotifyAndCleanupStep()
    ];
  }

  async run(context) {
    console.log(`🎬 ClippingPipeline: Starting job for ${context.videoName || 'Unnamed Clip'}`);
    
    // Ensure we have a Target ID
    if (!context.clipId) {
      context.clipId = context.targetVideoId ? 
        new mongoose.Types.ObjectId(context.targetVideoId) : 
        new mongoose.Types.ObjectId();
    }

    for (const step of this.steps) {
      try {
        console.log(`  ➔ Step: ${step.name}`);
        await step.execute(context);
      } catch (error) {
        console.error(`  ❌ Step ${step.name} failed:`, error.message);
        throw error;
      }
    }

    console.log(`✅ ClippingPipeline: Finished successfully for ${context.clipId}`);
    return context.result;
  }
}

export default new ClippingPipeline();
