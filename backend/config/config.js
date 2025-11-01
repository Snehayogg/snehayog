import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// **NEW: Try multiple possible .env file locations**
const possibleEnvPaths = [
  path.join(__dirname, '..', '.env'),           // Backend root
  path.join(process.cwd(), '.env'),             // Current working directory
  path.join(__dirname, '..', '..', '.env'),    // Project root
  '.env'                                        // Relative to current directory
];

let envLoaded = false;
let loadedEnvPath = '';

for (const envPath of possibleEnvPaths) {
  if (fs.existsSync(envPath)) {
    console.log('🔍 Found .env file at:', envPath);
    dotenv.config({ path: envPath });
    envLoaded = true;
    loadedEnvPath = envPath;
    break;
  }
}

if (!envLoaded) {
  console.error('❌ No .env file found in any of these locations:');
  possibleEnvPaths.forEach(path => console.error('   •', path));
  console.error('🔍 Current working directory:', process.cwd());
  console.error('🔍 Config directory:', __dirname);
}

// **NEW: Check if .env file was loaded**
if (!process.env.MONGODB_URI && !process.env.MONGO_URI) {
  console.warn('⚠️  .env file not loaded or MONGODB_URI/MONGO_URI not found');
  if (envLoaded) {
    console.warn('🔍 .env file loaded from:', loadedEnvPath);
    console.warn('🔍 Available environment variables:', Object.keys(process.env).filter(key => 
      key.includes('RAZORPAY') || 
      key.includes('MONGO') || 
      key.includes('JWT') || 
      key.includes('CLOUD')
    ));
  }
}

// Configuration validation
const validateConfig = () => {
  const requiredVars = [
    'RAZORPAY_KEY_ID',
    'RAZORPAY_KEY_SECRET',
    'RAZORPAY_WEBHOOK_SECRET',
    'JWT_SECRET',
    // Check for either MONGODB_URI or MONGO_URI
    process.env.MONGODB_URI ? 'MONGODB_URI' : 'MONGO_URI'
  ];

  const missingVars = requiredVars.filter(varName => {
    if (varName === 'MONGODB_URI' || varName === 'MONGO_URI') {
      return !process.env.MONGODB_URI && !process.env.MONGO_URI;
    }
    return !process.env[varName];
  });
  
  if (missingVars.length > 0) {
    throw new Error(`Missing required environment variables: ${missingVars.join(', ')}`);
  }
};

// Main configuration object
export const config = {
  // Server configuration
  server: {
    port: process.env.PORT || 5001,
    nodeEnv: process.env.NODE_ENV || 'development',
    corsOrigin: process.env.CORS_ORIGIN?.split(',') || ['http://localhost:3000', 'https://snehayog.site'],
  },

  // Database configuration - support both MONGODB_URI and MONGO_URI
  database: {
    uri: process.env.MONGODB_URI || process.env.MONGO_URI,
    options: {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    },
  },

  // Razorpay configuration
  razorpay: {
    keyId: process.env.RAZORPAY_KEY_ID,
    keySecret: process.env.RAZORPAY_KEY_SECRET,
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET,
    environment: process.env.RAZORPAY_KEY_ID?.startsWith('rzp_test_') ? 'test' : 'live',
  },

  // JWT configuration
  jwt: {
    secret: process.env.JWT_SECRET,
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },

  // Google Auth configuration
  google: {
    clientId: process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
  },

  // Cloudinary configuration - support both naming conventions
  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME || process.env.CLOUD_NAME,
    apiKey: process.env.CLOUDINARY_API_KEY || process.env.CLOUD_KEY,
    apiSecret: process.env.CLOUDINARY_API_SECRET || process.env.CLOUD_SECRET,
  },

  // Feature flags
  features: {
    enablePayments: process.env.ENABLE_PAYMENTS === 'true',
    enableAnalytics: process.env.ENABLE_ANALYTICS === 'true',
    enableNotifications: process.env.ENABLE_NOTIFICATIONS === 'true',
    enableUPIPayments: process.env.ENABLE_UPI_PAYMENTS === 'true',
  },

  // Security configuration
  security: {
    rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 900000,
    rateLimitMaxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100,
    sessionTimeoutMs: parseInt(process.env.SESSION_TIMEOUT_MS) || 3600000,
  },

  // Logging configuration
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    enableDebug: process.env.DEBUG === 'true',
    enableTestEndpoints: process.env.ENABLE_TEST_ENDPOINTS === 'true',
  },
};

// Validate configuration on import
try {
  validateConfig();
  console.log('✅ Configuration loaded successfully');
  console.log(`🔍 Environment: ${config.server.nodeEnv}`);
  console.log(`🔍 Razorpay: ${config.razorpay.environment}`);
  console.log(`🔍 Server Port: ${config.server.port}`);
  console.log(`🔍 Database URI: ${config.database.uri ? 'SET' : 'MISSING'}`);
} catch (error) {
  console.error('❌ Configuration validation failed:', error.message);
  console.error('📝 Please check your .env file and ensure all required variables are set');
  process.exit(1);
}

export default config;
