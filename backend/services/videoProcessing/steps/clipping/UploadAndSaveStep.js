import IBaseStep from '../../IBaseStep.js';
import cloudflareR2Service from '../../../uploadServices/cloudflareR2Service.js';
import Video from '../../../../models/Video.js';

/**
 * Step 3: Upload clip to R2 and update Video record
 */
export default class UploadAndSaveStep extends IBaseStep {
  constructor() {
    super('UploadAndSave');
  }

  async execute(context) {
    const { userId, clipId, localClipPath, videoName, duration } = context;
    const clipKey = `videos/${userId}/clips/${clipId}.mp4`;

    const uploadResult = await cloudflareR2Service.uploadFileToR2(localClipPath, clipKey, 'video/mp4');

    const videoData = {
      videoName: videoName || 'My Clip',
      uploader: userId,
      videoType: 'yog',
      mediaType: 'video',
      videoUrl: uploadResult.url,
      thumbnailUrl: uploadResult.url, 
      processingStatus: 'completed',
      processingProgress: 100,
      aspectRatio: 9/16,
      duration: duration,
      uploadedAt: new Date()
    };

    let clipVideo = await Video.findById(clipId);
    if (clipVideo) {
      Object.assign(clipVideo, videoData);
      await clipVideo.save();
    } else {
      clipVideo = new Video({ _id: clipId, ...videoData });
      await clipVideo.save();
    }

    context.result = { status: 'completed', clipId, url: uploadResult.url };
  }
}
