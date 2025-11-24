import mongoose from 'mongoose';

const CreatorPayoutSchema = new mongoose.Schema({
  creatorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  month: {
    type: String,
    required: true,
    validate: {
      validator: function(v) {
        // Format: YYYY-MM (e.g., 2024-01)
        return /^\d{4}-\d{2}$/.test(v);
      },
      message: 'Month must be in YYYY-MM format'
    }
  },
  // **NEW: Global Revenue Support**
  currency: {
    type: String,
    required: true,
    enum: ['INR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD'],
    default: 'INR'
  },
  exchangeRate: {
    type: Number,
    default: 1.0 // Rate relative to INR
  },
  impressions: {
    type: Number,
    required: true,
    min: 0
  },
  revenueINR: {
    type: Number,
    required: true,
    min: 0
  },
  // **NEW: Converted revenue in creator's currency**
  revenueInCreatorCurrency: {
    type: Number,
    required: true,
    min: 0
  },
  share: {
    type: Number,
    required: true,
    default: 0.8, // 80% to creator
    min: 0,
    max: 1
  },
  payableINR: {
    type: Number,
    required: true,
    min: 0
  },
  // **NEW: Converted payable amount**
  payableInCreatorCurrency: {
    type: Number,
    required: true,
    min: 0
  },
  status: {
    type: String,
    required: true,
    enum: ['pending', 'processing', 'paid', 'failed'],
    default: 'pending'
  },
  // **NEW: Global Payment Methods**
  paymentMethod: {
    type: String,
    enum: [
      // Indian methods
      'upi', 'card_payment',
      // International methods
      'paypal', 'stripe', 'wise', 'payoneer'
    ]
  },
  // **NEW: Payment Details based on method**
  paymentDetails: {
    // For UPI
    upiId: String,
    // **NEW: Card Payment Details**
    cardDetails: {
      cardNumber: String,
      expiryDate: String,
      cvv: String,
      cardholderName: String
    },
    // For International
    paypalEmail: String,
    stripeAccountId: String,
    wiseEmail: String
  },
  paymentReference: {
    type: String,
    trim: true
  },
  paymentDate: {
    type: Date
  },
  notes: {
    type: String,
    trim: true
  },
  // **NEW: Dynamic threshold based on payout count**
  isFirstPayout: {
    type: Boolean,
    default: true
  },
  payoutCount: {
    type: Number,
    default: 0
  },
  // **NEW: Currency-specific thresholds (only for 2nd+ payout)**
  minimumPayoutThreshold: {
    INR: { type: Number, default: 200 }, // ₹200 for 2nd+ payout
    USD: { type: Number, default: 5 },   // $5 for 2nd+ payout
    EUR: { type: Number, default: 5 },   // €5 for 2nd+ payout
    GBP: { type: Number, default: 5 },   // £5 for 2nd+ payout
    CAD: { type: Number, default: 7 },   // C$7 for 2nd+ payout
    AUD: { type: Number, default: 7 }    // A$7 for 2nd+ payout
  },
  isEligibleForPayout: {
    type: Boolean,
    default: false
  },
  // **NEW: Tax and compliance**
  taxDeduction: {
    type: Number,
    default: 0
  },
  gstNumber: String, // For Indian creators
  panNumber: String, // For Indian creators
  // **NEW: International compliance**
  taxForm: {
    w8ben: Boolean, // For non-US creators
    w9: Boolean,    // For US creators
    gst: Boolean    // For Indian creators
  }
}, {
  timestamps: true
});

// **NEW: Calculate payable amount and eligibility based on payout count**
CreatorPayoutSchema.pre('save', function(next) {
  if (this.revenueINR && this.share) {
    this.payableINR = this.revenueINR * this.share;
    
    // Convert to creator's currency
    if (this.currency !== 'INR' && this.exchangeRate) {
      this.payableInCreatorCurrency = this.payableINR / this.exchangeRate;
      this.revenueInCreatorCurrency = this.revenueINR / this.exchangeRate;
    } else {
      this.payableInCreatorCurrency = this.payableINR;
      this.revenueInCreatorCurrency = this.revenueINR;
    }
  }
  
  // **NEW: Dynamic threshold logic**
  if (this.isFirstPayout) {
    // First payout: No minimum threshold
    this.isEligibleForPayout = this.payableInCreatorCurrency > 0;
  } else {
    // Second+ payout: Apply currency-specific threshold
    const threshold = this.minimumPayoutThreshold[this.currency] || this.minimumPayoutThreshold.INR;
    this.isEligibleForPayout = this.payableInCreatorCurrency >= threshold;
  }
  
  next();
});

// **NEW: Update payout count when payout is processed**
CreatorPayoutSchema.pre('save', async function(next) {
  if (this.isModified('status') && this.status === 'paid') {
    // Increment payout count for the creator
    await mongoose.model('User').findByIdAndUpdate(
      this.creatorId,
      { $inc: { payoutCount: 1 } }
    );
  }
  next();
});

// Ensure unique creator-month combination
CreatorPayoutSchema.index({ creatorId: 1, month: 1 }, { unique: true });

// Index for faster queries
CreatorPayoutSchema.index({ status: 1, month: 1 });
CreatorPayoutSchema.index({ creatorId: 1, status: 1 });
CreatorPayoutSchema.index({ currency: 1, status: 1 });
CreatorPayoutSchema.index({ isFirstPayout: 1, status: 1 });

// **NEW: Virtual for formatted month display**
CreatorPayoutSchema.virtual('formattedMonth').get(function() {
  const [year, month] = this.month.split('-');
  const date = new Date(parseInt(year), parseInt(month) - 1);
  return date.toLocaleDateString('en-IN', { year: 'numeric', month: 'long' });
});

// **NEW: Virtual for formatted amount in creator's currency**
CreatorPayoutSchema.virtual('formattedPayableAmount').get(function() {
  const symbols = {
    'INR': '₹', 'USD': '$', 'EUR': '€', 'GBP': '£', 'CAD': 'C$', 'AUD': 'A$'
  };
  const symbol = symbols[this.currency] || '₹';
  return `${symbol}${this.payableInCreatorCurrency.toFixed(2)}`;
});

// **NEW: Virtual for payment method display**
CreatorPayoutSchema.virtual('paymentMethodDisplay').get(function() {
  const methodNames = {
    'upi': 'UPI',
    'paytm': 'Paytm',
    'phonepe': 'PhonePe',
    'paypal': 'PayPal',
    'stripe': 'Stripe',
    'wise': 'Wise',
    'payoneer': 'Payoneer'
  };
  return methodNames[this.paymentMethod] || this.paymentMethod;
});

// **NEW: Virtual for threshold display**
CreatorPayoutSchema.virtual('thresholdDisplay').get(function() {
  if (this.isFirstPayout) {
    return 'No minimum (First payout)';
  } else {
    const threshold = this.minimumPayoutThreshold[this.currency] || this.minimumPayoutThreshold.INR;
    const symbols = {
      'INR': '₹', 'USD': '$', 'EUR': '€', 'GBP': '£', 'CAD': 'C$', 'AUD': 'A$'
    };
    const symbol = symbols[this.currency] || '₹';
    return `${symbol}${threshold} minimum`;
  }
});

export default mongoose.models.CreatorPayout || mongoose.model('CreatorPayout', CreatorPayoutSchema);
