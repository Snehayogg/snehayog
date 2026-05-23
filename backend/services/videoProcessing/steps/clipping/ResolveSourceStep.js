import IBaseStep from '../../IBaseStep.js';
import Video from '../../../../models/Video.js';
import cloudflareR2Service from '../../../uploadServices/cloudflareR2Service.js';

/**
 * Step 1: Resolve the source video key and URL
 */
export default class ResolveSourceStep extends IBaseStep {
  constructor() {
    super('ResolveSource');
  }

  async execute(context) {
    let sourceKey = context.sourceKey;

    if (context.originalVideoId) {
      const originalVideo = await Video.findById(context.originalVideoId);
      if (originalVideo) {
        sourceKey = originalVideo.canonicalMp4Key || originalVideo.rawVideoKey;
      }
    }

    if (!sourceKey) throw new Error('No source video key found');
    
    context.sourceKey = sourceKey;
    context.sourceUrl = cloudflareR2Service.getPublicUrl(sourceKey);
  }
}
