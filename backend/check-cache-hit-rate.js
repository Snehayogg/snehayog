import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Cache Hit Rate Calculator
 * 
 * Usage:
 *   node check-cache-hit-rate.js                    # Check common log locations
 *   node check-cache-hit-rate.js <log-file-path>    # Check specific log file
 *   cat logs/app.log | node check-cache-hit-rate.js # Read from stdin
 */

// Common log file locations to check
const commonLogPaths = [
  path.join(__dirname, 'logs', 'backend.log'),
  path.join(__dirname, 'logs', 'app.log'),
  path.join(__dirname, 'logs', 'server.log'),
  path.join(__dirname, 'backend.log'),
  path.join(__dirname, 'app.log'),
  path.join(process.cwd(), 'logs', 'backend.log'),
  path.join(process.cwd(), 'logs', 'app.log'),
];

/**
 * Read log content from file or stdin
 */
async function readLogContent(logPath) {
  try {
    if (logPath) {
      // Read from file
      if (!fs.existsSync(logPath)) {
        throw new Error(`Log file not found: ${logPath}`);
      }
      return fs.readFileSync(logPath, 'utf8');
    } else {
      // Try to read from stdin (if piped)
      if (process.stdin.isTTY) {
        // Not piped, try common log locations
        for (const logPath of commonLogPaths) {
          if (fs.existsSync(logPath)) {
            console.log(`📂 Found log file: ${logPath}\n`);
            return fs.readFileSync(logPath, 'utf8');
          }
        }
        throw new Error('No log file found. Provide a log file path or pipe log content.');
      } else {
        // Read from stdin
        let content = '';
        for await (const chunk of process.stdin) {
          content += chunk.toString();
        }
        return content;
      }
    }
  } catch (error) {
    throw error;
  }
}

/**
 * Calculate cache statistics from log content
 */
function calculateCacheStats(logContent) {
  // Count cache hits (including Ad Cache HIT)
  const hits = (logContent.match(/Cache HIT|Ad Cache HIT/g) || []).length;
  
  // Count cache misses (including Ad Cache MISS)
  const misses = (logContent.match(/Cache MISS|Ad Cache MISS/g) || []).length;
  
  // Count video cache hits specifically
  const videoHits = (logContent.match(/✅ Cache HIT:/g) || []).length;
  
  // Count video cache misses specifically
  const videoMisses = (logContent.match(/❌ Cache MISS:/g) || []).length;
  
  // Count ad cache hits specifically
  const adHits = (logContent.match(/✅ Ad Cache HIT:/g) || []).length;
  
  // Count ad cache misses specifically
  const adMisses = (logContent.match(/❌ Ad Cache MISS:/g) || []).length;
  
  const total = hits + misses;
  
  return {
    hits,
    misses,
    total,
    videoHits,
    videoMisses,
    adHits,
    adMisses,
    videoTotal: videoHits + videoMisses,
    adTotal: adHits + adMisses
  };
}

/**
 * Format percentage with status indicator
 */
function formatHitRate(hitRate) {
  if (hitRate >= 80) {
    return `${hitRate}% ✅ Excellent`;
  } else if (hitRate >= 50) {
    return `${hitRate}% ⚠️ Good`;
  } else {
    return `${hitRate}% ❌ Needs Improvement`;
  }
}

/**
 * Main function
 */
async function main() {
  try {
    const logPath = process.argv[2]; // Get log file path from command line argument
    
    console.log('🔍 Reading log content...\n');
    
    const logContent = await readLogContent(logPath);
    
    if (!logContent || logContent.trim().length === 0) {
      console.log('❌ Log file is empty');
      process.exit(1);
    }
    
    const stats = calculateCacheStats(logContent);
    
    if (stats.total === 0) {
      console.log('❌ No cache requests found in logs');
      console.log('💡 Make sure your app is running and generating cache logs');
      console.log('💡 Look for "Cache HIT" or "Cache MISS" messages in your logs');
      process.exit(0);
    }
    
    // Calculate overall hit rate
    const overallHitRate = ((stats.hits / stats.total) * 100).toFixed(2);
    
    // Calculate video cache hit rate
    const videoHitRate = stats.videoTotal > 0 
      ? ((stats.videoHits / stats.videoTotal) * 100).toFixed(2)
      : 'N/A';
    
    // Calculate ad cache hit rate
    const adHitRate = stats.adTotal > 0
      ? ((stats.adHits / stats.adTotal) * 100).toFixed(2)
      : 'N/A';
    
    // Display results
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 Cache Performance Statistics');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    console.log('📈 Overall Cache Performance:');
    console.log(`   Hit Rate: ${formatHitRate(overallHitRate)}`);
    console.log(`   Hits: ${stats.hits}`);
    console.log(`   Misses: ${stats.misses}`);
    console.log(`   Total Requests: ${stats.total}\n`);
    
    if (stats.videoTotal > 0) {
      console.log('🎥 Video Cache Performance:');
      console.log(`   Hit Rate: ${formatHitRate(videoHitRate)}`);
      console.log(`   Hits: ${stats.videoHits}`);
      console.log(`   Misses: ${stats.videoMisses}`);
      console.log(`   Total Requests: ${stats.videoTotal}\n`);
    }
    
    if (stats.adTotal > 0) {
      console.log('📢 Ad Cache Performance:');
      console.log(`   Hit Rate: ${formatHitRate(adHitRate)}`);
      console.log(`   Hits: ${stats.adHits}`);
      console.log(`   Misses: ${stats.adMisses}`);
      console.log(`   Total Requests: ${stats.adTotal}\n`);
    }
    
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Performance recommendations
    if (overallHitRate < 50) {
      console.log('💡 Recommendations:');
      console.log('   • Increase cache TTL (Time To Live)');
      console.log('   • Check if cache invalidation is too frequent');
      console.log('   • Verify Redis connection is stable');
      console.log('   • Monitor cache key patterns\n');
    } else if (overallHitRate >= 80) {
      console.log('✅ Excellent cache performance! Your Redis caching is working optimally.\n');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error('\n💡 Usage:');
    console.error('   node check-cache-hit-rate.js                    # Auto-detect log file');
    console.error('   node check-cache-hit-rate.js <log-file-path>    # Specify log file');
    console.error('   cat logs/app.log | node check-cache-hit-rate.js # Read from stdin');
    console.error('\n💡 Common log locations checked:');
    commonLogPaths.forEach(p => console.error(`   • ${p}`));
    process.exit(1);
  }
}

// Run the script
main();

