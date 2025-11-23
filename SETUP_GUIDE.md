# 🚀 Snehayog - Setup Guide

Complete setup guide for developers cloning this repository.

## 📋 Prerequisites

- **Flutter SDK**: ≥ 3.4.3
- **Node.js**: ≥ 18.x
- **Git**: Latest version
- **Android Studio** or **Xcode** (for mobile development)

---

## 🔧 Quick Setup (Automated)

### Windows:
```bash
cd snehayog/frontend
flutter pub get
```

### Linux/Mac:
```bash
cd snehayog/frontend
flutter pub get
```

---

## 📁 Project Structure

```
snehayog/
├── backend/                # Node.js backend
├── frontend/               # Flutter app
└── packages/
    └── snehayog_monetization/  # Local Flutter package (REQUIRED)
```

⚠️ **IMPORTANT**: The `snehayog_monetization` package is now inside `packages/` folder in the git repository!

---

## 🛠️ Manual Setup Steps

### 1️⃣ Clone the Repository

```bash
git clone <your-repo-url>
cd snehayog
```

### 2️⃣ Verify Folder Structure

Make sure you have this structure:
```bash
cd snehayog
ls -la
# You should see:
# - backend/
# - frontend/
# - packages/snehayog_monetization/
```

If `packages/snehayog_monetization` is missing, the Flutter app will NOT build!

### 3️⃣ Setup Backend

```bash
cd backend
npm install
cp .env.example .env  # Create your .env file
# Edit .env with your actual values
npm start
```

### 4️⃣ Setup Frontend

```bash
cd frontend
flutter pub get
flutter run
```

---

## ❗ Troubleshooting

### Issue: `flutter pub get` fails with "Could not find package snehayog_monetization"

**Solution:**

1. Check if `snehayog_monetization` folder exists in packages:
   ```bash
   cd snehayog
   ls -la packages/
   # You should see snehayog_monetization/
   ```

2. If missing, make sure you cloned the ENTIRE repository including all folders

3. Verify the path in `pubspec.yaml`:
   ```yaml
   snehayog_monetization:
     path: ../packages/snehayog_monetization  # Relative to frontend/
   ```

4. Run setup again:
   ```bash
   cd snehayog/frontend
   flutter clean
   flutter pub get
   ```

### Issue: Backend connection fails

**Solution:**

1. Make sure backend is running:
   ```bash
   cd snehayog/backend
   npm start
   ```

2. Check `app_config.dart` has correct backend URL:
   ```dart
   static String get baseUrl => 
       kIsWeb ? 'https://snehayog-production.up.railway.app'
       : 'http://172.20.10.2:5001';  // Your local IP
   ```

---

## 🎯 Development Workflow

1. **Start Backend** (Terminal 1):
   ```bash
   cd snehayog/backend
   npm start
   ```

2. **Start Flutter App** (Terminal 2):
   ```bash
   cd snehayog/frontend
   flutter run
   ```

3. **Watch Logs** (Terminal 3):
   ```bash
   cd snehayog/backend
   tail -f logs/server.log  # If you have logging
   ```

---

## 📦 About snehayog_monetization Package

This is a **local Flutter package** that contains:
- Razorpay payment integration
- Monetization services
- Payment handling utilities

It's kept as a separate package for:
- ✅ Better code organization
- ✅ Reusability across projects
- ✅ Cleaner dependency management

---

## 🚀 Production Deployment

### Backend (Railway):
```bash
cd snehayog/backend
railway up
```

### Frontend (APK Build):
```bash
cd snehayog/frontend
flutter build apk --release
# APK location: build/app/outputs/flutter-apk/app-release.apk
```

---

## 📞 Support

If you encounter any issues:
1. Check this guide first
2. Review error logs
3. Open an issue on GitHub

---

**Last Updated**: October 2025

