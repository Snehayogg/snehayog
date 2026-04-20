#!/bin/sh

# Start the video worker in the background
echo "🎬 Starting Video Worker..."
node workers/videoWorker.js &

# Start the main server in the foreground
echo "🚀 Starting API Server..."
node server.js
