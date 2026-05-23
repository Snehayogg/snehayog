import VideoPipeline from './VideoPipeline.js';
import DownloadStep from './steps/DownloadStep.js';
import HlsTranscodeStep from './steps/HlsTranscodeStep.js';
import AiAnalysisStep from './steps/AiAnalysisStep.js';
import CleanupStep from './steps/CleanupStep.js';

/**
 * Standard Video Processing Pipeline
 */
const defaultPipeline = new VideoPipeline();

defaultPipeline
  .addStep(new DownloadStep())
  .addStep(new HlsTranscodeStep())
  .addStep(new CleanupStep());

export default defaultPipeline;
