import 'dotenv/config';
import brevoService from '../services/notificationServices/brevoService.js';

/**
 * Script to test Brevo email integration
 * Run with: node backend/scripts/testBrevo.js <recipient_email> <user_name>
 */
const testBrevo = async () => {
  const [,, toEmail, userName] = process.argv;

  if (!toEmail || !userName) {
    console.log('❌ Usage: node backend/scripts/testBrevo.js <recipient_email> <user_name>');
    process.exit(1);
  }

  console.log(`🚀 Sending test welcome email to ${toEmail} (${userName})...`);
  
  try {
    const result = await brevoService.sendWelcomeEmail(toEmail, userName);
    if (result.success) {
      console.log('✅ Test Passed: Email sent successfully.');
    } else {
      console.log('❌ Test Failed:', result.error);
    }
  } catch (error) {
    console.error('❌ Unexpected Error:', error.message);
  }
};

testBrevo();
