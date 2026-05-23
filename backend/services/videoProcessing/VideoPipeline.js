import Video from '../../models/Video.js';
import fs from 'fs';

/**
 * FFmpeg-style Video Processing Engine (The Orchestrator)
 */
class VideoPipeline {
  constructor() {
    this.steps = [];
  }

  /**
   * Add a step to the pipeline
   * @param {IBaseStep} step 
   */
  addStep(step) {
    this.steps.push(step);
    return this;
  }

  /**
   * Run the full pipeline for a video
   * @param {Object} initialContext - Initial data (videoId, etc.)
   */
  async run(initialContext) {
    const { videoId } = initialContext;
    const context = { ...initialContext };
    
    console.log(`🎬 Pipeline: Starting for video ${videoId}`);

    try {
      for (const step of this.steps) {
        console.log(`⏳ Pipeline: Executing [${step.getName()}]...`);
        await step.execute(context);
        
        // Optional: Update progress in DB if available
        if (context.progress) {
          await Video.findByIdAndUpdate(videoId, { processingProgress: context.progress });
        }
      }
      
      console.log(`✅ Pipeline: Completed successfully for ${videoId}`);
      return context;
    } catch (error) {
      console.error(`❌ Pipeline: Failed at step for ${videoId}:`, error);
      
      // Update DB with failure
      await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'failed',
        processingError: error.message 
      });
      
      // Cleanup local temp file on ANY failure to save disk space
      if (context.localRawPath && fs.existsSync(context.localRawPath)) {
        try {
          fs.unlinkSync(context.localRawPath);
          console.log(`🧹 Pipeline: Cleaned up local file after failure: ${context.localRawPath}`);
        } catch (cleanupErr) {
          console.warn('⚠️ Pipeline: Failed to clean up local file on failure:', cleanupErr.message);
        }
      }
      
      throw error;
    }
  }
}

export default VideoPipeline;
