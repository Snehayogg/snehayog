import mongoose from 'mongoose';

const AdCampaignSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true
  },
  advertiserUserId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  objective: {
    type: String,
    required: true,
    enum: ['awareness', 'consideration', 'conversion']
  },
  status: {
    type: String,
    required: true,
    enum: ['draft', 'pending_review', 'active', 'paused', 'completed'],
    default: 'draft'
  },
  startDate: {
    type: Date,
    required: true
  },
  endDate: {
    type: Date,
    required: true
  },
  dailyBudget: {
    type: Number,
    required: true,
    min: 100 // Minimum ₹100 per day
  },
  totalBudget: {
    type: Number,
    min: 1000 // Minimum ₹1000 total
  },
  bidType: {
    type: String,
    default: 'CPM',
    enum: ['CPM', 'CPC']
  },
  cpmINR: {
    type: Number,
    default: 30,
    min: 10,
    max: 1000
  },
  target: {
    age: {
      min: { type: Number, min: 13, max: 65 },
      max: { type: Number, min: 13, max: 65 }
    },
    gender: {
      type: String,
      enum: ['all', 'male', 'female', 'other']
    },
    locations: [{
      type: String,
      trim: true
    }],
    interests: [{
      type: String,
      trim: true
    }],
    platforms: [{
      type: String,
      enum: ['android', 'ios', 'web']
    }],

    deviceType: {
      type: String,
      enum: ['mobile', 'tablet', 'desktop', 'all'],
      default: 'all'
    }
  },

  optimizationGoal: {
    type: String,
    enum: ['clicks', 'impressions', 'conversions'],
    default: 'impressions'
  },
  timeZone: {
    type: String,
    default: 'Asia/Kolkata'
  },
  dayParting: {
    type: Map,
    of: Boolean,
    default: {}
  },
  hourParting: {
    type: Map,
    of: String,
    default: {}
  },
  pacing: {
    type: String,
    default: 'smooth',
    enum: ['smooth', 'asap']
  },
  frequencyCap: {
    type: Number,
    default: 3,
    min: 1,
    max: 10
  },
  // **ENHANCED: Performance tracking fields**
  impressions: {
    type: Number,
    default: 0
  },
  clicks: {
    type: Number,
    default: 0
  },
  spend: {
    type: Number,
    default: 0
  },
  ctr: {
    type: Number,
    default: 0
  },
  cpm: {
    type: Number,
    default: 0
  },
  // **NEW: Additional performance metrics**
  conversions: {
    type: Number,
    default: 0
  },
  conversionRate: {
    type: Number,
    default: 0
  },
  costPerConversion: {
    type: Number,
    default: 0
  },
  reach: {
    type: Number,
    default: 0
  },
  frequency: {
    type: Number,
    default: 0
  },
  engagementRate: {
    type: Number,
    default: 0
  },
  roas: { // Return on Ad Spend
    type: Number,
    default: 0
  }
}, {
  timestamps: true
});

// Calculate CTR
AdCampaignSchema.virtual('calculatedCtr').get(function() {
  if (this.impressions === 0) return 0;
  return (this.clicks / this.impressions) * 100;
});

// Calculate CPM
AdCampaignSchema.virtual('calculatedCpm').get(function() {
  if (this.impressions === 0) return 0;
  return (this.spend / this.impressions) * 1000;
});

// Pre-save middleware to update calculated fields
AdCampaignSchema.pre('save', function(next) {
  this.ctr = this.calculatedCtr;
  this.cpm = this.calculatedCpm;
  next();
});

export default mongoose.models.AdCampaign || mongoose.model('AdCampaign', AdCampaignSchema);
