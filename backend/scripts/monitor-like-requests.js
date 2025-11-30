#!/usr/bin/env node

/**
 * LIKE REQUEST MONITOR SCRIPT
 * 
 * This script monitors backend logs for like requests in real-time.
 * It helps you see if like requests are reaching the backend.
 * 
 * Usage:
 *   node scripts/monitor-like-requests.js
 * 
 * Or monitor your backend console directly for:
 *   "🔍 Like API: Received request"
 *   "✅ Like API: Successfully toggled like"
 */

import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  magenta: '\x1b[35m',
};

function log(message, color = 'reset') {
  const timestamp = new Date().toISOString();
  console.log(`${colors[color]}[${timestamp}] ${message}${colors.reset}`);
}

function logSection(title) {
  console.log('\n' + '='.repeat(60));
  log(title, 'cyan');
  console.log('='.repeat(60));
}

logSection('🔍 LIKE REQUEST MONITOR');
log('Monitoring backend for like requests...', 'blue');
log('Press Ctrl+C to stop\n', 'yellow');

// Check if we're on Windows or Unix
const isWindows = process.platform === 'win32';

// Try to monitor logs
const logFile = join(__dirname, '../logs/app.log');

if (fs.existsSync(logFile)) {
  log(`📄 Monitoring log file: ${logFile}`, 'blue');
  
  // Use tail command (Unix) or PowerShell (Windows)
  let tailProcess;
  
  if (isWindows) {
    // Windows PowerShell Get-Content with -Wait
    tailProcess = spawn('powershell', [
      '-Command',
      `Get-Content "${logFile}" -Wait -Tail 50`
    ]);
  } else {
    // Unix tail -f
    tailProcess = spawn('tail', ['-f', logFile]);
  }
  
  tailProcess.stdout.on('data', (data) => {
    const lines = data.toString().split('\n');
    lines.forEach(line => {
      if (line.trim()) {
        // Highlight like-related logs
        if (line.includes('Like API') || line.includes('like')) {
          if (line.includes('Received request')) {
            log(`📥 ${line}`, 'green');
          } else if (line.includes('Successfully') || line.includes('✅')) {
            log(`✅ ${line}`, 'green');
          } else if (line.includes('Error') || line.includes('❌')) {
            log(`❌ ${line}`, 'red');
          } else {
            log(`🔍 ${line}`, 'cyan');
          }
        } else {
          // Show other logs in dimmed color
          console.log(line);
        }
      }
    });
  });
  
  tailProcess.stderr.on('data', (data) => {
    log(`Error: ${data}`, 'red');
  });
  
  tailProcess.on('close', (code) => {
    log(`\nMonitor stopped (exit code: ${code})`, 'yellow');
    process.exit(code);
  });
  
} else {
  log(`⚠️  Log file not found: ${logFile}`, 'yellow');
  log('💡 Alternative: Monitor your backend console directly', 'yellow');
  log('💡 Look for these log messages:', 'yellow');
  log('   - "🔍 Like API: Received request"', 'cyan');
  log('   - "✅ Like API: Successfully toggled like"', 'green');
  log('   - "❌ Like API Error:"', 'red');
  log('\n💡 Or check your backend terminal/console output', 'yellow');
  
  // Provide instructions
  logSection('📋 MANUAL MONITORING INSTRUCTIONS');
  log('1. Open your backend terminal/console', 'yellow');
  log('2. Look for log messages starting with "🔍 Like API:"', 'yellow');
  log('3. When you click like in the app, you should see:', 'yellow');
  log('   - "🔍 Like API: Received request { googleId, videoId }"', 'cyan');
  log('   - "✅ Like API: Video updated successfully..."', 'green');
  log('4. If you don\'t see these messages, the request is not reaching the backend', 'red');
}

// Handle Ctrl+C
process.on('SIGINT', () => {
  log('\n\n🛑 Stopping monitor...', 'yellow');
  process.exit(0);
});

