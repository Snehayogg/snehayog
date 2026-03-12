import mongoose from 'mongoose';
import dotenv from 'dotenv';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import ffmpegStatic from 'ffmpeg-static';
import ffprobeStatic from 'ffprobe-static';
import Video from '../models/Video.js';

dotenv.config();

const FFPROBE_PATH = process.env.FFPROBE_PATH || ffprobeStatic?.path;
const FFMPEG_PATH = process.env.FFMPEG_PATH || ffmpegStatic;
const DEFAULT_CONCURRENCY = 2;
const DEFAULT_ASPECT_TOLERANCE = 0.02;
const CONFIDENCE_ORDER = { low: 1, medium: 2, high: 3 };

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: null,
    ids: [],
    videoType: null,
    concurrency: DEFAULT_CONCURRENCY,
    syncResolution: false,
    contentDetect: 'auto',
    minimumConfidence: 'medium',
    reportPath: null,
    includeStatuses: ['completed'],
    sampleCount: 3,
    help: false
  };

  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
      continue;
    }
    if (arg === '--sync-resolution') {
      options.syncResolution = true;
      continue;
    }
    if (arg === '--help' || arg === '-h') {
      options.help = true;
      continue;
    }
    if (arg.startsWith('--limit=')) {
      options.limit = Math.max(1, parseInt(arg.split('=')[1], 10) || 0);
      continue;
    }
    if (arg.startsWith('--id=')) {
      options.ids.push(arg.split('=')[1]);
      continue;
    }
    if (arg.startsWith('--video-type=')) {
      options.videoType = arg.split('=')[1]?.toLowerCase() || null;
      continue;
    }
    if (arg.startsWith('--concurrency=')) {
      options.concurrency = Math.max(1, parseInt(arg.split('=')[1], 10) || DEFAULT_CONCURRENCY);
      continue;
    }
    if (arg.startsWith('--content-detect=')) {
      const value = arg.split('=')[1]?.toLowerCase();
      if (['auto', 'always', 'never'].includes(value)) {
        options.contentDetect = value;
      }
      continue;
    }
    if (arg.startsWith('--minimum-confidence=')) {
      const value = arg.split('=')[1]?.toLowerCase();
      if (CONFIDENCE_ORDER[value]) {
        options.minimumConfidence = value;
      }
      continue;
    }
    if (arg.startsWith('--report=')) {
      options.reportPath = arg.split('=')[1];
      continue;
    }
    if (arg.startsWith('--statuses=')) {
      options.includeStatuses = arg
        .split('=')[1]
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
      continue;
    }
    if (arg.startsWith('--samples=')) {
      options.sampleCount = Math.max(1, Math.min(5, parseInt(arg.split('=')[1], 10) || 3));
    }
  }

  return options;
}

function printHelp() {
  console.log(`
Usage:
  node scripts/classify-existing-videos.js [options]

Options:
  --apply                      Persist updates to MongoDB. Default is dry-run.
  --limit=<n>                  Process only the first n matching videos.
  --id=<mongoId>               Process a specific video. Can be repeated.
  --video-type=<yog|vayu>      Filter by current stored videoType.
  --concurrency=<n>            Number of videos to inspect in parallel. Default: 2.
  --content-detect=<mode>      auto | always | never. Default: auto.
  --samples=<n>                Cropdetect samples per video when enabled. Default: 3.
  --minimum-confidence=<level> low | medium | high. Default: medium.
  --sync-resolution            Also overwrite originalResolution using the chosen basis.
  --report=<path>              Write a JSON report to the provided path.
  --statuses=a,b               Processing statuses to include. Default: completed.
  --help                       Show this help.

Examples:
  node scripts/classify-existing-videos.js --limit=20
  node scripts/classify-existing-videos.js --apply --sync-resolution
  node scripts/classify-existing-videos.js --video-type=vayu --content-detect=always --apply
`);
}

function isHttpUrl(value) {
  return typeof value === 'string' && /^https?:\/\//i.test(value);
}

function fileExists(value) {
  try {
    return !!value && fs.existsSync(value);
  } catch {
    return false;
  }
}

function asAbsoluteLocalPath(value) {
  if (!value || typeof value !== 'string') {
    return null;
  }

  if (fileExists(value)) {
    return value;
  }

  const trimmed = value.replace(/^https?:\/\/[^/]+/i, '');
  const normalized = trimmed.replace(/^\/+/, '').replace(/\//g, path.sep);
  const candidates = [
    path.join(process.cwd(), normalized),
    path.join(process.cwd(), '..', normalized),
    path.join(process.cwd(), 'uploads', path.basename(normalized))
  ];

  return candidates.find(fileExists) || null;
}

function unique(values) {
  return Array.from(new Set(values.filter(Boolean)));
}

function getCandidateSources(video) {
  return unique([
    asAbsoluteLocalPath(video.videoUrl),
    asAbsoluteLocalPath(video.hlsMasterPlaylistUrl),
    asAbsoluteLocalPath(video.hlsPlaylistUrl),
    video.videoUrl,
    video.hlsMasterPlaylistUrl,
    video.hlsPlaylistUrl
  ]);
}

function parseNumeric(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function parseRatio(value) {
  if (!value || value === '0:1' || value === 'N/A') {
    return null;
  }

  if (typeof value === 'number') {
    return Number.isFinite(value) && value > 0 ? value : null;
  }

  const text = String(value).trim();
  if (!text) {
    return null;
  }

  if (text.includes(':')) {
    const [numerator, denominator] = text.split(':').map((part) => parseNumeric(part));
    return numerator > 0 && denominator > 0 ? numerator / denominator : null;
  }

  const numeric = parseNumeric(text);
  return numeric > 0 ? numeric : null;
}

function normalizeRotation(rotation) {
  const numeric = parseInt(rotation, 10);
  if (!Number.isFinite(numeric)) {
    return 0;
  }

  let normalized = numeric % 360;
  if (normalized < 0) {
    normalized += 360;
  }
  return normalized;
}

function extractRotation(videoStream) {
  const tagRotation = normalizeRotation(videoStream?.tags?.rotate);
  if (tagRotation) {
    return tagRotation;
  }

  const sideData = Array.isArray(videoStream?.side_data_list)
    ? videoStream.side_data_list.find((item) => item?.side_data_type === 'Display Matrix' && item.rotation !== undefined)
    : null;

  return normalizeRotation(sideData?.rotation);
}

function createDisplayDimensions(videoStream) {
  const rawWidth = parseNumeric(videoStream?.width);
  const rawHeight = parseNumeric(videoStream?.height);
  const rotation = extractRotation(videoStream);
  const sar = parseRatio(videoStream?.sample_aspect_ratio) || 1;

  let displayWidth = rawWidth * sar;
  let displayHeight = rawHeight;

  if (rotation === 90 || rotation === 270) {
    [displayWidth, displayHeight] = [displayHeight, displayWidth];
  }

  const dar = parseRatio(videoStream?.display_aspect_ratio);
  if (dar && displayWidth > 0 && displayHeight > 0) {
    const current = displayWidth / displayHeight;
    if (Math.abs(current - dar) > 0.01) {
      displayWidth = Math.round(displayHeight * dar);
    }
  }

  return {
    rawWidth,
    rawHeight,
    displayWidth: Math.round(displayWidth),
    displayHeight: Math.round(displayHeight),
    rotation,
    sar
  };
}

function runProcess(binaryPath, args) {
  return new Promise((resolve, reject) => {
    if (!binaryPath) {
      reject(new Error('Required binary path is not configured'));
      return;
    }

    const child = spawn(binaryPath, args, {
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', (error) => reject(error));
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }

      const error = new Error(`Process exited with code ${code}`);
      error.stdout = stdout;
      error.stderr = stderr;
      reject(error);
    });
  });
}

async function probeSource(source) {
  const args = [
    '-v', 'error',
    '-print_format', 'json',
    '-show_format',
    '-show_streams',
    source
  ];

  if (isHttpUrl(source)) {
    args.unshift('-rw_timeout', '15000000');
  }

  const { stdout } = await runProcess(FFPROBE_PATH, args);
  const payload = JSON.parse(stdout);
  const videoStream = payload?.streams?.find((stream) => stream.codec_type === 'video');

  if (!videoStream) {
    throw new Error('No video stream found');
  }

  const dimensions = createDisplayDimensions(videoStream);
  const duration = parseNumeric(payload?.format?.duration || videoStream?.duration);
  const aspectRatio = dimensions.displayWidth > 0 && dimensions.displayHeight > 0
    ? dimensions.displayWidth / dimensions.displayHeight
    : 0;

  return {
    source,
    duration,
    codec: videoStream.codec_name || 'unknown',
    rawWidth: dimensions.rawWidth,
    rawHeight: dimensions.rawHeight,
    displayWidth: dimensions.displayWidth,
    displayHeight: dimensions.displayHeight,
    aspectRatio,
    rotation: dimensions.rotation,
    sar: dimensions.sar
  };
}

function buildSampleTimestamps(duration, sampleCount) {
  if (!duration || duration <= 0) {
    return [0];
  }

  if (duration <= 6) {
    return [Math.max(0, duration / 2)];
  }

  const fractions = sampleCount === 1
    ? [0.5]
    : Array.from({ length: sampleCount }, (_, index) => 0.15 + (0.7 * index) / (sampleCount - 1));

  return fractions.map((fraction) => Math.max(0, Math.min(duration - 0.5, duration * fraction)));
}

function parseCropdetectBoxes(stderr) {
  const regex = /crop=(\d+):(\d+):(\d+):(\d+)/g;
  const boxes = [];
  let match;

  while ((match = regex.exec(stderr)) !== null) {
    boxes.push({
      width: parseInt(match[1], 10),
      height: parseInt(match[2], 10),
      x: parseInt(match[3], 10),
      y: parseInt(match[4], 10)
    });
  }

  return boxes;
}

function selectRepresentativeBox(boxes) {
  if (!boxes.length) {
    return null;
  }

  const counts = new Map();
  for (const box of boxes) {
    const key = `${box.width}x${box.height}:${box.x}:${box.y}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  }

  const [bestKey] = Array.from(counts.entries()).sort((a, b) => b[1] - a[1])[0];
  const [size, x, y] = bestKey.split(':');
  const [width, height] = size.split('x');
  return {
    width: parseInt(width, 10),
    height: parseInt(height, 10),
    x: parseInt(x, 10),
    y: parseInt(y, 10),
    samplesMatched: counts.get(bestKey)
  };
}

async function detectContentBox(source, duration, sampleCount) {
  const timestamps = buildSampleTimestamps(duration, sampleCount);
  const collected = [];

  for (const timestamp of timestamps) {
    const args = [
      '-v', 'info',
      '-ss', `${timestamp}`,
      '-i', source,
      '-t', '1.5',
      '-vf', 'cropdetect=limit=0.08:round=2:reset=0',
      '-an',
      '-f', 'null',
      '-'
    ];

    if (isHttpUrl(source)) {
      args.unshift('-rw_timeout', '15000000');
    }

    try {
      const { stderr } = await runProcess(FFMPEG_PATH, args);
      collected.push(...parseCropdetectBoxes(stderr));
    } catch {
      // Ignore cropdetect failures for individual samples.
    }
  }

  return selectRepresentativeBox(collected);
}

function shouldRunContentDetect(video, probe, options) {
  if (options.contentDetect === 'always') {
    return true;
  }
  if (options.contentDetect === 'never') {
    return false;
  }

  const storedAspect = parseNumeric(video.aspectRatio);
  const storedResolutionAspect = video.originalResolution?.width && video.originalResolution?.height
    ? video.originalResolution.width / video.originalResolution.height
    : 0;

  return (
    !storedAspect ||
    Math.abs(storedAspect - probe.aspectRatio) > 0.15 ||
    (storedResolutionAspect > 0 && Math.abs(storedResolutionAspect - probe.aspectRatio) > 0.15) ||
    (video.videoType === 'vayu' && probe.aspectRatio < 1.0) ||
    (video.videoType === 'yog' && probe.aspectRatio > 1.0)
  );
}

function chooseFinalClassification(video, probe, contentBox) {
  let basis = 'display';
  let finalWidth = probe?.displayWidth || 0;
  let finalHeight = probe?.displayHeight || 0;
  let finalAspectRatio = probe?.aspectRatio || 0;
  let confidence = probe ? 'high' : 'low';
  const notes = [];

  if (probe?.rotation) {
    notes.push(`rotation=${probe.rotation}`);
  }

  if (probe && contentBox && probe.displayWidth > 0 && probe.displayHeight > 0 && contentBox.width > 0 && contentBox.height > 0) {
    const cropAspectRatio = contentBox.width / contentBox.height;
    const widthBorderRatio = Math.abs(probe.displayWidth - contentBox.width) / probe.displayWidth;
    const heightBorderRatio = Math.abs(probe.displayHeight - contentBox.height) / probe.displayHeight;
    const significantBorders = widthBorderRatio > 0.08 || heightBorderRatio > 0.08;
    const orientationFlip = (probe.aspectRatio > 1.0 && cropAspectRatio < 1.0) || (probe.aspectRatio < 1.0 && cropAspectRatio > 1.0);

    if (significantBorders && (orientationFlip || Math.abs(cropAspectRatio - probe.aspectRatio) > 0.2)) {
      basis = 'content-box';
      finalWidth = contentBox.width;
      finalHeight = contentBox.height;
      finalAspectRatio = cropAspectRatio;
      confidence = contentBox.samplesMatched >= 2 ? 'high' : 'medium';
      notes.push(`crop=${contentBox.width}x${contentBox.height}`);
    }
  }

  if (!finalAspectRatio || finalAspectRatio <= 0) {
    const fallbackAspect = parseNumeric(video.aspectRatio);
    const fallbackWidth = parseNumeric(video.originalResolution?.width);
    const fallbackHeight = parseNumeric(video.originalResolution?.height);

    finalAspectRatio = fallbackAspect || (fallbackWidth > 0 && fallbackHeight > 0 ? fallbackWidth / fallbackHeight : 9 / 16);
    finalWidth = fallbackWidth;
    finalHeight = fallbackHeight;
    basis = 'stored-metadata';
    confidence = 'low';
  }

  return {
    basis,
    finalWidth,
    finalHeight,
    finalAspectRatio,
    finalVideoType: finalAspectRatio > 1.0 ? 'vayu' : 'yog',
    confidence,
    notes
  };
}

function hasMeaningfulChange(video, result, syncResolution) {
  const typeChanged = video.videoType !== result.finalVideoType;
  const aspectChanged = Math.abs(parseNumeric(video.aspectRatio) - result.finalAspectRatio) > DEFAULT_ASPECT_TOLERANCE;
  const resolutionChanged = syncResolution && (
    parseNumeric(video.originalResolution?.width) !== result.finalWidth ||
    parseNumeric(video.originalResolution?.height) !== result.finalHeight
  );

  return typeChanged || aspectChanged || resolutionChanged;
}

async function inspectVideo(video, options) {
  const candidateSources = getCandidateSources(video);
  const errors = [];
  let probe = null;

  for (const source of candidateSources) {
    try {
      probe = await probeSource(source);
      break;
    } catch (error) {
      errors.push(`${source}: ${error.message}`);
    }
  }

  let contentBox = null;
  if (probe && shouldRunContentDetect(video, probe, options)) {
    try {
      contentBox = await detectContentBox(probe.source, probe.duration, options.sampleCount);
    } catch (error) {
      errors.push(`cropdetect: ${error.message}`);
    }
  }

  const classification = chooseFinalClassification(video, probe, contentBox);
  const changeDetected = hasMeaningfulChange(video, classification, options.syncResolution);
  const eligibleToApply = CONFIDENCE_ORDER[classification.confidence] >= CONFIDENCE_ORDER[options.minimumConfidence];

  return {
    id: String(video._id),
    name: video.videoName,
    previousVideoType: video.videoType,
    previousAspectRatio: parseNumeric(video.aspectRatio),
    previousResolution: video.originalResolution || null,
    source: probe?.source || null,
    sourceProbe: probe,
    contentBox,
    result: classification,
    changeDetected,
    eligibleToApply,
    errors
  };
}

async function writeReport(reportPath, payload) {
  const absolutePath = path.isAbsolute(reportPath)
    ? reportPath
    : path.join(process.cwd(), reportPath);

  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  fs.writeFileSync(absolutePath, JSON.stringify(payload, null, 2));
  return absolutePath;
}

async function processWithConcurrency(items, concurrency, worker) {
  const results = [];
  let index = 0;

  async function runNext() {
    const currentIndex = index++;
    if (currentIndex >= items.length) {
      return;
    }

    results[currentIndex] = await worker(items[currentIndex], currentIndex);
    await runNext();
  }

  const workers = Array.from({ length: Math.min(concurrency, items.length) }, () => runNext());
  await Promise.all(workers);
  return results;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printHelp();
    return;
  }

  if (!FFPROBE_PATH) {
    throw new Error('ffprobe binary could not be resolved. Set FFPROBE_PATH or install ffprobe-static.');
  }

  if (!FFMPEG_PATH && options.contentDetect !== 'never') {
    throw new Error('ffmpeg binary could not be resolved. Set FFMPEG_PATH or install ffmpeg-static.');
  }

  const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!mongoUri) {
    throw new Error('MONGO_URI or MONGODB_URI is required');
  }

  console.log(`Mode: ${options.apply ? 'APPLY' : 'DRY RUN'}`);
  console.log(`Content detection: ${options.contentDetect}`);
  console.log(`Minimum confidence to apply: ${options.minimumConfidence}`);

  await mongoose.connect(mongoUri);

  try {
    const query = {
      mediaType: { $ne: 'image' },
      processingStatus: { $in: options.includeStatuses }
    };

    if (options.videoType) {
      query.videoType = options.videoType;
    }
    if (options.ids.length) {
      query._id = { $in: options.ids };
    }

    let cursor = Video.find(query)
      .select('_id videoName videoType aspectRatio originalResolution videoUrl hlsMasterPlaylistUrl hlsPlaylistUrl processingStatus')
      .sort({ createdAt: -1 });

    if (options.limit) {
      cursor = cursor.limit(options.limit);
    }

    const videos = await cursor.lean();
    console.log(`Videos selected: ${videos.length}`);

    const results = await processWithConcurrency(videos, options.concurrency, async (video, index) => {
      const inspected = await inspectVideo(video, options);
      const progress = `${index + 1}/${videos.length}`;
      const tag = inspected.changeDetected ? 'change' : 'same';
      console.log(`[${progress}] ${tag} | ${inspected.result.finalVideoType} | ${inspected.result.confidence} | ${inspected.name}`);

      if (options.apply && inspected.changeDetected && inspected.eligibleToApply) {
        const update = {
          videoType: inspected.result.finalVideoType,
          aspectRatio: inspected.result.finalAspectRatio
        };

        if (options.syncResolution && inspected.result.finalWidth > 0 && inspected.result.finalHeight > 0) {
          update.originalResolution = {
            width: inspected.result.finalWidth,
            height: inspected.result.finalHeight
          };
        }

        await Video.updateOne({ _id: inspected.id }, { $set: update });
      }

      return inspected;
    });

    const summary = results.reduce((acc, item) => {
      acc.total += 1;
      if (item.changeDetected) acc.changed += 1;
      if (item.eligibleToApply) acc.eligible += 1;
      if (item.changeDetected && item.eligibleToApply) acc.safeToApply += 1;
      if (item.result.basis === 'content-box') acc.contentBoxDecisions += 1;
      if (item.errors.length) acc.withErrors += 1;
      acc.confidence[item.result.confidence] += 1;
      return acc;
    }, {
      total: 0,
      changed: 0,
      eligible: 0,
      safeToApply: 0,
      contentBoxDecisions: 0,
      withErrors: 0,
      confidence: { low: 0, medium: 0, high: 0 }
    });

    console.log('\nSummary');
    console.log(`  Total inspected: ${summary.total}`);
    console.log(`  Changes detected: ${summary.changed}`);
    console.log(`  Eligible by confidence: ${summary.eligible}`);
    console.log(`  Safe-to-apply changes: ${summary.safeToApply}`);
    console.log(`  Content-box decisions: ${summary.contentBoxDecisions}`);
    console.log(`  Items with probe warnings: ${summary.withErrors}`);
    console.log(`  Confidence counts: high=${summary.confidence.high}, medium=${summary.confidence.medium}, low=${summary.confidence.low}`);

    const changedSample = results.filter((item) => item.changeDetected).slice(0, 10);
    if (changedSample.length) {
      console.log('\nTop changes');
      for (const item of changedSample) {
        console.log(`  ${item.name}`);
        console.log(`    ${item.previousVideoType} (${item.previousAspectRatio.toFixed(4)}) -> ${item.result.finalVideoType} (${item.result.finalAspectRatio.toFixed(4)}) [${item.result.basis}, ${item.result.confidence}]`);
      }
    }

    if (options.reportPath) {
      const savedReportPath = await writeReport(options.reportPath, {
        generatedAt: new Date().toISOString(),
        options,
        summary,
        results
      });
      console.log(`\nReport saved to ${savedReportPath}`);
    }
  } finally {
    await mongoose.disconnect();
  }
}

main().catch((error) => {
  console.error('\nClassification script failed:', error.message);
  process.exit(1);
});
