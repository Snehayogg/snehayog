import mongoose from 'mongoose';

const PlatformRevenueSchema = new mongoose.Schema({
  invoiceId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Invoice',
    required: true,
    unique: true
  },
  orderId: {
    type: String,
    required: true,
    index: true
  },
  amount: {
    type: Number,
    required: true,
    min: 0
  },
  currency: {
    type: String,
    required: true,
    enum: ['INR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD'],
    default: 'INR'
  },
  collectedAt: {
    type: Date,
    required: true,
    default: Date.now
  },
  status: {
    type: String,
    required: true,
    enum: ['pending', 'collected', 'withdrawn'],
    default: 'collected'
  },
  // **NEW: Related payment information for tracking**
  paymentGateway: {
    type: String,
    enum: ['razorpay', 'stripe'],
    required: true
  },
  paymentMethod: {
    type: String,
    enum: ['upi', 'card', 'netbanking', 'wallet', 'other']
  },
  // **NEW: Withdrawal tracking for manual payouts**
  withdrawnAt: {
    type: Date
  },
  withdrawalReference: {
    type: String,
    trim: true
  },
  notes: {
    type: String,
    trim: true
  }
}, {
  timestamps: true
});

// Index for faster queries
PlatformRevenueSchema.index({ status: 1, collectedAt: -1 });
PlatformRevenueSchema.index({ currency: 1, status: 1 });
PlatformRevenueSchema.index({ invoiceId: 1 });

// Virtual for formatted amount
PlatformRevenueSchema.virtual('formattedAmount').get(function() {
  const symbols = {
    'INR': '₹', 'USD': '$', 'EUR': '€', 'GBP': '£', 'CAD': 'C$', 'AUD': 'A$'
  };
  const symbol = symbols[this.currency] || '₹';
  return `${symbol}${this.amount.toFixed(2)}`;
});

export default mongoose.models.PlatformRevenue || mongoose.model('PlatformRevenue', PlatformRevenueSchema);
