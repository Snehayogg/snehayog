import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Setup __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load the .env file from the backend folder
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import AdImpression from '../models/AdImpression.js';
import CreatorMonthlyStat from '../models/CreatorMonthlyStat.js';

async function migrate() {
  if (!process.env.MONGO_URI) {
    console.error('❌ MONGODB_URI is undefined. Make sure it is set in backend/.env');
    process.exit(1);
  }

  await mongoose.connect(process.env.MONGO_URI);
  console.log('✅ Connected to DB:', process.env.MONGO_URI.split('@')[1] || process.env.MONGO_URI);

  const impressions = await AdImpression.find({}).lean();
  console.log(`📊 Found ${impressions.length} ad impressions to sync...`);

  let count = 0;
  const bulkOps = [];

  for (const imp of impressions) {
    if (!imp.creatorId) continue;
    
    // Convert UTC to IST (+5:30)
    const dt = new Date(imp.timestamp);
    const ist = new Date(dt.getTime() + (5.5 * 60 * 60 * 1000));
    const yearMonth = `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}`;

    if (imp.adType === 'banner') {
      bulkOps.push({
        updateOne: {
          filter: { creatorId: imp.creatorId, yearMonth },
          update: { $inc: { bannerImpressions: 1, grossRevenue: (1 / 1000) * 20 } },
          upsert: true
        }
      });
      count++;
    } else if (imp.adType === 'carousel') {
      bulkOps.push({
        updateOne: {
          filter: { creatorId: imp.creatorId, yearMonth },
          update: { $inc: { carouselImpressions: 1, grossRevenue: (1 / 1000) * 30 } },
          upsert: true
        }
      });
      count++;
    }
  }

  // Execute in batches of 5000 to prevent RAM spikes
  console.log(`Executing ${bulkOps.length} operations via bulkWrite...`);
  const batchSize = 5000;
  for (let i = 0; i < bulkOps.length; i += batchSize) {
    const batch = bulkOps.slice(i, i + batchSize);
    await CreatorMonthlyStat.bulkWrite(batch);
    console.log(`✅ Processed batch ${i / batchSize + 1} (${batch.length} ops)`);
  }

  console.log(`✅ Migration complete! Successfully synced ${count} valid video ad impressions into CreatorMonthlyStats.`);
  process.exit(0);
}

migrate().catch(console.error);
