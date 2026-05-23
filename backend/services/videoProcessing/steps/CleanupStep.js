import IBaseStep from '../IBaseStep.js';
import storageManager from '../../storageSystem/StorageManager.js';
import fs from 'fs';

/**
 * Pipeline Step: Final Cleanup
 */
class CleanupStep extends IBaseStep {
  constructor() {
    super('FinalCleanup');
  }

  async execute(context) {
    const { videoId, rawVideoKey, localRawPath, hlsResult } = context;

    // 1. Delete original from R2 if encoded successfully
    if (rawVideoKey && hlsResult) {
      try {
        console.log(`🧹 CleanupStep: Deleting source from R2: ${rawVideoKey}`);
        await storageManager.active.delete(rawVideoKey);
      } catch (e) {
        console.warn('⚠️ CleanupStep: Failed to delete R2 source:', e.message);
      }
    }

    // 2. Delete local temp file
    if (localRawPath && fs.existsSync(localRawPath)) {
      try {
        fs.unlinkSync(localRawPath);
        console.log(`🧹 CleanupStep: Local file deleted: ${localRawPath}`);
      } catch (e) {
        console.warn('⚠️ CleanupStep: Failed to delete local file:', e.message);
      }
    }

    context.progress = 100;
  }
}

export default CleanupStep;
