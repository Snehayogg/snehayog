import express from 'express';
import Referral from '../models/Referral.js';
import User from '../models/User.js';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

function generateCode(googleId) {
  const base = Buffer.from(googleId).toString('base64').replace(/=+$/, '');
  return base.slice(0, 10);
}

// Get or create referral code for current user
router.get('/code', verifyToken, async (req, res) => {
  try {
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user) return res.status(401).json({ error: 'User not found' });

    let ref = await Referral.findOne({ referrerGoogleId: user.googleId });
    if (!ref) {
      const code = generateCode(user.googleId);
      ref = await Referral.create({ referrerGoogleId: user.googleId, code });
    }

    res.json({ code: ref.code, referrerGoogleId: user.googleId });
  } catch (e) {
    console.error('❌ Referral code error:', e);
    res.status(500).json({ error: 'Failed to get referral code' });
  }
});

// Resolve code to referrer
router.get('/resolve/:code', async (req, res) => {
  try {
    const ref = await Referral.findOne({ code: req.params.code });
    if (!ref) return res.status(404).json({ error: 'Code not found' });
    res.json({ referrerGoogleId: ref.referrerGoogleId });
  } catch (e) {
    res.status(500).json({ error: 'Failed to resolve code' });
  }
});

// Track install or signup
router.post('/track', async (req, res) => {
  try {
    const { code, event } = req.body; // event: 'install' | 'signup'
    if (!code || !event) return res.status(400).json({ error: 'code and event required' });
    const ref = await Referral.findOne({ code });
    if (!ref) return res.status(404).json({ error: 'Code not found' });

    if (event === 'signup') ref.signedUpCount += 1;
    else ref.installedCount += 1;
    await ref.save();
    res.json({ installed: ref.installedCount, signedUp: ref.signedUpCount });
  } catch (e) {
    console.error('❌ Referral track error:', e);
    res.status(500).json({ error: 'Failed to track referral' });
  }
});

// Stats for current user
router.get('/stats', verifyToken, async (req, res) => {
  try {
    const ref = await Referral.findOne({ referrerGoogleId: req.user.googleId });
    if (!ref) return res.json({ installed: 0, signedUp: 0, code: generateCode(req.user.googleId) });
    res.json({ installed: ref.installedCount, signedUp: ref.signedUpCount, code: ref.code });
  } catch (e) {
    res.status(500).json({ error: 'Failed to get stats' });
  }
});

export default router;


