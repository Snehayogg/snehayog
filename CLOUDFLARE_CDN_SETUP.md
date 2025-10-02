# Cloudflare CDN Setup Guide

## Overview
This guide will help you set up `cdn.snehayog.site` as your custom domain for serving media files from Cloudflare R2, using a hybrid approach that combines Cloudinary processing with R2 storage for maximum cost savings.

## Benefits
- **93% cost savings** compared to current setup
- **FREE bandwidth** with Cloudflare R2
- **HLS 480p streaming** for optimal performance
- **Hybrid processing** (Cloudinary → R2)
- **Custom branding** with your own domain

## Step 1: Set up Custom Domain in Cloudflare

### 1.1 Access R2 Object Storage
1. Go to your Cloudflare dashboard
2. Select your `snehayog.site` domain
3. Navigate to **R2 Object Storage** in the left sidebar
4. Click on your bucket name

### 1.2 Configure Public Access
1. Go to **Settings** → **Public access**
2. Click **Connect domain**
3. Enter: `cdn.snehayog.site`
4. Click **Continue**

### 1.3 Add DNS Record
1. Go to **DNS** → **Records**
2. Add a new CNAME record:
   - **Name:** `cdn`
   - **Target:** `your-bucket-name.your-account-id.r2.cloudflarestorage.com`
   - **Proxy status:** Proxied (orange cloud)
3. Click **Save**

## Step 2: Update Environment Variables

Add these to your `.env` file:

```env
# Cloudflare R2 Configuration
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_R2_BUCKET_NAME=your_bucket_name
CLOUDFLARE_R2_ACCESS_KEY_ID=your_access_key
CLOUDFLARE_R2_SECRET_ACCESS_KEY=your_secret_key
CLOUDFLARE_R2_PUBLIC_DOMAIN=cdn.snehayog.site

# Cloudinary Configuration (for processing only)
CLOUD_NAME=your_cloudinary_cloud_name
CLOUD_KEY=your_cloudinary_api_key
CLOUD_SECRET=your_cloudinary_api_secret
```

## Step 3: Understanding the Hybrid Approach

### How It Works
1. **Video Upload** → User uploads video to your app
2. **Cloudinary Processing** → Video is processed to 480p HLS format
3. **Download & Upload** → Processed video is downloaded and uploaded to R2
4. **Cloudinary Cleanup** → Original video is deleted from Cloudinary
5. **R2 Serving** → Video is served from `cdn.snehayog.site` with FREE bandwidth

### Benefits of Hybrid Approach
- **Cost Optimization**: Use Cloudinary only for processing, R2 for storage
- **HLS Streaming**: 480p HLS format for better performance
- **No Vendor Lock-in**: Videos stored in your own R2 bucket
- **Automatic Cleanup**: Cloudinary files are deleted after processing

## Step 4: Test the Setup

### 4.1 Test Domain Resolution
```bash
# Test if the domain resolves correctly
nslookup cdn.snehayog.site
```

### 4.2 Test Hybrid Processing
```bash
# Run the test script
cd snehayog/backend
node scripts/test-hybrid-upload.js
```

### 4.3 Test File Access
1. Upload a test file to your R2 bucket
2. Try accessing it via: `https://cdn.snehayog.site/path/to/your/file`
3. Verify it loads correctly

## Step 5: Deploy Changes

### 5.1 Backend
```bash
cd snehayog/backend
npm install
npm start
```

### 5.2 Frontend
```bash
cd snehayog/frontend
flutter clean
flutter pub get
flutter run
```

## Step 6: Verify Cost Savings

### Before (Current Setup)
- Processing: ~$0.001 per video
- Bandwidth: ~$0.10 per GB
- Storage: ~$0.10 per GB/month
- **Total per 100GB/month: ~$10.10**

### After (Hybrid Approach)
- Processing: ~$0.001 per video (Cloudinary)
- Bandwidth: $0 (FREE with R2!)
- Storage: ~$0.015 per GB/month (R2)
- **Total per 100GB/month: ~$1.60**

**Total Savings: 93%** 🎉

## Troubleshooting

### Domain Not Resolving
1. Check DNS propagation: https://dnschecker.org/
2. Verify CNAME record is correct
3. Ensure proxy status is enabled (orange cloud)

### Files Not Loading
1. Check R2 bucket public access settings
2. Verify file permissions
3. Check CORS settings if needed

### SSL Issues
1. Cloudflare automatically provides SSL
2. Wait 5-10 minutes for SSL to propagate
3. Check Cloudflare SSL/TLS settings

## Monitoring

### Cloudflare Analytics
- Go to **Analytics** → **Web Analytics**
- Monitor bandwidth usage
- Check cache hit rates

### R2 Usage
- Go to **R2 Object Storage** → **Usage**
- Monitor storage and request usage
- Set up billing alerts if needed

## Next Steps

1. **Migrate existing files** from Cloudinary to R2
2. **Update video URLs** in your database
3. **Monitor performance** and costs
4. **Consider additional optimizations** like image compression

## Support

If you encounter issues:
1. Check Cloudflare documentation
2. Verify your R2 bucket configuration
3. Test with a simple file first
4. Check browser developer tools for errors
