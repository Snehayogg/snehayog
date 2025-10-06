// MongoDB initialization script
// This script runs when the MongoDB container starts for the first time

// Switch to the snehayog database
db = db.getSiblingDB('snehayog');

// Create collections with proper indexes
db.createCollection('users');
db.createCollection('videos');
db.createCollection('comments');
db.createCollection('adcampaigns');
db.createCollection('adcreatives');
db.createCollection('creatorpayouts');
db.createCollection('invoices');

// Create indexes for better performance
db.users.createIndex({ "email": 1 }, { unique: true });
db.users.createIndex({ "googleId": 1 }, { unique: true, sparse: true });
db.users.createIndex({ "createdAt": 1 });

db.videos.createIndex({ "userId": 1 });
db.videos.createIndex({ "createdAt": -1 });
db.videos.createIndex({ "status": 1 });
db.videos.createIndex({ "title": "text", "description": "text" });

db.comments.createIndex({ "videoId": 1 });
db.comments.createIndex({ "userId": 1 });
db.comments.createIndex({ "createdAt": -1 });

db.adcampaigns.createIndex({ "userId": 1 });
db.adcampaigns.createIndex({ "status": 1 });
db.adcampaigns.createIndex({ "createdAt": -1 });

db.adcreatives.createIndex({ "campaignId": 1 });
db.adcreatives.createIndex({ "status": 1 });

db.creatorpayouts.createIndex({ "userId": 1 });
db.creatorpayouts.createIndex({ "status": 1 });
db.creatorpayouts.createIndex({ "createdAt": -1 });

db.invoices.createIndex({ "userId": 1 });
db.invoices.createIndex({ "status": 1 });
db.invoices.createIndex({ "createdAt": -1 });

print('✅ Snehayog database initialized successfully');
print('📊 Collections created: users, videos, comments, adcampaigns, adcreatives, creatorpayouts, invoices');
print('🔍 Indexes created for optimal performance');
