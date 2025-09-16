import mongoose from 'mongoose';

const commentSchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  text: {
    type: String,
    required: true,
    trim: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  },
  likes: {
    type: Number,
    default: 0
  },
  likedBy: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  replies: [{
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true
    },
    text: {
      type: String,
      required: true,
      trim: true
    },
    createdAt: {
      type: Date,
      default: Date.now
    },
    likes: {
      type: Number,
      default: 0
    }
  }]
}, {
  timestamps: true
});

// Indexes for better performance
commentSchema.index({ user: 1, createdAt: -1 });
commentSchema.index({ createdAt: -1 });

// Virtual for comment age
commentSchema.virtual('age').get(function() {
  const now = new Date();
  const diff = now.getTime() - this.createdAt.getTime();
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) return '${Math.floor(days / 7)} weeks ago';
  if (days < 365) return '${Math.floor(days / 30)} months ago';
  return '${Math.floor(days / 365)} years ago';
});

// Method to add like
commentSchema.methods.addLike = function(userId) {
  if (!this.likedBy.includes(userId)) {
    this.likedBy.push(userId);
    this.likes += 1;
    return this.save();
  }
  return Promise.resolve(this);
};

// Method to remove like
commentSchema.methods.removeLike = function(userId) {
  const index = this.likedBy.indexOf(userId);
  if (index > -1) {
    this.likedBy.splice(index, 1);
    this.likes = Math.max(0, this.likes - 1);
    return this.save();
  }
  return Promise.resolve(this);
};

// Method to add reply
commentSchema.methods.addReply = function(userId, text) {
  this.replies.push({
    user: userId,
    text: text
  });
  return this.save();
};

export default mongoose.model('Comment', commentSchema);
