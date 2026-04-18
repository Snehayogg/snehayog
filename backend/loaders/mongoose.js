import databaseManager from '../config/database.js';
import '../models/index.js';

export default async () => {
  const mongoUri = process.env.MONGO_URI;
  if (!mongoUri) {
    console.warn('⚠️ Missing environment variable: MONGO_URI');
    console.warn('⚠️ Database features will be unavailable');
    return null;
  }

  // Set the environment variable for consistency if it was only MONGO_URI
  process.env.MONGO_URI = mongoUri;

  try {
    // Database connection happens in background (non-blocking in the main loop)
    // but the loader returns the promise for orchestration if needed.
    const connection = databaseManager.connect();
    
    connection.then(() => {
      console.log('✅ Database connected successfully');
    }).catch((error) => {
      console.error('❌ Database connection failed:', error.message);
      console.log('⚠️ Database will retry connection automatically');
    });

    return databaseManager;
  } catch (error) {
    console.error('❌ database loader failed:', error);
    throw error;
  }
};
