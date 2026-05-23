/**
 * Abstract class defining the contract for search providers (FFmpeg Search Codecs).
 * 
 * Any search provider (Mongo, Elasticsearch, mock, etc.) must extend this class
 * and implement these methods.
 */
export class ISearchProvider {
  /**
   * Search for videos.
   * @param {string} query The search query string
   * @param {number} limit Maximum results to return
   * @returns {Promise<Array<Object>>} Normalized list of video objects
   */
  async searchVideos(query, limit) {
    throw new Error('searchVideos() not implemented');
  }

  /**
   * Search for creators/users.
   * @param {string} query The search query string
   * @param {number} limit Maximum results to return
   * @returns {Promise<Array<Object>>} Normalized list of creator/user objects
   */
  async searchCreators(query, limit) {
    throw new Error('searchCreators() not implemented');
  }
}
