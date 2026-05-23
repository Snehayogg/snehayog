import IStorageProvider from '../IStorageProvider.js';
import fs from 'fs';
import path from 'path';

/**
 * Local File System Storage Provider (The "Dev Codec")
 * 
 * Useful for local development and testing without incurring R2 costs.
 */
class LocalStorageProvider extends IStorageProvider {
  constructor(baseDir = 'uploads') {
    super();
    this.baseDir = path.join(process.cwd(), baseDir);
    if (!fs.existsSync(this.baseDir)) {
      fs.mkdirSync(this.baseDir, { recursive: true });
    }
  }

  async upload(localPath, destinationKey, contentType) {
    const fullDestPath = path.join(this.baseDir, destinationKey);
    const destDir = path.dirname(fullDestPath);
    
    if (!fs.existsSync(destDir)) {
      fs.mkdirSync(destDir, { recursive: true });
    }

    fs.copyFileSync(localPath, fullDestPath);
    
    return {
      url: `/uploads/${destinationKey}`, // Mock local URL
      key: destinationKey,
      size: fs.statSync(fullDestPath).size
    };
  }

  async download(key, localPath) {
    const fullSourcePath = path.join(this.baseDir, key);
    if (!fs.existsSync(fullSourcePath)) throw new Error(`File not found: ${key}`);
    
    fs.copyFileSync(fullSourcePath, localPath);
    return localPath;
  }

  async delete(key) {
    const fullPath = path.join(this.baseDir, key);
    if (fs.existsSync(fullPath)) {
      fs.unlinkSync(fullPath);
      return true;
    }
    return false;
  }

  getPublicUrl(key) {
    return `/uploads/${key}`;
  }
}

export default LocalStorageProvider;
