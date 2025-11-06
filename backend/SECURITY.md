# Payment Data Security Implementation

## Overview

This document describes the security measures implemented for storing sensitive payment data in the Vayug application.

## 🔒 Encryption

### Field-Level Encryption

All sensitive payment data is encrypted at the field level using `mongoose-field-encryption` plugin.

**Encrypted Fields in User Model:**
- `paymentDetails.bankAccount.accountNumber` - Bank account numbers
- `paymentDetails.bankAccount.ifscCode` - IFSC codes
- `paymentDetails.internationalBank.accountNumber` - International bank account numbers
- `paymentDetails.internationalBank.swiftCode` - SWIFT codes
- `paymentDetails.internationalBank.routingNumber` - Routing numbers
- `taxInfo.panNumber` - PAN numbers (sensitive PII)

**Encrypted Fields in CreatorPayout Model:**
- All payment details fields
- PAN and GST numbers

### Configuration

Encryption uses AES-256 encryption with the following configuration:

```javascript
{
  secret: process.env.ENCRYPTION_SECRET_KEY, // 32+ character key
  saltGenerator: () => process.env.ENCRYPTION_SALT
}
```

### Environment Variables Required

Add these to your `.env` file:

```bash
# Encryption Secret Key (32+ characters recommended)
# Generate using: openssl rand -base64 32
ENCRYPTION_SECRET_KEY=your-32-character-encryption-secret-key-here

# Encryption Salt (optional, for additional security)
ENCRYPTION_SALT=snehayog-payment-salt-2024
```

**⚠️ Important:**
- Never commit encryption keys to version control
- Use different keys for development and production
- Store keys securely (use environment variables or secret management services)
- If you lose the encryption key, encrypted data cannot be recovered

### Generating Encryption Keys

**Using OpenSSL:**
```bash
openssl rand -base64 32
```

**Using Node.js:**
```javascript
require('crypto').randomBytes(32).toString('base64')
```

## 📋 Audit Logging

All access to sensitive payment data is logged for security and compliance.

### Logged Events

1. **Payment Profile Views** - When users view their payment profile
2. **Payment Profile Updates** - When payment details are updated
3. **Payout Processing** - When payouts are initiated or processed

### Audit Log Format

```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "userId": "user123",
  "action": "view",
  "resource": "paymentProfile",
  "targetUserId": "user123",
  "metadata": {
    "ipAddress": "192.168.1.1",
    "userAgent": "Mozilla/5.0..."
  },
  "severity": "info"
}
```

### Production Recommendations

In production, send audit logs to:
- **CloudWatch Logs** (AWS)
- **DataDog** (SaaS logging)
- **MongoDB audit collection**
- **SIEM systems** (Security Information and Event Management)

## 🔐 Access Control

### Resource Ownership Verification

Users can only access their own payment data. Access control middleware ensures:

1. Authentication required for all payment endpoints
2. Users cannot access other users' payment data
3. Proper error messages for unauthorized access

### Data Masking

Sensitive data is automatically masked in API responses when:
- User is viewing another user's data (admin scenarios)
- Data is logged (last 4 digits only)
- Data is displayed in audit logs

**Masking Examples:**
- Account Number: `****1234`
- IFSC Code: `SB****`
- PAN Number: `AB****12`
- UPI ID: `abc***@paytm`

## 📊 What's Stored and Why

### ✅ Safe to Store

1. **UPI ID** (e.g., `username@paytm`)
   - Relatively safe (public identifier)
   - Encrypted for defense in depth
   - Used for instant payouts

2. **Bank Account Details** (Encrypted)
   - Account Number
   - IFSC Code
   - Bank Name
   - Account Holder Name
   - Required for bank transfers
   - Fully encrypted at rest

### ❌ Never Store

1. **Card Details** (CVV, full card number)
   - ❌ Already removed from codebase
   - ✅ Use payment gateways (Razorpay/Stripe) instead

2. **Passwords**
   - Not applicable (using Google OAuth)

3. **Unencrypted Sensitive Data**
   - All sensitive fields are encrypted

## 🚀 Best Practices

### Development

1. Use test encryption keys
2. Monitor audit logs in development
3. Test access control thoroughly

### Production

1. ✅ Use strong encryption keys (32+ characters)
2. ✅ Store keys in secure environment variables
3. ✅ Enable HTTPS/TLS for all communications
4. ✅ Monitor audit logs regularly
5. ✅ Implement rate limiting on payment endpoints
6. ✅ Regular security audits
7. ✅ Keep dependencies updated
8. ✅ Use secrets management service (AWS Secrets Manager, etc.)

## 🔄 Migration from Unencrypted Data

If you have existing unencrypted data:

1. **Backup database first**
2. The encryption plugin will encrypt data on next save
3. To migrate all existing data:

```javascript
// Migration script (run once)
const User = require('./models/User');
const users = await User.find({});

for (const user of users) {
  if (user.paymentDetails?.bankAccount?.accountNumber) {
    await user.save(); // Triggers encryption
  }
}
```

## 📝 Compliance

### PCI DSS

- ✅ No card data stored (using payment gateways)
- ✅ Sensitive data encrypted
- ✅ Access control implemented
- ✅ Audit logging enabled

### Data Protection

- ✅ Encryption at rest
- ✅ Encryption in transit (HTTPS)
- ✅ Access controls
- ✅ Audit trails

## 🔍 Monitoring

### Key Metrics to Monitor

1. Failed access attempts
2. Unusual access patterns
3. Multiple profile updates
4. Large payout requests
5. Audit log size

### Alerts to Set Up

1. Multiple failed authentication attempts
2. Unauthorized access attempts
3. Payment profile updates from new IPs
4. Large volume of audit logs

## 📚 References

- [mongoose-field-encryption Documentation](https://github.com/wheresvic/mongoose-field-encryption)
- [PCI DSS Requirements](https://www.pcisecuritystandards.org/)
- [OWASP Data Protection](https://owasp.org/www-project-data-security-top-10/)

## 🆘 Support

If you need to:
- Rotate encryption keys
- Recover encrypted data
- Debug encryption issues

Contact: [Your Security Team]

---

**Last Updated:** 2024-01-15
**Version:** 1.0.0
