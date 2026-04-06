import SibApiV3Sdk from 'sib-api-v3-sdk';

/**
 * Brevo (Sendinblue) Email Service
 */
class BrevoService {
  constructor() {
    this.defaultClient = SibApiV3Sdk.ApiClient.instance;
    this.apiKey = this.defaultClient.authentications['api-key'];
    this.apiKey.apiKey = process.env.BREVO_API_KEY;

    this.apiInstance = new SibApiV3Sdk.TransactionalEmailsApi();
    this.senderEmail = process.env.BREVO_SENDER_EMAIL || 'support@snehayog.site';
    this.senderName = process.env.BREVO_SENDER_NAME || 'Vayug';
  }

  /**
   * Send a transactional email
   * @param {Object} options - Email options
   * @param {string} options.to - Recipient email
   * @param {string} options.subject - Email subject
   * @param {string} options.htmlContent - HTML content
   * @param {string} [options.textContent] - Optional plain text content
   * @param {Object} [options.params] - Optional dynamic parameters for templates
   * @returns {Promise}
   */
  async sendEmail({ to, subject, htmlContent, textContent, params }) {
    try {
      const sendSmtpEmail = new SibApiV3Sdk.SendSmtpEmail();

      sendSmtpEmail.subject = subject;
      sendSmtpEmail.htmlContent = htmlContent;
      if (textContent) sendSmtpEmail.textContent = textContent;
      
      sendSmtpEmail.sender = { 
        name: this.senderName, 
        email: this.senderEmail 
      };
      
      sendSmtpEmail.to = [{ email: to }];
      
      if (params) {
        sendSmtpEmail.params = params;
      }

      const data = await this.apiInstance.sendTransacEmail(sendSmtpEmail);
      console.log('✅ Brevo: Email sent successfully. MessageId:', data.messageId);
      return { success: true, messageId: data.messageId };
    } catch (error) {
      console.error('❌ Brevo: Error sending email:', error.response ? error.response.body : error.message);
      return { success: false, error: error.message };
    }
  }

  /**
   * Send a welcome email to a new user
   * @param {string} to - Recipient email
   * @param {string} userName - Name of the user
   */
  async sendWelcomeEmail(to, userName) {
    const subject = `Welcome to Vayug, ${userName}!`;
    const htmlContent = `
      <h1>Welcome to Vayug!</h1>
      <p>Hi ${userName},</p>
      <p>We're thrilled to have you join our community. Explore the videos with no Intruppted ads, World's first Ad free Video Streaming Platform.</p>
      <br>
      <p>Best regards,</p>
      <p>The Vayug Team</p>
    `;
    
    return this.sendEmail({ to, subject, htmlContent });
  }
}

// Export as singleton
export default new BrevoService();
