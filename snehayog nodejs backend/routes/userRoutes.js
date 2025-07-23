const express = require('express');
const router = express.Router();
const User = require('../models/User');

// ✅ Route to get user by MongoDB ID
router.get('/:id', async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select('name profilePic');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json(user);
  } catch (err) {
    console.error('Get user error:', err);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

module.exports = router;
