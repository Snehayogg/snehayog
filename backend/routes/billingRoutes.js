import express from 'express';
import AdCampaign from '../models/AdCampaign.js';
import Invoice from '../models/Invoice.js';
import crypto from 'crypto';
import Razorpay from 'razorpay';
import { getRazorpayConfig } from '../config/razorpay.js';

const router = express.Router();

// **NEW: Initialize Razorpay with config**
const config = getRazorpayConfig();
const razorpay = new Razorpay({
  key_id: config.keyId,
  key_secret: config.keySecret,
});

// POST /billing/create-order - Create Razorpay order
router.post('/create-order', async (req, res) => {
  try {
    console.log('🔍 Billing: Creating Razorpay order...');
    console.log('🔍 Billing: Request body:', req.body);
    
    const { amount, currency = 'INR', receipt, notes } = req.body;

    // Validate required fields
    if (!amount || amount < 100) {
      return res.status(400).json({ error: 'Amount must be at least ₹100' });
    }

    // **REMOVED: UPI-specific logic - Razorpay handles UPI natively**

    // **NEW: Create actual Razorpay order**
    const razorpayOrder = await razorpay.orders.create({
      amount: Math.round(amount * 100), // Convert to paise
      currency: currency,
      receipt: receipt || `receipt_${Date.now()}`,
      notes: notes || {},
      // **REMOVED: UPI-specific options - Razorpay handles UPI natively**
    });

    console.log('✅ Billing: Razorpay order created:', razorpayOrder.id);

    res.json({
      message: 'Order created successfully',
      order: {
        id: razorpayOrder.id,
        amount: razorpayOrder.amount,
        currency: razorpayOrder.currency,
        receipt: razorpayOrder.receipt,
        notes: razorpayOrder.notes,
        status: razorpayOrder.status,
        // **REMOVED: UPI-specific response - not needed**
      }
    });

  } catch (error) {
    console.error('❌ Billing: Order creation error:', error);
    
    // **NEW: Better error handling for common issues**
    if (error.error && error.error.description) {
      return res.status(400).json({ 
        error: `Razorpay error: ${error.error.description}`,
        details: error.error
      });
    }
    
    if (error.message && error.message.includes('key_id')) {
      return res.status(500).json({ 
        error: 'Payment service configuration error. Please check Razorpay keys.',
        details: 'Invalid or missing Razorpay API keys'
      });
    }
    
    res.status(500).json({ error: 'Failed to create order: ' + error.message });
  }
});

// **REMOVED: Test payment route - not needed in production**

// **NEW: GET /billing/test-url - Debug payment URL generation**
router.get('/test-url', (req, res) => {
  try {
    console.log('🔍 Billing: Testing payment URL generation');
    
    const testParams = {
      'key': 'rzp_test_RBiIx4GqiPJgsc',
      'amount': '500000', // ₹5000 in paise
      'currency': 'INR',
      'name': 'Snehayog Test',
      'description': 'Test payment',
      'order_id': 'order_test123',
      'prefill[email]': 'test@example.com',
      'prefill[contact]': '9999999999',
      'callback_url': 'http://192.168.0.190:5001/api/billing/payment-success',
      'cancel_url': 'http://192.168.0.190:5001/api/billing/payment-cancelled',
    };

    const queryParams = Object.entries(testParams)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join('&');

    const testUrl = `https://checkout.razorpay.com/v1/checkout.html?${queryParams}`;
    
    console.log('🔍 Billing: Test URL generated:', testUrl);
    
    res.json({
      success: true,
      testUrl: testUrl,
      urlLength: testUrl.length,
      params: testParams
    });
    
  } catch (error) {
    console.error('❌ Billing: Test URL generation error:', error);
    res.status(500).json({ error: 'Failed to generate test URL' });
  }
});

// **NEW: GET /billing/payment-success - Handle successful payment**
router.get('/payment-success', (req, res) => {
  try {
    console.log('🔍 Billing: Payment successful - callback received');
    console.log('🔍 Billing: Query parameters:', req.query);
    
    // **NEW: Return a simple HTML page for successful payment**
    const htmlResponse = `
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Payment Successful - Snehayog</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #4CAF50 0%, #45a049 100%);
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: white;
          }
          .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.2);
            max-width: 500px;
          }
          .icon {
            font-size: 64px;
            margin-bottom: 20px;
          }
          h1 {
            margin: 0 0 20px 0;
            font-size: 28px;
          }
          p {
            margin: 0 0 20px 0;
            line-height: 1.6;
            opacity: 0.9;
          }
          .button {
            background: rgba(255, 255, 255, 0.2);
            color: white;
            border: 1px solid rgba(255, 255, 255, 0.3);
            padding: 12px 24px;
            border-radius: 25px;
            text-decoration: none;
            display: inline-block;
            margin: 10px;
            transition: all 0.3s ease;
          }
          .button:hover {
            background: rgba(255, 255, 255, 0.3);
            transform: translateY(-2px);
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="icon">✅</div>
          <h1>Payment Successful!</h1>
          <p>Your payment has been processed successfully. Your ad campaign is now active!</p>
          <p>You will receive a confirmation email shortly.</p>
          <div>
            <a href="snehayog://payment-callback?status=success" class="button">Return to App</a>
            <a href="snehayog://dashboard" class="button">View Campaign</a>
          </div>
        </div>
      </body>
      </html>
    `;
    
    res.setHeader('Content-Type', 'text/html');
    res.send(htmlResponse);
    
  } catch (error) {
    console.error('❌ Billing: Payment success error:', error);
    res.status(500).json({ error: 'Failed to handle payment success' });
  }
});

// **NEW: GET /billing/payment-cancelled - Handle payment cancellation**
router.get('/payment-cancelled', (req, res) => {
  try {
    console.log('🔍 Billing: Payment cancelled by user');
    
    // **NEW: Return a simple HTML page for payment cancellation**
    const htmlResponse = `
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Payment Cancelled - Snehayog</title>
        <style>
          body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: white;
          }
          .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.2);
            max-width: 500px;
          }
          .icon {
            font-size: 64px;
            margin-bottom: 20px;
          }
          h1 {
            margin: 0 0 20px 0;
            font-size: 28px;
          }
          p {
            margin: 0 0 20px 0;
            line-height: 1.6;
            opacity: 0.9;
          }
          .button {
            background: rgba(255, 255, 255, 0.2);
            color: white;
            border: 1px solid rgba(255, 255, 255, 0.3);
            padding: 12px 24px;
            border-radius: 25px;
            text-decoration: none;
            display: inline-block;
            margin: 10px;
            transition: all 0.3s ease;
          }
          .button:hover {
            background: rgba(255, 255, 255, 0.3);
            transform: translateY(-2px);
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="icon">❌</div>
          <h1>Payment Cancelled</h1>
          <p>Your payment was cancelled. Don't worry, your ad campaign is still saved as a draft.</p>
          <p>You can complete the payment later from your dashboard.</p>
          <div>
            <a href="snehayog://payment-callback?status=cancelled" class="button">Return to App</a>
            <a href="snehayog://dashboard" class="button">View Dashboard</a>
          </div>
        </div>
      </body>
      </html>
    `;
    
    res.setHeader('Content-Type', 'text/html');
    res.send(htmlResponse);
    
  } catch (error) {
    console.error('❌ Billing: Payment cancellation error:', error);
    res.status(500).json({ error: 'Failed to handle payment cancellation' });
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

    // Find and update invoice
    const invoice = await Invoice.findOne({ orderId: razorpay_order_id });
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    // Update invoice with payment details
    invoice.status = 'paid';
    invoice.paidAt = new Date();
    invoice.razorpayPaymentId = razorpay_payment_id;
    invoice.razorpaySignature = razorpay_signature;
    invoice.paymentMethod = 'razorpay';

    await invoice.save();

    res.json({
      message: 'Payment verified successfully',
        paymentId: invoice.razorpayPaymentId
    });

  } catch (error) {
    console.error('Payment verification error:', error);
    res.status(500).json({ error: 'Payment verification failed' });
  }
});

// **NEW: POST /billing/webhook - Handle Razorpay webhooks**
router.post('/webhook', async (req, res) => {
  try {
    console.log('🔍 Billing: Webhook received from Razorpay');
    console.log('🔍 Billing: Webhook body:', req.body);

    const {
      event,
      payload,
      created_at
    } = req.body;

    // **NEW: Verify webhook signature**
    const webhookSignature = req.headers['x-razorpay-signature'];
    if (!webhookSignature) {
      console.warn('⚠️ Billing: No webhook signature received');
      return res.status(400).json({ error: 'Missing webhook signature' });
    }

    // Verify webhook signature
    const expectedSignature = crypto
      .createHmac('sha256', process.env.RAZORPAY_WEBHOOK_SECRET)
      .update(JSON.stringify(req.body))
      .digest('hex');

    if (webhookSignature !== expectedSignature) {
      console.warn('⚠️ Billing: Invalid webhook signature');
      return res.status(400).json({ error: 'Invalid webhook signature' });
    }

    console.log('✅ Billing: Webhook signature verified');

    // **NEW: Handle different webhook events**
    switch (event) {
      case 'payment.captured':
        await _handlePaymentCaptured(payload);
        break;
      
      case 'payment.failed':
        await _handlePaymentFailed(payload);
        break;
      
      case 'order.paid':
        await _handleOrderPaid(payload);
        break;
      
      case 'refund.processed':
        await _handleRefundProcessed(payload);
        break;
      
      default:
        console.log('🔍 Billing: Unhandled webhook event:', event);
    }

    // **NEW: Send success response to Razorpay**
    res.json({ status: 'ok' });

  } catch (error) {
    console.error('❌ Billing: Webhook processing error:', error);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

// **NEW: Helper function to handle payment captured**
async function _handlePaymentCaptured(payload) {
  try {
    console.log('🔍 Billing: Processing payment captured event');
    
    const {
      id: paymentId,
      order_id: orderId,
      amount,
      currency,
      status
    } = payload.payment.entity;

    console.log('🔍 Billing: Payment ID:', paymentId);
    console.log('🔍 Billing: Order ID:', orderId);
    console.log('🔍 Billing: Amount:', amount);
    console.log('🔍 Billing: Status:', status);

    // Find invoice by order ID
    const invoice = await Invoice.findOne({ orderId: orderId });
    if (!invoice) {
      console.warn('⚠️ Billing: Invoice not found for order:', orderId);
      return;
    }

    // Update invoice status
    invoice.status = 'paid';
    invoice.paidAt = new Date();
    invoice.razorpayPaymentId = paymentId;
    invoice.paymentMethod = 'razorpay';

    await invoice.save();
    console.log('✅ Billing: Invoice updated successfully');

    // **NEW: Activate ad campaign**
    await _activateAdCampaign(invoice.campaignId);

  } catch (error) {
    console.error('❌ Billing: Error handling payment captured:', error);
  }
}

// **NEW: Helper function to handle payment failed**
async function _handlePaymentFailed(payload) {
  try {
    console.log('🔍 Billing: Processing payment failed event');
    
    const {
      id: paymentId,
      order_id: orderId,
      error_code: errorCode,
      error_description: errorDescription
    } = payload.payment.entity;

    console.log('🔍 Billing: Payment failed - ID:', paymentId);
    console.log('🔍 Billing: Error code:', errorCode);
    console.log('🔍 Billing: Error description:', errorDescription);

    // Find invoice and mark as failed
    const invoice = await Invoice.findOne({ orderId: orderId });
    if (invoice) {
      invoice.status = 'failed';
      invoice.failedAt = new Date();
      invoice.failureReason = errorDescription;
      await invoice.save();
      console.log('✅ Billing: Invoice marked as failed');
    }

  } catch (error) {
    console.error('❌ Billing: Error handling payment failed:', error);
  }
}

// **NEW: Helper function to handle order paid**
async function _handleOrderPaid(payload) {
  try {
    console.log('🔍 Billing: Processing order paid event');
    
    const {
      id: orderId,
      amount,
      currency,
      status
    } = payload.order.entity;

    console.log('🔍 Billing: Order paid - ID:', orderId);
    console.log('🔍 Billing: Amount:', amount);
    console.log('🔍 Billing: Status:', status);

    // Find invoice and update status
    const invoice = await Invoice.findOne({ orderId: orderId });
    if (invoice) {
      invoice.status = 'paid';
      invoice.paidAt = new Date();
      await invoice.save();
      console.log('✅ Billing: Invoice marked as paid');

      // Activate ad campaign
      await _activateAdCampaign(invoice.campaignId);
    }

  } catch (error) {
    console.error('❌ Billing: Error handling order paid:', error);
  }
}

// **NEW: Helper function to handle refund processed**
async function _handleRefundProcessed(payload) {
  try {
    console.log('🔍 Billing: Processing refund processed event');
    
    const {
      id: refundId,
      payment_id: paymentId,
      amount,
      status
    } = payload.refund.entity;

    console.log('🔍 Billing: Refund processed - ID:', refundId);
    console.log('🔍 Billing: Payment ID:', paymentId);
    console.log('🔍 Billing: Amount:', amount);
    console.log('🔍 Billing: Status:', status);

    // Find invoice and update refund status
    const invoice = await Invoice.findOne({ razorpayPaymentId: paymentId });
    if (invoice) {
      invoice.status = 'refunded';
      invoice.refundedAt = new Date();
      invoice.refundAmount = amount / 100; // Convert from paise to rupees
      await invoice.save();
      console.log('✅ Billing: Invoice marked as refunded');
    }

  } catch (error) {
    console.error('❌ Billing: Error handling refund processed:', error);
  }
}

// **NEW: Helper function to activate ad campaign**
async function _activateAdCampaign(campaignId) {
  try {
    console.log('🔍 Billing: Activating ad campaign:', campaignId);

    // Find and activate campaign
    const campaign = await AdCampaign.findById(campaignId);
    if (campaign) {
      campaign.status = 'active';
      campaign.activatedAt = new Date();
      await campaign.save();
      console.log('✅ Billing: Campaign activated successfully');

      // **NEW: Send notification to user (implement as needed)**
      // await sendCampaignActivatedNotification(campaign.advertiserUserId);
    } else {
      console.warn('⚠️ Billing: Campaign not found:', campaignId);
    }

  } catch (error) {
    console.error('❌ Billing: Error activating campaign:', error);
  }
}

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

// **REMOVED: Test page route - not needed in production**

export default router;
