import express from 'express';
import CreatorPayout from '../models/CreatorPayout.js';
import User from '../models/User.js';
import { verifyToken } from '../utils/verifytoken.js';
import requireAdminDashboardKey from '../middleware/adminDashboardAuth.js';

const router = express.Router();

// **NEW: Test endpoint to verify backend is working**
router.get('/test', (req, res) => {
  console.log('✅ Test endpoint hit successfully');
  res.json({ 
    message: 'Creator payout backend is working!',
    timestamp: new Date().toISOString(),
    routes: [
      'GET /test - This test endpoint',
      'GET /profile - Get creator payout profile',
      'PUT /payment-method - Update payment method',
      'POST /monthly - Create monthly payout record',
      'GET /monthly - Get monthly payouts',
      'POST /request - Request payout'
    ]
  });
});

// **NEW: Health check endpoint (no auth required)**
router.get('/health', (req, res) => {
  console.log('🏥 Health check endpoint hit');
  res.json({ 
    status: 'healthy',
    service: 'creator-payouts',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// **NEW: Get creator's payout profile with dynamic thresholds**
router.get('/profile', verifyToken, async (req, res) => {
  try {
    // console.log('🔍 Profile request received');
    // console.log('🔍 User from token:', req.user);
    
    const creatorId = req.user.id;
    // console.log('🔍 Creator ID:', creatorId);
    
    const user = await User.findOne({ googleId: creatorId });
    
    if (!user) {
      console.log('❌ User not found for Google ID:', creatorId);
      return res.status(404).json({ error: 'User not found' });
    }

    // console.log('✅ User found:', { ... });

    // **NEW: Check if this is first payout**
    const existingPayouts = await CreatorPayout.find({ 
      creatorId: user._id, 
      status: 'paid' 
    }).countDocuments();

    const isFirstPayout = existingPayouts === 0;
    const payoutCount = existingPayouts;

    /* console.log('🔍 Payout info:', {
      existingPayouts,
      isFirstPayout,
      payoutCount
    }); */

    const response = {
      creator: {
        id: user._id,
        googleId: user.googleId,
        name: user.name,
        email: user.email,
        country: user.country || 'IN',
        currency: user.preferredCurrency || 'INR',
        preferredPaymentMethod: user.preferredPaymentMethod,
        payoutCount: payoutCount
      },
      // **NEW: Include payment details for frontend validation**
      paymentDetails: user.paymentDetails || null,
      paymentMethods: _getAvailablePaymentMethods(user.country || 'IN'),
      // **NEW: Dynamic thresholds based on payout count**
      thresholds: {
        firstPayout: {
          INR: 'No minimum',
          USD: 'No minimum',
          EUR: 'No minimum',
          GBP: 'No minimum',
          CAD: 'No minimum',
          AUD: 'No minimum'
        },
        subsequentPayouts: {
          INR: '₹200 minimum',
          USD: '$5 minimum',
          EUR: '€5 minimum',
          GBP: '£5 minimum',
          CAD: 'C$7 minimum',
          AUD: 'A$7 minimum'
        }
      },
      currentThreshold: isFirstPayout ? 'No minimum (First payout)' : '₹200 minimum (Subsequent payouts)',
      isFirstPayout: isFirstPayout
    };

    // console.log('✅ Profile response prepared:', response);
    // console.log('🔍 Payment details in response:', response.paymentDetails);
    res.json(response);
  } catch (error) {
    console.error('❌ Payout profile error:', error);
    console.error('❌ Error stack:', error.stack);
    res.status(500).json({ error: 'Failed to get payout profile: ' + error.message });
  }
});

// **NEW: Update creator's payment method**
router.put('/payment-method', verifyToken, async (req, res) => {
  try {
    // console.log('🔍 Payment method update request received');
    
    const creatorId = req.user.id;
    const { paymentMethod, paymentDetails, currency, country, taxInfo } = req.body;

    // Find user by Google ID
    const user = await User.findOne({ googleId: creatorId });
    if (!user) {
      console.log('❌ User not found for Google ID:', creatorId);
      return res.status(404).json({ error: 'User not found' });
    }

    // console.log('✅ User found:', { ... });

    // Validate payment method based on country
    const availableMethods = _getAvailablePaymentMethods(country || user?.country || 'IN');
    // console.log('🔍 Available payment methods for country', country || user?.country || 'IN', ':', availableMethods);
    
    if (!availableMethods.includes(paymentMethod)) {
      console.log('❌ Payment method not available:', paymentMethod);
      return res.status(400).json({ 
        error: 'Payment method not available for your country' 
      });
    }

    // console.log('✅ Payment method validation passed');

    // Prepare update data
    const updateData = {
      preferredPaymentMethod: paymentMethod,
      paymentDetails: paymentDetails,
      country: country
    };

    // Only add taxInfo if it exists and has values
    if (taxInfo && (taxInfo.panNumber || taxInfo.gstNumber)) {
      updateData.taxInfo = taxInfo;
    }

    // console.log('🔍 Update data:', updateData);

    // Update user's payment preferences
    const updatedUser = await User.findByIdAndUpdate(
      user._id, 
      updateData,
      { new: true, runValidators: true }
    );

    if (!updatedUser) {
      console.log('❌ Failed to update user');
      return res.status(500).json({ error: 'Failed to update user profile' });
    }

    /* console.log('✅ User updated successfully:', {
      id: updatedUser._id,
      preferredPaymentMethod: updatedUser.preferredPaymentMethod,
      country: updatedUser.country
    }); */

    res.json({ message: 'Payment method updated successfully' });
  } catch (error) {
    console.error('❌ Payment method update error:', error);
    console.error('❌ Error stack:', error.stack);
    res.status(500).json({ error: 'Failed to update payment method: ' + error.message });
  }
});

// **NEW: Create monthly payout record**
router.post('/monthly', verifyToken, async (req, res) => {
  try {
    const creatorId = req.user.id;
    const user = await User.findOne({ googleId: creatorId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { month, impressions, revenueINR, currency, exchangeRate } = req.body;

    // **NEW: Check if this is first payout**
    const existingPayouts = await CreatorPayout.find({ 
      creatorId: user._id, 
      status: 'paid' 
    }).countDocuments();

    const isFirstPayout = existingPayouts === 0;

    // Create payout record
    const payout = new CreatorPayout({
      creatorId: user._id,
      month,
      impressions,
      revenueINR,
      currency: currency || 'INR',
      exchangeRate: exchangeRate || 1.0,
      isFirstPayout,
      payoutCount: existingPayouts
    });

    await payout.save();

    res.json({
      message: 'Monthly payout record created',
      payout: {
        id: payout._id,
        month: payout.month,
        payableAmount: payout.formattedPayableAmount,
        threshold: payout.thresholdDisplay,
        isEligible: payout.isEligibleForPayout
      }
    });

  } catch (error) {
    console.error('Monthly payout creation error:', error);
    res.status(500).json({ error: 'Failed to create monthly payout' });
  }
});

// **NEW: Get creator's monthly payouts**
router.get('/monthly', verifyToken, async (req, res) => {
  try {
    const creatorId = req.user.id;
    const user = await User.findOne({ googleId: creatorId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { month, status } = req.query;
    
    let query = { creatorId: user._id };
    if (month) query.month = month;
    if (status) query.status = status;

    const payouts = await CreatorPayout.find(query)
      .sort({ month: -1 })
      .limit(12);

    // **NEW: Add threshold information to each payout**
    const payoutsWithThresholds = payouts.map(payout => ({
      ...payout.toObject(),
      thresholdDisplay: payout.thresholdDisplay,
      isFirstPayout: payout.isFirstPayout
    }));

    res.json({ payouts: payoutsWithThresholds });
  } catch (error) {
    console.error('Monthly payouts error:', error);
    res.status(500).json({ error: 'Failed to get monthly payouts' });
  }
});

// **NEW: Request payout with dynamic threshold check**
router.post('/request', verifyToken, async (req, res) => {
  try {
    const creatorId = req.user.id;
    const user = await User.findOne({ googleId: creatorId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { month } = req.body;

    // Check if payout exists and is eligible
    const payout = await CreatorPayout.findOne({ 
      creatorId: user._id, 
      month
    });

    if (!payout) {
      return res.status(400).json({ 
        error: 'No payout record found for this month' 
      });
    }

    if (payout.status !== 'pending') {
      return res.status(400).json({ 
        error: 'Payout already processed' 
      });
    }

    // **NEW: Check eligibility based on dynamic threshold**
    if (!payout.isEligibleForPayout) {
      const threshold = payout.isFirstPayout ? 'any amount' : payout.thresholdDisplay;
      return res.status(400).json({ 
        error: `Payout not eligible. First payout: no minimum. Subsequent payouts: ${threshold}`,
        currentAmount: payout.formattedPayableAmount,
        requiredThreshold: threshold,
        isFirstPayout: payout.isFirstPayout
      });
    }

    // Update status to processing
    payout.status = 'processing';
    await payout.save();

    // Process payout
    const result = await _processPayout(payout);

    res.json({
      message: 'Payout request submitted successfully',
      payoutId: payout._id,
      status: payout.status,
      threshold: payout.thresholdDisplay,
      estimatedProcessingTime: result.processingTime
    });

  } catch (error) {
    console.error('Payout request error:', error);
    res.status(500).json({ error: 'Failed to request payout' });
  }
});

// **NEW: Admin endpoints for monitoring and control**
router.get('/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    const stats = await CreatorPayout.aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      }
    ]);

    const result = {
      total: 0,
      pending: 0,
      processing: 0,
      paid: 0,
      failed: 0
    };

    stats.forEach(stat => {
      result[stat._id] = stat.count;
      result.total += stat.count;
    });

    res.json(result);
  } catch (error) {
    console.error('Stats error:', error);
    res.status(500).json({ error: 'Failed to get stats' });
  }
});

router.get('/overview', requireAdminDashboardKey, async (req, res) => {
  try {
    const totalCreators = await User.countDocuments();
    const eligibleForPayout = await CreatorPayout.countDocuments({ 
      status: 'pending', 
      isEligibleForPayout: true 
    });
    
    const totalAmount = await CreatorPayout.aggregate([
      { $match: { status: 'pending', isEligibleForPayout: true } },
      { $group: { _id: null, total: { $sum: '$payableINR' } } }
    ]);

    // Calculate next payout date (1st of next month)
    const now = new Date();
    const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const nextPayoutDate = nextMonth.toLocaleDateString('en-IN', { 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric' 
    });

    res.json({
      totalCreators,
      eligibleForPayout,
      totalAmount: totalAmount.length > 0 ? `₹${totalAmount[0].total.toFixed(2)}` : '₹0',
      nextPayoutDate
    });
  } catch (error) {
    console.error('Overview error:', error);
    res.status(500).json({ error: 'Failed to get overview' });
  }
});

router.get('/recent', requireAdminDashboardKey, async (req, res) => {
  try {
    const recentPayouts = await CreatorPayout.find()
      .populate('creatorId', 'name')
      .sort({ createdAt: -1 })
      .limit(20);

    const payouts = recentPayouts.map(payout => ({
      ...payout.toObject(),
      creatorName: payout.creatorId?.name || 'Unknown'
    }));

    res.json({ payouts });
  } catch (error) {
    console.error('Recent payouts error:', error);
    res.status(500).json({ error: 'Failed to get recent payouts' });
  }
});

// **NEW: Helper function to get available payment methods by country**
function _getAvailablePaymentMethods(country) {
  const methods = {
    'IN': ['upi', 'card_payment'],
    'US': ['paypal', 'stripe', 'card_payment'],
    'CA': ['paypal', 'stripe', 'card_payment'],
    'GB': ['paypal', 'stripe', 'wise', 'card_payment'],
    'DE': ['paypal', 'stripe', 'wise', 'card_payment'],
    'AU': ['paypal', 'stripe', 'card_payment'],
    'default': ['paypal', 'stripe', 'wise', 'payoneer', 'card_payment']
  };
  
  return methods[country] || methods.default;
}

// **NEW: Helper function to process payouts**
async function _processPayout(payout) {
  const processingTimes = {
    'upi': '2-4 hours',
    'card_payment': '1-3 business days',
    'paypal': '1-3 business days',
    'stripe': '2-5 business days',
    'wise': '1-2 business days'
  };

  return {
    processingTime: processingTimes[payout.paymentMethod] || '3-5 business days',
    success: true
  };
}

export default router;
