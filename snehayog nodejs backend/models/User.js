const mongoose = require('mongoose');

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
  }
});

// Add method to get user's videos
UserSchema.methods.getVideos = async function() {
  await this.populate({
    path: 'videos',
    populate: { path: 'uploader', select: 'name profilePic' }
  });
  return this.videos;
};

module.exports = mongoose.model('User', UserSchema);
