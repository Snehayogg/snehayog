import mongoose from 'mongoose';

const ReferralSchema = new mongoose.Schema({
  referrerGoogleId: { type: String, index: true, required: true },
  code: { type: String, unique: true, index: true, required: true },
  installedCount: { type: Number, default: 0 },
  signedUpCount: { type: Number, default: 0 },
}, { timestamps: true });

export default mongoose.models.Referral || mongoose.model('Referral', ReferralSchema);


