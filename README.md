# 🎥 Vayug

**Vayug** is an open-source platform that empowers content creators by allowing them to upload short and long-form videos, build audiences, and earn 80% of ad revenue.
Inspired by platforms like YouTube Shorts and Instagram Reels, Vayug focuses on creator-first monetization and a seamless video-sharing experience.

---

## ✨ Features

- 📱 Mobile-first UI (built with Flutter)
- 🔐 Google Sign-In authentication
- 🎬 Upload videos from gallery
- 📤 Videos stored securely on Cloudinary (via Node.js backend)
- 🧭 Bottom navigation with Home, Upload, Profile
- 📈 Like, comment, and share functionality
- 💰 80% ad revenue share to creators
- 🗂️ Video types: Shorts + Long-form
- 🧑 User profiles with stats & uploads

---

## 📦 Tech Stack

| Frontend        | Backend           | Database       | Hosting           |
|----------------|-------------------|----------------|--------------------|
| Flutter         | Node.js + Express | MongoDB        | Railway + Cloudinary |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK ≥ 3.4.3
- Node.js ≥ 18.x
- MongoDB (local or Atlas)

### Clone the repo

```bash
git clone https://github.com/Vayug12/snehayog.git
cd snehayog
```

### Verify Setup (Windows)
```bash
cd frontend\scripts
verify_setup.bat
```

### Verify Setup (Linux/Mac)
```bash
cd frontend/scripts
./verify_setup.sh
```

### Setup Backend
```bash
cd backend
npm install
cp .env.example .env  # Configure your environment variables
npm start
```

### Setup Frontend
```bash
cd frontend
flutter pub get
flutter run
```

📖 **For detailed setup instructions**, see [SETUP_GUIDE.md](../SETUP_GUIDE.md)

---

## 📁 Project Structure

```
snehayog/
├── backend/                # Node.js + Express API
├── frontend/               # Flutter mobile app
├── packages/               # Local packages
│   └── snehayog_monetization/  # Payment & monetization package
├── LICENSE
└── README.md
```

⚠️ **Important**: The `packages/snehayog_monetization` folder is required for the Flutter app to build!
