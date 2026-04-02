import mongoose from 'mongoose';

const CreatorMonthlyStatSchema = new mongoose.Schema({
  creatorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  yearMonth: {
    type: String, // Format: 'YYYY-MM'
    required: true,
    index: true
  },
  bannerImpressions: {
    type: Number,
    default: 0
  },
  carouselImpressions: {
    type: Number,
    default: 0
  },
  grossRevenue: {
    type: Number, 
    default: 0.0
  }
}, {
  timestamps: true
});

// A unique index per creator + month ensures atomic $inc upserts function correctly
CreatorMonthlyStatSchema.index({ creatorId: 1, yearMonth: 1 }, { unique: true });

export default mongoose.models.CreatorMonthlyStat || mongoose.model('CreatorMonthlyStat', CreatorMonthlyStatSchema);
