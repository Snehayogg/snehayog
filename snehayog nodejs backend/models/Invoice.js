import mongoose from 'mongoose';

const InvoiceSchema = new mongoose.Schema({
  campaignId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdCampaign',
    required: true
  },
  orderId: {
    type: String,
    required: true,
    unique: true
  },
  amountINR: {
    type: Number,
    required: true,
    min: 100 // Minimum ₹100
  },
  status: {
    type: String,
    required: true,
    enum: ['created', 'paid', 'failed', 'refunded'],
    default: 'created'
  },
  razorpayPaymentId: {
    type: String,
    sparse: true
  },
  razorpaySignature: {
    type: String,
    sparse: true
  },
  paymentMethod: {
    type: String,
    enum: ['upi', 'card', 'netbanking', 'wallet', 'other']
  },
  paymentDate: {
    type: Date
  },
  refundAmount: {
    type: Number,
    default: 0
  },
  refundReason: {
    type: String,
    trim: true
  },
  refundDate: {
    type: Date
  },
  description: {
    type: String,
    trim: true
  },
  invoiceNumber: {
    type: String,
    unique: true,
    required: true
  },
  dueDate: {
    type: Date,
    required: true
  },
  taxAmount: {
    type: Number,
    default: 0
  },
  totalAmount: {
    type: Number,
    required: true
  }
}, {
  timestamps: true
});

// Generate invoice number
InvoiceSchema.pre('save', function(next) {
  if (this.isNew && !this.invoiceNumber) {
    const date = new Date();
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
    this.invoiceNumber = `INV-${year}${month}-${random}`;
  }
  
  // Calculate total amount including tax
  if (this.amountINR && this.taxAmount !== undefined) {
    this.totalAmount = this.amountINR + this.taxAmount;
  } else {
    this.totalAmount = this.amountINR;
  }
  
  next();
});

// Index for faster queries
InvoiceSchema.index({ campaignId: 1, status: 1 });
InvoiceSchema.index({ orderId: 1 });
InvoiceSchema.index({ status: 1, createdAt: -1 });

export default mongoose.models.Invoice || mongoose.model('Invoice', InvoiceSchema);
