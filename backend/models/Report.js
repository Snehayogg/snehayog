import mongoose from 'mongoose';

const reportSchema = new mongoose.Schema(
  {
    targetType: {
      type: String,
      enum: ['video', 'user', 'comment', 'other'],
      required: true,
      lowercase: true,
      trim: true,
    },
    targetId: {
      type: String,
      required: true,
      trim: true,
    },
    reason: {
      type: String,
      enum: ['spam', 'abusive', 'nudity', 'copyright', 'misinformation', 'other'],
      required: true,
      lowercase: true,
      trim: true,
    },
    details: {
      type: String,
      maxlength: 2000,
      trim: true,
    },
    userId: {
      type: String,
      trim: true,
    },
    status: {
      type: String,
      enum: ['open', 'reviewing', 'resolved', 'dismissed'],
      default: 'open',
    },
    userAgent: { type: String, trim: true },
    ipAddress: { type: String, trim: true },
  },
  { timestamps: true }
);

reportSchema.index({ createdAt: -1 });
reportSchema.index({ targetType: 1, targetId: 1 });

const Report = mongoose.model('Report', reportSchema);

export default Report;


