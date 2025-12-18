/**
 * Seed AppConfig Script
 * 
 * This script creates an initial AppConfig document in MongoDB.
 * Run this after setting up the database to initialize the backend-driven config.
 * 
 * Usage:
 *   node scripts/seed-app-config.js
 * 
 * Environment Variables:
 *   MONGO_URI - MongoDB connection string
 *   NODE_ENV - Environment (development, staging, production)
 */

import dotenv from 'dotenv';
import mongoose from 'mongoose';
import AppConfig from '../models/AppConfig.js';

dotenv.config();

const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;

if (!mongoUri) {
  console.error('❌ Error: MONGO_URI or MONGODB_URI environment variable is required');
  process.exit(1);
}

async function seedAppConfig() {
  try {
    console.log('🔍 Connecting to MongoDB...');
    await mongoose.connect(mongoUri);
    console.log('✅ Connected to MongoDB');

    const environment = process.env.NODE_ENV || 'production';
    const platform = 'android'; // Can be 'android', 'ios', 'web', or 'all'

    // Check if config already exists
    const existing = await AppConfig.findOne({
      platform: platform,
      environment: environment,
      isActive: true,
    });

    if (existing) {
      console.log(`⚠️  AppConfig already exists for ${platform}/${environment}`);
      console.log('   Use MongoDB to update it, or delete it first to re-seed');
      await mongoose.disconnect();
      return;
    }

    // Create default config
    const config = new AppConfig({
      platform: platform,
      environment: environment,
      versionControl: {
        minSupportedAppVersion: '1.0.0',
        latestAppVersion: '1.4.0',
        forceUpdateMessage: 'A new version of the app is available. Please update to continue.',
        softUpdateMessage: 'A new version is available with exciting features!',
        updateUrl: {
          android: 'https://play.google.com/store/apps/details?id=com.snehayog.app',
          ios: 'https://apps.apple.com/app/snehayog',
        },
      },
      featureFlags: {
        yugTabCarouselAds: true,
        imageUploadForCreators: true,
        adCreationV2: true,
        videoFeedAds: true,
        creatorPayouts: true,
        referralSystem: true,
        pushNotifications: true,
        analytics: true,
      },
      businessRules: {
        adBudget: {
          minDailyBudget: 100,
          maxDailyBudget: 10000,
          minTotalBudget: 1000,
        },
        cpmRates: {
          banner: 10.0,
          carousel: 30.0,
          videoFeedAd: 30.0,
        },
        revenueShare: {
          creatorShare: 0.80,
          platformShare: 0.20,
        },
        uploadLimits: {
          maxVideoSize: 100 * 1024 * 1024, // 100MB
          maxImageSize: 5 * 1024 * 1024, // 5MB
          maxVideoDuration: 600, // 10 minutes
          allowedVideoFormats: ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
          allowedImageFormats: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', 'bmp'],
        },
        payoutRules: {
          minPayoutAmount: 500,
          payoutProcessingDays: 7,
        },
        adServing: {
          insertionFrequency: 2,
          maxAdsPerSession: 10,
          impressionFrequencyCap: 3,
        },
      },
      recommendationParams: {
        weights: {
          views: 0.3,
          likes: 0.25,
          recency: 0.2,
          userEngagement: 0.15,
          categoryMatch: 0.1,
        },
        timeDecayFactor: 0.95,
        trendingThreshold: 1000,
      },
      uiTexts: new Map([
        ['app_name', 'Vayu'],
        ['app_tagline', 'Create • Video • Earn'],
        ['nav_yug', 'Yug'],
        ['nav_vayu', 'Vayu'],
        ['nav_profile', 'Profile'],
        ['nav_ads', 'Ads'],
        ['btn_upload', 'Upload'],
        ['btn_create_ad', 'Create Advertisement'],
        ['btn_save', 'Save'],
        ['btn_cancel', 'Cancel'],
        ['btn_submit', 'Submit'],
        ['btn_visit_now', 'Visit Now'],
        ['btn_update_app', 'Update App'],
        ['upload_title', 'Upload & Create'],
        ['upload_select_media', 'Select Media'],
        ['upload_media_hint', 'Upload Video or Product Image'],
        ['upload_product_image_hint', 'Product image selected. Please add your product/website URL in the External Link field.'],
        ['ad_create_title', 'Create Advertisement'],
        ['ad_budget_label', 'Daily Budget'],
        ['ad_duration_label', 'Campaign Duration'],
        ['profile_my_videos', 'My Videos'],
        ['profile_earnings', 'Earnings'],
        ['profile_settings', 'Settings'],
        ['error_network', 'Network error. Please check your connection.'],
        ['error_upload_failed', 'Upload failed. Please try again.'],
        ['error_invalid_url', 'Please enter a valid URL starting with http:// or https://'],
        ['success_upload', 'Upload successful!'],
        ['success_ad_created', 'Advertisement created successfully!'],
      ]),
      killSwitch: {
        enabled: false,
        message: 'The app is temporarily unavailable. Please try again later.',
        maintenanceMode: false,
        maintenanceMessage: 'We are performing maintenance. Some features may be unavailable.',
      },
      cacheSettings: {
        configCacheTTL: 300, // 5 minutes
        videoFeedCacheTTL: 180, // 3 minutes
      },
      isActive: true,
    });

    await config.save();
    console.log(`✅ AppConfig created successfully for ${platform}/${environment}`);
    console.log(`   Config ID: ${config._id}`);
    console.log(`   Min Version: ${config.versionControl.minSupportedAppVersion}`);
    console.log(`   Latest Version: ${config.versionControl.latestAppVersion}`);

    await mongoose.disconnect();
    console.log('✅ Disconnected from MongoDB');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error seeding AppConfig:', error);
    await mongoose.disconnect();
    process.exit(1);
  }
}

seedAppConfig();

