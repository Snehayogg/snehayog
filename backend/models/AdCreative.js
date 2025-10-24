import mongoose from 'mongoose';

const AdCreativeSchema = new mongoose.Schema({
  campaignId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdCampaign',
    required: true
  },
  adType: {
    type: String,
    required: true,
    enum: ['banner', 'carousel', 'video feed ad'],
    default: 'banner'
  },
  type: {
    type: String,
    required: true,
    enum: ['image', 'video'],
    validate: {
      validator: function(v) {
        // Banner ads can only use images
        if (this.adType === 'banner' && v !== 'image') {
          return false;
        }
        // Carousel ads and video feeds can use both images and videos
        return true;
      },
      message: 'Banner ads can only use images. Carousel ads and video feeds can use both images and videos.'
    }
  },
  cloudinaryUrl: {
    type: String,
    required: function() {
      // Only required for banner and video feed ads
      // Carousel ads use slides array instead
      return this.adType !== 'carousel';
    }
  },
  thumbnail: {
    type: String
  },
  aspectRatio: {
    type: String,
    required: function() {
      // Only required for banner and video feed ads
      // Carousel ads have aspect ratio per slide
      return this.adType !== 'carousel';
    },
    enum: ['16:9', '9:16', '1:1', '4:3', '3:4']
  },
  durationSec: {
    type: Number,
    min: 1,
    max: 60,
    required: function() {
      return this.type === 'video' && this.adType !== 'carousel';
    }
  },
  // **NEW: Slides array for carousel ads**
  slides: [{
    mediaUrl: {
      type: String,
      required: true
    },
    thumbnail: {
      type: String
    },
    mediaType: {
      type: String,
      enum: ['image', 'video'],
      default: 'image'
    },
    aspectRatio: {
      type: String,
      enum: ['16:9', '9:16', '1:1', '4:3', '3:4'],
      default: '9:16'
    },
    durationSec: {
      type: Number,
      min: 1,
      max: 60
    },
    title: {
      type: String
    },
    description: {
      type: String
    }
  }],
  // **NEW: Title field for banner ads**
  title: {
    type: String,
    required: function() {
      return this.adType === 'banner';
    },
    trim: true,
    maxlength: 150, // Max 30 words (5 chars per word average)
    validate: {
      validator: function(v) {
        if (this.adType === 'banner' && (!v || v.trim().length === 0)) {
          return false;
        }
        // Check word count (max 30 words)
        if (v && v.trim().split(/\s+/).length > 30) {
          return false;
        }
        return true;
      },
      message: 'Banner ads require a title with maximum 30 words'
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
      required: false, // **FIX: Make URL optional - not all ads need links**
      validate: {
        validator: function(v) {
          // Allow empty URLs or valid HTTP/HTTPS URLs
          return !v || /^https?:\/\/.+/.test(v);
        },
        message: 'URL must be empty or a valid HTTP/HTTPS URL'
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

// Pre-save middleware to validate adType and type combination
AdCreativeSchema.pre('save', function(next) {
  // Validate banner ads can only use images
  if (this.adType === 'banner' && this.type !== 'image') {
    const error = new Error('Banner ads can only use images');
    return next(error);
  }
  
  // Validate video ads require duration
  if (this.type === 'video' && (!this.durationSec || this.durationSec < 1 || this.durationSec > 60)) {
    const error = new Error('Video ads require duration between 1-60 seconds');
    return next(error);
  }
  
  next();
});

// Add indexes for better performance
AdCreativeSchema.index({ adType: 1 }); // For filtering by ad type
AdCreativeSchema.index({ campaignId: 1, adType: 1 }); // For finding creatives by campaign and ad type

export default mongoose.models.AdCreative || mongoose.model('AdCreative', AdCreativeSchema);
