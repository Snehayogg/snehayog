const { verifyGoogleToken, generateJWT } = require('../utils/verifytoken');
const User = require('../models/User');

const googleSignIn = async (req, res) => {
  const { idToken } = req.body;

  try {
    const userData = await verifyGoogleToken(idToken);

    let user = await User.findOne({ googleId: userData.sub });
    if (!user) {
      user = new User({
        name: userData.name,
        email: userData.email,
        profilePic: userData.picture,
        videos: [], // Include videos field
      });
      await user.save();
    }

    const token = generateJWT(user._id);

    res.json({
      token,
      user: {
        name: user.name,
        email: user.email,
        profilePic: user.profilePic,
        videos: user.videos,
      },
    });
  } catch (error) {
    console.error(error);
    res.status(400).json({ error: 'Google SignIn failed' });
  }
};

module.exports = { googleSignIn };
