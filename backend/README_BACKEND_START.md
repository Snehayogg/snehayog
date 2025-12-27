# How to Start Backend Server on localhost:5001

## Quick Start

### 1. Navigate to Backend Directory
```bash
cd snehayog/backend
```

### 2. Check if Backend is Already Running
```bash
# PowerShell (Windows)
.\check-backend.ps1

# OR manually check in browser:
# Open: http://localhost:5001/api/health
# Should see: {"status":"healthy","service":"vayug-backend",...}
```

### 3. Start the Backend Server

**Option A: Production Mode (no auto-reload)**
```bash
npm start
```

**Option B: Development Mode (with auto-reload using nodemon)**
```bash
npm run dev
```

### 4. Verify Backend is Running

After starting, you should see output like:
```
Server running on port 5001
Database connected successfully
```

### 5. Test the Health Endpoint

Open in browser or use curl:
- Browser: http://localhost:5001/api/health
- PowerShell: `Invoke-WebRequest -Uri "http://localhost:5001/api/health"`
- curl: `curl http://localhost:5001/api/health`

You should get a JSON response:
```json
{
  "status": "healthy",
  "service": "vayug-backend",
  "timestamp": "...",
  "uptime": 123.45,
  "environment": "development"
}
```

## Common Issues

### Issue 1: Port 5001 Already in Use
**Error:** `Error: listen EADDRINUSE: address already in use :::5001`

**Solution:**
```bash
# Windows PowerShell - Find and kill process using port 5001
netstat -ano | findstr :5001
# Note the PID from the output, then:
taskkill /PID <PID> /F

# OR use a different port:
# Set environment variable: $env:PORT=5002
# Then: npm start
```

### Issue 2: MongoDB Not Connected
**Error:** `MongoServerError: connect ECONNREFUSED`

**Solution:**
- Make sure MongoDB is running locally, OR
- Check your `.env` file has correct `MONGO_URI` or `MONGODB_URI`
- For local MongoDB: `mongodb://localhost:27017/snehayog`

### Issue 3: Missing Dependencies
**Error:** `Cannot find module 'xxx'`

**Solution:**
```bash
npm install
```

## Environment Variables

The server uses these default values:
- **PORT**: `5001` (if not set in `.env`)
- **HOST**: `0.0.0.0` (allows connections from any IP)

To use a different port, create/update `.env` file:
```
PORT=5001
MONGO_URI=mongodb://localhost:27017/snehayog
```

## Check What Port the Server is Using

After starting, look for this line in the console output:
```
✅ Server running on http://0.0.0.0:5001
```

If you see a different port, that means `PORT` environment variable is set differently.

