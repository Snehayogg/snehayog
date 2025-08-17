import CreatorPayout from '../models/CreatorPayout.js';
import User from '../models/User.js';

// **NEW: Process individual payout**
export async function processPayout(payout) {
  try {
    console.log(`💳 Processing payout: ${payout._id} for creator: ${payout.creatorId.name}`);

    // Update status to processing
    payout.status = 'processing';
    await payout.save();

    // Process based on payment method
    const result = await processPaymentByMethod(payout);

    if (result.success) {
      // Update payout status to paid
      payout.status = 'paid';
      payout.paymentDate = new Date();
      payout.paymentReference = result.reference;
      await payout.save();

      // Update creator's payout count
      await User.findByIdAndUpdate(
        payout.creatorId._id,
        { $inc: { payoutCount: 1 } }
      );

      console.log(`✅ Payout processed successfully: ${payout._id}`);
      return { success: true, reference: result.reference };
    } else {
      // Update payout status to failed
      payout.status = 'failed';
      payout.notes = result.error;
      await payout.save();

      console.log(`❌ Payout failed: ${payout._id} - ${result.error}`);
      return { success: false, error: result.error };
    }

  } catch (error) {
    console.error(`❌ Error processing payout ${payout._id}:`, error);
    
    // Update payout status to failed
    payout.status = 'failed';
    payout.notes = error.message;
    await payout.save();

    return { success: false, error: error.message };
  }
}

// **NEW: Process payment based on method**
async function processPaymentByMethod(payout) {
  const user = payout.creatorId;
  const paymentMethod = user.preferredPaymentMethod;

  try {
    switch (paymentMethod) {
      case 'upi':
        return await processUPIPayment(payout, user);
      
      case 'bank_transfer':
        return await processBankTransfer(payout, user);
      
      case 'paypal':
        return await processPayPalPayment(payout, user);
      
      case 'stripe':
        return await processStripePayment(payout, user);
      
      case 'wise':
        return await processWisePayment(payout, user);
      
      default:
        throw new Error(`Unsupported payment method: ${paymentMethod}`);
    }
  } catch (error) {
    console.error(`Error processing ${paymentMethod} payment:`, error);
    return { success: false, error: error.message };
  }
}

// **NEW: Process UPI payment**
async function processUPIPayment(payout, user) {
  try {
    // Here you would integrate with actual UPI payment gateway
    // For now, we'll simulate the process
    
    console.log(`📱 Processing UPI payment to: ${user.paymentDetails.upiId}`);
    
    // Simulate UPI processing delay
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Generate UPI reference
    const reference = `UPI_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    return {
      success: true,
      reference: reference,
      method: 'UPI'
    };
  } catch (error) {
    throw new Error(`UPI payment failed: ${error.message}`);
  }
}

// **NEW: Process bank transfer**
async function processBankTransfer(payout, user) {
  try {
    const bankDetails = user.paymentDetails.bankAccount;
    console.log(`🏦 Processing bank transfer to: ${bankDetails.accountNumber}`);
    
    // Here you would integrate with actual bank transfer API
    // For now, we'll simulate the process
    
    // Simulate bank processing delay
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Generate bank reference
    const reference = `BANK_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    return {
      success: true,
      reference: reference,
      method: 'Bank Transfer'
    };
  } catch (error) {
    throw new Error(`Bank transfer failed: ${error.message}`);
  }
}

// **NEW: Process PayPal payment**
async function processPayPalPayment(payout, user) {
  try {
    console.log(`💳 Processing PayPal payment to: ${user.paymentDetails.paypalEmail}`);
    
    // Here you would integrate with PayPal API
    // For now, we'll simulate the process
    
    // Simulate PayPal processing delay
    await new Promise(resolve => setTimeout(resolve, 1500));
    
    // Generate PayPal reference
    const reference = `PAYPAL_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    return {
      success: true,
      reference: reference,
      method: 'PayPal'
    };
  } catch (error) {
    throw new Error(`PayPal payment failed: ${error.message}`);
  }
}

// **NEW: Process Stripe payment**
async function processStripePayment(payout, user) {
  try {
    console.log(`💳 Processing Stripe payment to: ${user.paymentDetails.stripeAccountId}`);
    
    // Here you would integrate with Stripe Connect API
    // For now, we'll simulate the process
    
    // Simulate Stripe processing delay
    await new Promise(resolve => setTimeout(resolve, 1500));
    
    // Generate Stripe reference
    const reference = `STRIPE_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    return {
      success: true,
      reference: reference,
      method: 'Stripe'
    };
  } catch (error) {
    throw new Error(`Stripe payment failed: ${error.message}`);
  }
}

// **NEW: Process Wise payment**
async function processWisePayment(payout, user) {
  try {
    console.log(`🌍 Processing Wise payment to: ${user.paymentDetails.wiseEmail}`);
    
    // Here you would integrate with Wise API
    // For now, we'll simulate the process
    
    // Simulate Wise processing delay
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    // Generate Wise reference
    const reference = `WISE_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    return {
      success: true,
      reference: reference,
      method: 'Wise'
    };
  } catch (error) {
    throw new Error(`Wise payment failed: ${error.message}`);
  }
}
