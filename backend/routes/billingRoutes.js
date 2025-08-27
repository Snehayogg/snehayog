import express from 'express';
import AdCampaign from '../models/AdCampaign.js';
import Invoice from '../models/Invoice.js';
import crypto from 'crypto';

const router = express.Router();

// POST /billing/create-order - Create Razorpay order
router.post('/create-order', async (req, res) => {
  try {
    const { campaignId, orderType = 'daily' } = req.body;

    // Validate campaign exists
    const campaign = await AdCampaign.findById(campaignId);
    if (!campaign) {
      return res.status(404).json({ error: 'Campaign not found' });
    }

    // Check if campaign belongs to user
    if (campaign.advertiserUserId.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Calculate order amount based on type
    let orderAmount = 0;
    let description = '';

    if (orderType === 'total' && campaign.totalBudget) {
      orderAmount = campaign.totalBudget;
      description = `Total budget payment for campaign: ${campaign.name}`;
    } else {
      // Calculate daily budget amount
      const daysDiff = Math.ceil((campaign.endDate - campaign.startDate) / (1000 * 60 * 60 * 24));
      orderAmount = campaign.dailyBudget * Math.min(daysDiff, 30); // Cap at 30 days
      description = `Daily budget payment for campaign: ${campaign.name}`;
    }

    // Validate minimum amount
    if (orderAmount < 100) {
      return res.status(400).json({ error: 'Order amount must be at least ₹100' });
    }

    // Create invoice record
    const invoice = new Invoice({
      campaignId,
      orderId: `order_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      amountINR: orderAmount,
      description,
      dueDate: new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours from now
    });

    await invoice.save();

    // Create Razorpay order (this would integrate with Razorpay API)
    const razorpayOrder = {
      id: invoice.orderId,
      amount: Math.round(orderAmount * 100), // Convert to paise
      currency: 'INR',
      receipt: invoice.invoiceNumber,
      notes: {
        campaignId: campaignId,
        campaignName: campaign.name,
        orderType: orderType
      }
    };

    res.json({
      message: 'Order created successfully',
      order: razorpayOrder,
      invoice: {
        id: invoice._id,
        invoiceNumber: invoice.invoiceNumber,
        amount: invoice.amountINR,
        status: invoice.status
      }
    });

  } catch (error) {
    console.error('Order creation error:', error);
    res.status(500).json({ error: 'Failed to create order' });
  }
});

// POST /billing/verify-payment - Verify Razorpay payment
router.post('/verify-payment', async (req, res) => {
  try {
    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature
    } = req.body;

    // Verify signature
    const expectedSignature = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest('hex');

    if (expectedSignature !== razorpay_signature) {
      return res.status(400).json({ error: 'Invalid payment signature' });
    }

    // Find invoice by order ID
    const invoice = await Invoice.findOne({ orderId: razorpay_order_id });
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    // Update invoice status
    invoice.status = 'paid';
    invoice.razorpayPaymentId = razorpay_payment_id;
    invoice.razorpaySignature = razorpay_signature;
    invoice.paymentDate = new Date();
    invoice.paymentMethod = 'razorpay';

    await invoice.save();

    res.json({
      message: 'Payment verified successfully',
      invoice: {
        id: invoice._id,
        status: invoice.status,
        paymentId: invoice.razorpayPaymentId
      }
    });

  } catch (error) {
    console.error('Payment verification error:', error);
    res.status(500).json({ error: 'Failed to verify payment' });
  }
});

// GET /billing/invoices - Get user's invoices
router.get('/invoices', async (req, res) => {
  try {
    const { status, page = 1, limit = 10 } = req.query;
    const skip = (page - 1) * limit;

    let query = {};
    
    // Get campaigns by user
    const userCampaigns = await AdCampaign.find({ 
      advertiserUserId: req.user.id 
    }).select('_id');
    
    const campaignIds = userCampaigns.map(c => c._id);
    query.campaignId = { $in: campaignIds };

    if (status) {
      query.status = status;
    }

    const invoices = await Invoice.find(query)
      .populate('campaignId', 'name')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    const total = await Invoice.countDocuments(query);

    res.json({
      invoices,
      pagination: {
        currentPage: parseInt(page),
        totalPages: Math.ceil(total / limit),
        total,
        hasMore: (page * limit) < total
      }
    });

  } catch (error) {
    console.error('Invoice fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch invoices' });
  }
});

// GET /billing/invoices/:id - Get invoice details
router.get('/invoices/:id', async (req, res) => {
  try {
    const invoiceId = req.params.id;

    const invoice = await Invoice.findById(invoiceId)
      .populate('campaignId', 'name dailyBudget totalBudget');

    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    // Check if user owns this invoice
    const campaign = await AdCampaign.findById(invoice.campaignId._id);
    if (campaign.advertiserUserId.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
    }

    res.json({ invoice });

  } catch (error) {
    console.error('Invoice fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch invoice' });
  }
});

// POST /billing/refund - Request refund
router.post('/refund', async (req, res) => {
  try {
    const { invoiceId, reason } = req.body;

    const invoice = await Invoice.findById(invoiceId);
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    // Check if user owns this invoice
    const campaign = await AdCampaign.findById(invoice.campaignId);
    if (campaign.advertiserUserId.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Check if invoice is paid
    if (invoice.status !== 'paid') {
      return res.status(400).json({ error: 'Only paid invoices can be refunded' });
    }

    // Process refund (this would integrate with Razorpay API)
    // For now, just update the status
    invoice.status = 'refunded';
    invoice.refundAmount = invoice.amountINR;
    invoice.refundReason = reason;
    invoice.refundDate = new Date();

    await invoice.save();

    res.json({
      message: 'Refund processed successfully',
      invoice: {
        id: invoice._id,
        status: invoice.status,
        refundAmount: invoice.refundAmount
      }
    });

  } catch (error) {
    console.error('Refund error:', error);
    res.status(500).json({ error: 'Failed to process refund' });
  }
});

export default router;
