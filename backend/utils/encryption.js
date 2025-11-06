import dotenv from 'dotenv';

dotenv.config();

/**
 * Encryption configuration for sensitive payment data
 * Uses mongoose-field-encryption plugin
 */
export const encryptionConfig = {
  // Secret key for encryption (must be 32 characters for AES-256)
  // Generate a strong key: openssl rand -base64 32
  secret: process.env.ENCRYPTION_SECRET_KEY || process.env.JWT_SECRET || 'default-secret-key-32-characters!!',
  
  // Salt generator - use unique salt per field for better security
  saltGenerator: () => {
    // Use a fixed salt from env or generate one
    return process.env.ENCRYPTION_SALT || 'snehayog-payment-salt-2024';
  }
};

/**
 * Fields that should be encrypted in User model
 */
export const encryptedUserFields = [
  'paymentDetails.bankAccount.accountNumber',
  'paymentDetails.bankAccount.ifscCode',
  'paymentDetails.internationalBank.accountNumber',
  'paymentDetails.internationalBank.swiftCode',
  'paymentDetails.internationalBank.routingNumber',
  'taxInfo.panNumber', // PAN is sensitive PII
  // Note: UPI ID is less sensitive but can be encrypted for defense in depth
  // 'paymentDetails.upiId', // Optional - uncomment if you want to encrypt UPI IDs
];

/**
 * Fields that should be encrypted in CreatorPayout model
 */
export const encryptedPayoutFields = [
  'paymentDetails.bankAccount.accountNumber',
  'paymentDetails.bankAccount.ifscCode',
  'paymentDetails.internationalBank.accountNumber',
  'paymentDetails.internationalBank.swiftCode',
  'paymentDetails.internationalBank.routingNumber',
  'panNumber',
  'gstNumber', // GST can contain sensitive business info
];

/**
 * Validate encryption configuration
 */
export function validateEncryptionConfig() {
  if (!process.env.ENCRYPTION_SECRET_KEY) {
    console.warn('⚠️  WARNING: ENCRYPTION_SECRET_KEY not set in environment variables.');
    console.warn('⚠️  Using JWT_SECRET as fallback. This is not recommended for production.');
    console.warn('⚠️  Please set ENCRYPTION_SECRET_KEY in your .env file.');
  }
  
  if (encryptionConfig.secret.length < 32) {
    console.warn('⚠️  WARNING: Encryption secret is too short. Minimum 32 characters recommended.');
  }
}

// Validate on import
validateEncryptionConfig();
