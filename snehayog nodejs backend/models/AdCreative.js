import mongoose from 'mongoose';

const AdCreativeSchema = new mongoose.Schema({
  campaignId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdCampaign',
    required: true
  },
  type: {
    type: String,
    required: true,
    enum: ['image', 'video']
  },
  cloudinaryUrl: {
    type: String,
    required: true
  },
  thumbnail: {
    type: String
  },
  aspectRatio: {
    type: String,
    required: true,
    enum: ['16:9', '9:16', '1:1', '4:3', '3:4']
  },
  durationSec: {
    type: Number,
    min: 1,
    max: 60,
    required: function() {
      return this.type === 'video';
    }
  },
  callToAction: {
    label: {
      type: String,
      required: true,
      enum: ['Learn More', 'Shop Now', 'Download', 'Sign Up', 'Get Started', 'Watch More']
    },
    url: {
      type: String,
      required: true,
      validate: {
        validator: function(v) {
          return /^https?:\/\/.+/.test(v);
        },
        message: 'URL must be a valid HTTP/HTTPS URL'
      }
    }
  },
  reviewStatus: {
    type: String,
    required: true,
    enum: ['pending', 'approved', 'rejected'],
    default: 'pending'
  },
  rejectionReason: {
    type: String,
    trim: true
  },
  isActive: {
    type: Boolean,
    default: false
  },
  impressions: {
    type: Number,
    default: 0
  },
  clicks: {
    type: Number,
    default: 0
  },
  ctr: {
    type: Number,
    default: 0
  }
}, {
  timestamps: true
});

// Calculate CTR
AdCreativeSchema.virtual('calculatedCtr').get(function() {
  if (this.impressions === 0) return 0;
  return (this.clicks / this.impressions) * 100;
});

// Pre-save middleware to update calculated fields
AdCreativeSchema.pre('save', function(next) {
  this.ctr = this.calculatedCtr;
  next();
});

// Only allow one active creative per campaign
AdCreativeSchema.index({ campaignId: 1, isActive: 1 }, { unique: true, sparse: true });

export default mongoose.models.AdCreative || mongoose.model('AdCreative', AdCreativeSchema);
