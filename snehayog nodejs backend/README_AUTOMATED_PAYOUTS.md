# 🚀 Snehayog Automated Creator Payout System

## 📋 Overview

The **Automated Creator Payout System** automatically transfers 80% of ad revenue to creators on the 1st of every month. Creators set up their payment details once, and the system handles everything automatically.

## 🎯 Key Features

### ✅ **Fully Automated**
- **Monthly Schedule**: Runs on 1st of every month at 9:00 AM IST
- **Batch Processing**: Processes up to 50 payouts simultaneously
- **Error Handling**: Comprehensive error handling and admin notifications
- **No Manual Intervention**: Completely hands-off operation

### 🌍 **Global Support**
- **Multiple Currencies**: INR, USD, EUR, GBP, CAD, AUD
- **Global Payment Methods**: UPI, Bank Transfer, PayPal, Stripe, Wise, Bank Wire
- **Country-Specific**: Different payment methods available per country
- **Tax Compliance**: Support for PAN, GST, W8-BEN, W9 forms

### 💰 **Dynamic Thresholds**
- **First Payout**: No minimum amount (encourages creators)
- **Subsequent Payouts**: Currency-specific minimums
  - INR: ₹200 minimum
  - USD: $5 minimum
  - EUR: €5 minimum
  - GBP: £5 minimum
  - CAD: C$7 minimum
  - AUD: A$7 minimum

## 🏗️ System Architecture

### **Backend Components**

```
📁 Backend/
├── 🤖 automatedPayoutService.js     # Main scheduler & orchestrator
├── 💳 payoutProcessorService.js      # Individual payout processing
├── 📊 CreatorPayout.js              # Payout data model
├── 👤 User.js                       # User payment preferences
├── 🛣️ creatorPayoutRoutes.js        # API endpoints
└── 🖥️ server.js                     # Main server integration
```

### **Frontend Components**

```
📁 Frontend/
├── 💰 creator_payment_setup_screen.dart    # Payment profile setup
├── 📊 creator_payout_dashboard.dart        # Creator payout dashboard
└── 🎨 UI components & navigation
```

### **Admin Dashboard**

```
📁 Admin/
└── 🖥️ admin_dashboard.html              # Real-time monitoring dashboard
```

## 🔄 How It Works

### **1. Creator Setup (One-Time)**
```
Creator → Opens Payment Setup Screen → Enters Payment Details → Saves Profile
```

**Payment Methods Available:**
- **India**: UPI, Bank Transfer, Paytm, PhonePe
- **US/Canada**: PayPal, Stripe, Bank Wire
- **UK/Germany**: PayPal, Stripe, Wise, Bank Wire
- **Australia**: PayPal, Stripe, Bank Wire
- **Other Countries**: PayPal, Stripe, Wise, Payoneer

### **2. Monthly Revenue Calculation**
```
Ad Impressions → Revenue Calculation → 80% Creator Share → Payout Eligibility Check
```

### **3. Automated Payout Process**
```
📅 1st of Month 9:00 AM IST
├── 🔍 Find eligible creators
├── 💳 Validate payment details
├── 🚀 Process payouts in batches
├── 📊 Update status & send notifications
└── 📈 Generate admin reports
```

### **4. Payment Processing**
```
Payout Request → Payment Gateway → Status Update → Creator Notification
```

## 🚀 Getting Started

### **Prerequisites**
- Node.js 16+ 
- MongoDB 5+
- Flutter 3+ (for frontend)

### **1. Install Dependencies**
```bash
cd "snehayog/snehayog nodejs backend"
npm install
```

### **2. Environment Variables**
Create `.env` file:
```env
MONGO_URI=mongodb://localhost:27017/snehayog
JWT_SECRET=your_jwt_secret_here
GOOGLE_CLIENT_ID=your_google_client_id
```

### **3. Start Backend Server**
```bash
npm run dev
```

**Expected Output:**
```
🚀 Server started successfully!
📍 Server running at http://192.168.0.190:3000
🤖 Automated Payouts: Scheduled for 1st of every month
✅ Automated payout service is registered
```

### **4. Test the System**
```bash
node test-automated-payouts.js
```

## 📱 Frontend Integration

### **1. Add Routes**
```dart
// In your main app routes
'/creator-payment-setup': (context) => const CreatorPaymentSetupScreen(),
'/creator-payout-dashboard': (context) => const CreatorPayoutDashboard(),
```

### **2. Navigation**
```dart
// Navigate to payment setup
Navigator.pushNamed(context, '/creator-payment-setup');

// Navigate to payout dashboard
Navigator.pushNamed(context, '/creator-payout-dashboard');
```

## 🛠️ API Endpoints

### **Creator Endpoints**
```
GET  /api/creator-payouts/profile          # Get payout profile
PUT  /api/creator-payouts/payment-method   # Update payment details
POST /api/creator-payouts/monthly          # Create monthly payout record
GET  /api/creator-payouts/monthly          # Get payout history
POST /api/creator-payouts/request          # Request payout
```

### **Admin Endpoints**
```
GET  /api/creator-payouts/stats            # Payout statistics
GET  /api/creator-payouts/overview         # System overview
GET  /api/creator-payouts/recent           # Recent payouts
```

## 📊 Admin Dashboard

### **Access Dashboard**
Open `admin/admin_dashboard.html` in your browser or serve it from your backend.

### **Features**
- **Real-time Stats**: Total, successful, pending, failed payouts
- **System Overview**: Creator count, eligible payouts, total amount
- **Recent Payouts**: Latest 20 payout transactions
- **System Controls**: Start/stop scheduler, refresh data
- **Auto-refresh**: Updates every 30 seconds

## 🔧 Configuration

### **Payout Schedule**
```javascript
// In automatedPayoutService.js
cron.schedule('0 9 1 * *', async () => {
  // Monthly payout on 1st at 9:00 AM IST
}, { timezone: 'Asia/Kolkata' });

cron.schedule('0 9 * * *', async () => {
  // Daily check at 9:00 AM IST
}, { timezone: 'Asia/Kolkata' });
```

### **Batch Processing**
```javascript
const batchSize = 50;  // Process 50 payouts at once
const batchDelay = 2000; // 2 second delay between batches
```

### **Payment Method Validation**
```javascript
const countryPaymentMethods = {
  'IN': ['upi', 'bank_transfer', 'paytm', 'phonepe'],
  'US': ['paypal', 'stripe', 'bank_wire'],
  // ... more countries
};
```

## 📈 Monitoring & Logs

### **Server Logs**
```
🚀 Starting automated payout scheduler...
📅 Monthly payout triggered - 1st of month
💰 Found 25 eligible payouts
📦 Processing batch 1/1 (25 payouts)
✅ Payout successful for creator: John Doe
📊 Batch Results: 23 successful, 1 failed, 1 skipped
```

### **Dashboard Metrics**
- **Total Payouts**: Overall system statistics
- **Success Rate**: Percentage of successful transfers
- **Pending Amount**: Total money waiting to be transferred
- **Next Payout Date**: When the next automated run will occur

## 🚨 Troubleshooting

### **Common Issues**

#### **1. Scheduler Not Starting**
```bash
# Check server logs for:
❌ MongoDB connection failed
# Solution: Ensure MongoDB is running
```

#### **2. No Eligible Payouts**
```bash
# Check if creators have:
✅ Valid payment details
✅ Met minimum threshold
✅ Revenue > 0
```

#### **3. Payment Failures**
```bash
# Common causes:
❌ Invalid payment details
❌ Payment gateway errors
❌ Insufficient funds
```

### **Debug Commands**
```bash
# Test API endpoints
curl http://192.168.0.190:3000/api/creator-payouts/stats

# Check server health
curl http://192.168.0.190:3000/api/health

# View admin dashboard
open admin/admin_dashboard.html
```

## 🔒 Security Features

### **Authentication**
- JWT token-based authentication
- User-specific payout access
- Admin-only monitoring endpoints

### **Data Validation**
- Payment method validation per country
- Currency conversion validation
- Threshold enforcement

### **Audit Trail**
- Complete payout history
- Status change tracking
- Admin action logging

## 📋 Testing

### **1. Test Payment Setup**
```bash
# Start server
npm run dev

# Open frontend app
# Navigate to payment setup screen
# Enter test payment details
# Verify profile is saved
```

### **2. Test Payout Creation**
```bash
# Create test payout record
POST /api/creator-payouts/monthly
{
  "month": "2024-01",
  "impressions": 1000,
  "revenueINR": 500
}
```

### **3. Test Admin Dashboard**
```bash
# Open admin dashboard
# Verify stats are loading
# Check real-time updates
# Test scheduler controls
```

## 🚀 Production Deployment

### **Environment Setup**
```bash
# Production environment variables
NODE_ENV=production
MONGO_URI=mongodb://production-db:27017/snehayog
JWT_SECRET=strong_production_secret
```

### **Monitoring**
- **Log Aggregation**: Use tools like Winston or Bunyan
- **Health Checks**: Implement `/health` endpoint monitoring
- **Alerting**: Set up notifications for payout failures
- **Backup**: Regular MongoDB backups

### **Scaling**
- **Horizontal Scaling**: Multiple server instances
- **Database**: MongoDB replica sets
- **Queue System**: Redis for large payout volumes
- **Load Balancing**: Nginx or similar

## 📚 API Documentation

### **Request Examples**

#### **Setup Payment Profile**
```bash
PUT /api/creator-payouts/payment-method
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "paymentMethod": "upi",
  "paymentDetails": {
    "upiId": "username@upi"
  },
  "currency": "INR",
  "country": "IN",
  "taxInfo": {
    "panNumber": "ABCDE1234F"
  }
}
```

#### **Create Monthly Payout**
```bash
POST /api/creator-payouts/monthly
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "month": "2024-01",
  "impressions": 5000,
  "revenueINR": 2500,
  "currency": "INR",
  "exchangeRate": 1.0
}
```

### **Response Examples**

#### **Payout Profile**
```json
{
  "creator": {
    "id": "user_id",
    "name": "John Doe",
    "email": "john@example.com",
    "country": "IN",
    "currency": "INR",
    "payoutCount": 2
  },
  "paymentMethods": ["upi", "bank_transfer", "paytm", "phonepe"],
  "thresholds": {
    "firstPayout": { "INR": "No minimum" },
    "subsequentPayouts": { "INR": "₹200 minimum" }
  },
  "isFirstPayout": false
}
```

## 🎉 Success Stories

### **Before Implementation**
- ❌ Manual payout processing
- ❌ Creator payment details scattered
- ❌ No threshold enforcement
- ❌ Inconsistent payout timing

### **After Implementation**
- ✅ Fully automated monthly payouts
- ✅ Centralized payment profiles
- ✅ Dynamic threshold enforcement
- ✅ Consistent 1st of month timing
- ✅ 80% revenue share guaranteed
- ✅ Global payment method support

## 🤝 Contributing

### **Adding New Payment Methods**
1. Update `_getAvailablePaymentMethods()` function
2. Add validation in `_buildPaymentMethodFields()`
3. Update payment processing logic
4. Test with different countries

### **Adding New Currencies**
1. Update currency enums in models
2. Add exchange rate logic
3. Update threshold calculations
4. Test currency conversion

## 📞 Support

### **Getting Help**
- **Documentation**: Check this README first
- **Logs**: Review server console output
- **Dashboard**: Use admin dashboard for monitoring
- **Testing**: Run test scripts to verify functionality

### **Reporting Issues**
- **Backend Issues**: Check server logs and MongoDB
- **Frontend Issues**: Verify API connectivity
- **Payment Issues**: Check payment method validation
- **Scheduler Issues**: Verify cron job execution

---

## 🎯 **Ready to Automate Your Creator Payouts?**

Your creators will now automatically receive their 80% ad revenue share on the 1st of every month! 🚀💸✨

**The system is production-ready and handles everything automatically. Just start your server and watch the magic happen!**
