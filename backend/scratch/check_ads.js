import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '../.env') });

import AdCampaign from '../models/AdCampaign.js';
import AdCreative from '../models/AdCreative.js';

async function checkAds() {
  try {
    console.log('Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGO_URI);
    console.log('Connected!');

    const campaigns = await AdCampaign.find({});
    console.log(`Found ${campaigns.length} campaigns.`);
    campaigns.forEach(c => {
      console.log(`- Campaign: ${c.name}, ID: ${c._id}, Status: ${c.status}, Start: ${c.startDate}, End: ${c.endDate}`);
    });

    const creatives = await AdCreative.find({});
    console.log(`Found ${creatives.length} creatives.`);
    creatives.forEach(cr => {
      console.log(`- Creative: ${cr.title || 'No Title'}, ID: ${cr._id}, Type: ${cr.adType}, Active: ${cr.isActive}, Status: ${cr.reviewStatus}, Campaign: ${cr.campaignId}`);
    });

    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

checkAds();
