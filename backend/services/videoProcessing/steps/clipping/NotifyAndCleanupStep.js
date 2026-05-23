import IBaseStep from '../../IBaseStep.js';
import fs from 'fs';
import User from '../../../../models/User.js';
import * as notificationService from '../../../notificationServices/notificationService.js';
import eventBus from '../../../../utils/eventBus.js';
import cloudflareR2Service from '../../../uploadServices/cloudflareR2Service.js';

/**
 * Step 4: Cleanup temp files and notify user
 */
export default class NotifyAndCleanupStep extends IBaseStep {
  constructor() {
    super('NotifyAndCleanup');
  }

  async execute(context) {
    // 1. Local Cleanup
    if (context.localClipPath && fs.existsSync(context.localClipPath)) {
      fs.unlinkSync(context.localClipPath);
    }

    // 2. R2 Source Cleanup (if ephemeral)
    if (context.isEphemeral && context.sourceKey) {
      try {
        await cloudflareR2Service.deleteVideoFromR2(context.sourceKey);
      } catch (e) {
        console.warn('⚠️ Ephemeral cleanup failed:', e.message);
      }
    }

    // 3. Notifications
    try {
      const user = await User.findById(context.userId);
      if (user && user.googleId) {
        await notificationService.sendNotificationToUser(user.googleId, {
          title: "Shorts Generator ✨",
          body: "Your shorts is ready tap to download 🥳",
          data: {
            type: "clipping_complete",
            jobId: context.clipId.toString(),
            videoUrl: context.result.url
          }
        });
      }
    } catch (e) {}

    eventBus.emit('clipping-status', {
      jobId: context.clipId.toString(),
      status: 'completed'
    });
  }
}
