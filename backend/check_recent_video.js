import dotenv from 'dotenv';
import mongoose from 'mongoose';
import Video from './models/Video.js';
import User from './models/User.js';

dotenv.config();

async function run() {
  try {
    const mongoUri = process.env.MONGO_URI;
    if (!mongoUri) {
      console.error('MONGODB_URI is not defined in .env');
      return;
    }

    await mongoose.connect(mongoUri);
    console.log('Connected to MongoDB.');

    // Fetch the 5 most recently uploaded videos
    const videos = await Video.find()
      .sort({ uploadedAt: -1 })
      .limit(5)
      .populate('uploader', 'name email')
      .lean();

    console.log(`Found ${videos.length} recent videos:\n`);
    videos.forEach((vid, index) => {
      console.log(`[${index + 1}] ID: ${vid._id}`);
      console.log(`    Name: ${vid.videoName}`);
      console.log(`    Uploaded At: ${vid.uploadedAt}`);
      console.log(`    Uploader: ${vid.uploader ? vid.uploader.name : 'Unknown'}`);
      console.log(`    isSubscriberOnly: ${vid.isSubscriberOnly}`);
      console.log(`    Tags: ${vid.tags}`);
      console.log('--------------------------------------------------');
    });

  } catch (error) {
    console.error('Error:', error);
  } finally {
    await mongoose.disconnect();
    console.log('Disconnected from MongoDB.');
  }
}

run();
