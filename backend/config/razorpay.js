// Razorpay Configuration - Using centralized config
import { config } from './config.js';

export const razorpayConfig = {
  keyId: config.razorpay.keyId,
  keySecret: config.razorpay.keySecret,
  webhookSecret: config.razorpay.webhookSecret,
};

export const getRazorpayConfig = () => {
  // Configuration is already validated in config.js
  console.log('✅ Razorpay configuration loaded successfully');
  console.log('🔍 Key ID:', config.razorpay.keyId.substring(0, 10) + '...');
  console.log('🔍 Environment:', config.razorpay.environment);
  
  return razorpayConfig;
};
