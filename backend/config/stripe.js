// Minimal Stripe config to avoid crashes when Stripe is not used
// Returns empty values when no Stripe configuration is provided

export const getStripeConfig = () => {
  return {
    // Keep empty by default so Stripe code paths are effectively disabled
    secretKey: process.env.STRIPE_SECRET_KEY || '',
    webhookSecret: process.env.STRIPE_WEBHOOK_SECRET || '',
  };
};


