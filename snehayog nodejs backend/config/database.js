import mongoose from 'mongoose';

class DatabaseManager {
  constructor() {
    this.isConnected = false;
  }

  async connect() {
    try {
      console.log('🔌 Connecting to MongoDB...');
      console.log(`📍 MongoDB URI: ${process.env.MONGO_URI}`);
      
      await mongoose.connect(process.env.MONGO_URI, {
        useNewUrlParser: true,
        useUnifiedTopology: true,
        serverSelectionTimeoutMS: 5000,
        socketTimeoutMS: 45000,
      });
      
      this.isConnected = true;
      console.log("✅ MongoDB connected successfully");
      
      // Handle connection events
      mongoose.connection.on('error', this.handleError.bind(this));
      mongoose.connection.on('disconnected', this.handleDisconnect.bind(this));
      
    } catch (error) {
      console.error('❌ MongoDB connection failed:', error);
      throw error;
    }
  }

  async disconnect() {
    if (this.isConnected) {
      await mongoose.disconnect();
      this.isConnected = false;
      console.log('🔌 MongoDB disconnected');
    }
  }

  handleError(error) {
    console.error('❌ MongoDB connection error:', error);
    this.isConnected = false;
  }

  handleDisconnect() {
    console.log('⚠️ MongoDB disconnected');
    this.isConnected = false;
  }

  getConnectionStatus() {
    return {
      isConnected: this.isConnected,
      readyState: mongoose.connection.readyState
    };
  }
}

export default new DatabaseManager();
