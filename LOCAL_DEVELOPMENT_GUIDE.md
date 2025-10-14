# 🚀 Local Development Guide with Automatic Fallback

## Overview

Your Snehayog app now has an intelligent network fallback system that automatically switches between your local development server and the production server based on availability.

## How It Works

### 🔄 Automatic Fallback System

1. **Primary**: App tries to connect to your local server (`http://192.168.0.199:5001`)
2. **Fallback**: If local server is not running, automatically switches to production (`https://snehayog-production.up.railway.app`)
3. **Smart Detection**: Tests server connectivity before making API calls
4. **Real-time Switching**: Can switch between servers during runtime

### 📱 Visual Indicators

- **Green "LOCAL" badge**: Connected to your local development server
- **Orange "PROD" badge**: Connected to production server
- **Debug Widget**: Tap the network status badge to see detailed information and manually switch servers

## 🛠️ Setup Instructions

### 1. Start Local Backend Server

#### Option A: Using the Script (Recommended)
```bash
# Windows
start-local-server.bat

# Linux/Mac
./start-local-server.sh
```

#### Option B: Manual Command
```bash
cd backend
npm run dev:local
```

### 2. Start Flutter App
```bash
cd frontend
flutter run
```

### 3. Monitor Network Status

Look for the network status widget in the top-right corner:
- **Green "LOCAL"**: Connected to local server
- **Orange "PROD"**: Connected to production server

## 🔧 Configuration Files Updated

### Frontend Configuration
- `lib/config/app_config.dart` - Now uses NetworkService for automatic fallback
- `lib/services/network_service.dart` - New service handling fallback logic
- `lib/services/app_initialization_service.dart` - Initializes network service
- `lib/widgets/network_status_widget.dart` - Debug widget for network status

### Backend Configuration
- `constants/index.js` - Updated local network IP
- `config.js` - Updated CORS settings for local development
- `config/config.js` - Updated CORS origins
- `package.json` - Added `dev:local` and `start:local` scripts
- `server.js` - Updated to use HOST environment variable

## 🎯 Benefits

### ✅ For Development
- **No Code Push Required**: Test locally without pushing to Railway
- **Instant Feedback**: See changes immediately on local server
- **Production Fallback**: Always have a working server available
- **Easy Switching**: Toggle between local and production with one tap

### ✅ For Testing
- **Offline Development**: Work without internet connection (local server)
- **Production Testing**: Test against real production data when needed
- **Network Resilience**: App continues working even if one server fails

## 🔍 Debug Features

### Network Status Widget
- Shows current server being used
- Displays connection status for both servers
- Allows manual server switching
- Shows server health status

### Console Logging
```
🌐 NetworkService: Initializing with fallback support...
🔍 NetworkService: Testing connection to http://192.168.0.199:5001
✅ NetworkService: Connected to http://192.168.0.199:5001
📍 NetworkService: Current base URL: http://192.168.0.199:5001
```

## 🚨 Troubleshooting

### Local Server Not Starting
1. Check if port 5001 is available: `netstat -an | findstr 5001`
2. Ensure MongoDB is running (if using local database)
3. Check environment variables in backend

### App Not Connecting to Local Server
1. Verify your laptop IP is `192.168.0.199`
2. Check firewall settings
3. Ensure both devices are on the same network
4. Use the network status widget to manually switch servers

### Production Fallback Not Working
1. Check internet connection
2. Verify Railway deployment status
3. Check CORS settings in backend

## 📝 Environment Variables

### Backend (.env file)
```env
HOST=192.168.0.199
PORT=5001
MONGO_URI=your_mongodb_connection_string
```

### Frontend
The app automatically detects the environment and uses appropriate configuration.

## 🔄 Manual Server Switching

### Using the Debug Widget
1. Tap the network status badge in the top-right corner
2. Use "Local" or "Prod" buttons to switch servers
3. Use "Reconnect" to test all servers again

### Programmatically
```dart
// Switch to local server
await NetworkService.instance.tryLocalServer();

// Switch to production server
await NetworkService.instance.switchToProduction();

// Force reconnection test
await NetworkService.instance.reconnect();
```

## 📊 Server Priority

1. **Local Development**: `http://192.168.0.199:5001`
2. **Production Fallback**: `https://snehayog-production.up.railway.app`

The app will always try the local server first, and only fall back to production if the local server is unavailable.

## 🎉 Ready to Develop!

You can now:
- ✅ Develop locally without pushing code
- ✅ Test changes instantly
- ✅ Always have a working server available
- ✅ Switch between servers on demand
- ✅ Monitor network status in real-time

Happy coding! 🚀
