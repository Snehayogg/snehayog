#!/bin/bash
# Bash script to start server with logging
# Usage: ./start-with-logs.sh

# Create logs directory if it doesn't exist
mkdir -p logs

# Start server with output redirected to log file
echo "🚀 Starting server with logging enabled..."
echo "📝 Logs will be saved to: logs/backend.log"
echo "💡 Press Ctrl+C to stop the server"
echo ""

# Start npm and redirect both stdout and stderr to log file
npm start > logs/backend.log 2>&1

