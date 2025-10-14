#!/bin/bash

echo "🚀 Starting Snehayog Local Development Server"
echo "============================================"

echo ""
echo "📍 Setting up local development environment..."
echo "🌐 Host: 192.168.0.199"
echo "🔌 Port: 5001"
echo ""

cd backend

echo "📦 Installing dependencies (if needed)..."
npm install

echo ""
echo "🔧 Starting local server with HOST=192.168.0.199 PORT=5001..."
echo ""
echo "✅ Server will be available at:"
echo "   http://192.168.0.199:5001"
echo "   http://localhost:5001"
echo ""
echo "📱 Your Flutter app will automatically:"
echo "   1. Try to connect to local server first"
echo "   2. Fall back to production if local server is not running"
echo ""
echo "🛑 Press Ctrl+C to stop the server"
echo ""

npm run dev:local
