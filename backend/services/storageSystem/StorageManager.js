import R2StorageProvider from './providers/R2StorageProvider.js';
import LocalStorageProvider from './providers/LocalStorageProvider.js';

/**
 * Storage Manager (The Orchestrator)
 * 
 * Decides which storage provider to use based on environment.
 */
class StorageManager {
  constructor() {
    this.providers = new Map();
    this.defaultProvider = null;
    
    // Initialize standard providers
    this.register('r2', new R2StorageProvider());
    this.register('local', new LocalStorageProvider());

    // Pick default based on environment
    const env = process.env.NODE_ENV || 'development';
    this.defaultProvider = (env === 'production' || process.env.FLY_APP_NAME) 
      ? this.get('r2') 
      : this.get('local');
  }

  register(name, provider) {
    this.providers.set(name, provider);
  }

  get(name) {
    return this.providers.get(name);
  }

  /**
   * Use the default provider
   * @returns {IStorageProvider}
   */
  get active() {
    return this.defaultProvider;
  }
}

// Singleton instance
export default new StorageManager();
