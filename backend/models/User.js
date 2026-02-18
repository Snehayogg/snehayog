import mongoose from 'mongoose';

const UserSchema = new mongoose.Schema({
  googleId: {
    type: String,
    required: true,
    unique: true
  },
  name: {
    type: String,
    required: true
  },
  email: {
    type: String,
    required: true,
    unique: true
  },
  profilePic: {
    type: String
  },
  videos: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video'
  }],
  // **NEW: Follow/Unfollow functionality**
  following: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  followers: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  // **NEW: Saved/Bookmarked Videos**
  savedVideos: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video'
  }],
  // **NEW: Payment and Payout Preferences**
  preferredCurrency: {
    type: String,
    enum: ['INR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD'],
    default: 'INR'
  },
  preferredPaymentMethod: {
    type: String,
    enum: [
      'upi', 'card_payment',
      'paypal', 'stripe', 'wise', 'payoneer'
    ]
  },
  paymentDetails: {
    // UPI
    upiId: String,
    // **NEW: Card Payment Details**
    cardDetails: {
      cardNumber: String,
      expiryDate: String,
      cvv: String,
      cardholderName: String
    },
    // International
    paypalEmail: String,
    stripeAccountId: String,
    wiseEmail: String
  },
  country: {
    type: String,
    default: 'IN'
  },
  // **NEW: Tax Information**
  taxInfo: {
    panNumber: String,    // For Indians
    gstNumber: String,    // For Indians
    w8benSubmitted: Boolean, // For non-US
    w9Submitted: Boolean,    // For US
    taxResidency: String
  },
  // **NEW: Track payout count**
  payoutCount: {
    type: Number,
    default: 0
  },
  // **NEW: Device IDs - Store device IDs that have logged in with this account**
  // This allows skipping login screen after app reinstall
  deviceIds: [{
    type: String,
    trim: true,
    index: true
  }],
  // **NEW: FCM Token for push notifications**
  fcmToken: {
    type: String,
    default: null
  },
  // **NEW: Track last active time for identifying inactive users**
  lastActive: {
    type: Date,
    default: Date.now,
    index: true
  },
  isAppUninstalled: {
    type: Boolean,
    default: false
  },
  lastInstallCheck: {
    type: Date
  },
  // **NEW: Location Data**
  location: {
    latitude: {
      type: Number,
      required: false
    },
    longitude: {
      type: Number,
      required: false
    },
    address: {
      type: String,
      required: false
    },
    city: {
      type: String,
      required: false
    },
    state: {
      type: String,
      required: false
    },
    country: {
      type: String,
      required: false
    },
    lastUpdated: {
      type: Date,
      default: Date.now
    },
    permissionGranted: {
      type: Boolean,
      default: false
    }
  }
}, {
  timestamps: true
});

// Add method to get user's videos
UserSchema.methods.getVideos = async function() {
  await this.populate({
    path: 'videos',
    populate: { path: 'uploader', select: 'name profilePic' }
  });
  return this.videos;
};

// Add method to check if following a user
UserSchema.methods.isFollowing = function(userId) {
  return this.following.includes(userId);
};

// Add method to follow a user
UserSchema.methods.follow = function(userId) {
  if (!this.isFollowing(userId)) {
    this.following.push(userId);
    return true;
  }
  return false;
};

// Add method to unfollow a user
UserSchema.methods.unfollow = function(userId) {
  const index = this.following.indexOf(userId);
  if (index > -1) {
    this.following.splice(index, 1);
    return true;
  }
  return false;
};

// **NEW: Saved Video Methods**
UserSchema.methods.isSaved = function(videoId) {
  return this.savedVideos.some(id => id.toString() === videoId.toString());
};

UserSchema.methods.saveVideo = function(videoId) {
  if (!this.isSaved(videoId)) {
    this.savedVideos.push(videoId);
    return true;
  }
  return false;
};

UserSchema.methods.unsaveVideo = function(videoId) {
  const videoIdStr = videoId.toString();
  const index = this.savedVideos.findIndex(id => id.toString() === videoIdStr);
  if (index > -1) {
    this.savedVideos.splice(index, 1);
    return true;
  }
  return false;
};

export default mongoose.models.User || mongoose.model('User', UserSchema);

