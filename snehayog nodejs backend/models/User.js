import mongoose from 'mongoose';

const UserSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true
  },
  googleId: {
    type: String,
    required: true,
    unique: true
  },
  videos: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video'
  }],
  email: {
    type: String,
    required: true,
    unique: true
  },
  profilePic: {
    type: String
  },
  // Add following and followers fields for follow functionality
  following: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  followers: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }]
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

export default mongoose.models.User || mongoose.model('User', UserSchema);

