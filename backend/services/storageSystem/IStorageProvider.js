/**
 * FFmpeg-style Storage System: Base Provider Interface
 * 
 * Every storage backend (R2, S3, Local, etc.) must implement this contract.
 */
class IStorageProvider {
  /**
   * Upload a file to storage
   * @param {String} localPath - Path to the local file
   * @param {String} destinationKey - The key/path in the storage
   * @param {String} contentType - MIME type
   * @returns {Promise<Object>} { url, key }
   */
  async upload(localPath, destinationKey, contentType) {
    throw new Error('upload() must be implemented');
  }

  /**
   * Download a file from storage
   * @param {String} key - Storage key
   * @param {String} localPath - Where to save locally
   * @returns {Promise<String>} Local path
   */
  async download(key, localPath) {
    throw new Error('download() must be implemented');
  }

  /**
   * Delete a file from storage
   * @param {String} key - Storage key
   */
  async delete(key) {
    throw new Error('delete() must be implemented');
  }

  /**
   * Get a public URL for a key
   * @param {String} key 
   * @returns {String}
   */
  getPublicUrl(key) {
    throw new Error('getPublicUrl() must be implemented');
  }
}

export default IStorageProvider;
