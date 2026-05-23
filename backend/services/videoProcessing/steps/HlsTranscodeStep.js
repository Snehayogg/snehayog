import IBaseStep from '../IBaseStep.js';
import hybridVideoService from '../../uploadServices/hybridVideoService.js';
import Video from '../../../models/Video.js';

/**
 * Pipeline Step: HLS Transcoding
 */
class HlsTranscodeStep extends IBaseStep {
  constructor() {
    super('HlsTranscoding');
  }

  async execute(context) {
    const { videoId, localRawPath, videoName, userId } = context;
    
    let lastUpdate = 0;

    const hlsResult = await hybridVideoService.processVideoToHLS(
      localRawPath,
      videoName,
      userId,
      {
        videoId: videoId,
        onProgress: (percent) => {
          context.progress = percent;
          
          // Throttle DB updates to once every 3 seconds to avoid overloading MongoDB
          const now = Date.now();
          if (now - lastUpdate > 3000) {
            lastUpdate = now;
            Video.findByIdAndUpdate(videoId, { processingProgress: percent })
              .catch(err => console.warn('⚠️ Failed to update progress in DB:', err.message));
          }
        }
      }
    );

    // Save results to context for later steps
    context.hlsResult = hlsResult;

    // Update video record (Partial)
    await Video.findByIdAndUpdate(videoId, {
      videoUrl: hlsResult.videoUrl,
      hlsPlaylistUrl: hlsResult.hlsPlaylistUrl,
      isHLSEncoded: true,
      duration: hlsResult.duration,
      aspectRatio: hlsResult.aspectRatio,
      processingStatus: 'completed', // Mark completed early so users can watch immediately while AI processes in background
      processingProgress: 100
    });
  }
}

export default HlsTranscodeStep;
