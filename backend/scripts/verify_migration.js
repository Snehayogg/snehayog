
import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Load environment variables
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../.env') });

import AdImpression from '../models/AdImpression.js';

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/snehayog';

async function check() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');

    const total = await AdImpression.countDocuments();
    const withCreatordId = await AdImpression.countDocuments({ creatorId: { $exists: true } });
    const withoutCreatorId = await AdImpression.countDocuments({ $or: [{ creatorId: { $exists: false } }, { creatorId: null }] });

    console.log(`Total Impressions: ${total}`);
    console.log(`With creatorId: ${withCreatordId}`);
    console.log(`Without creatorId: ${withoutCreatorId}`);
    
    // Check for "Wow Ro" specific data if possible, but we don't know their ID easily without query
    // Let's just dump 5 recent ones
    const recent = await AdImpression.find().sort({timestamp: -1}).limit(5).lean();
    console.log('Recent 5 impressions:', JSON.stringify(recent, null, 2));

  } catch (error) {
    console.error('❌ Check failed:', error);
  } finally {
    await mongoose.disconnect();
    process.exit();
  }
}

check();
