/**
 * **IAdSource**
 * Abstract base class defining the contract for pluggable ad sources in Vayu.
 * Every concrete ad source (like BannerAdSource, CarouselAdSource) must extend this class.
 */
export class IAdSource {
  constructor() {
    if (this.constructor === IAdSource) {
      throw new Error("IAdSource is an abstract class and cannot be instantiated directly.");
    }
  }

  /**
   * Fetch active, approved ad creatives of a specific format.
   * @param {Object} context Contextual details (e.g. adType, limit)
   * @returns {Promise<Array<Object>>} Standardized active ad creative objects from this source
   */
  async getActiveAds(context) {
    throw new Error("Method 'getActiveAds()' must be implemented by concrete subclass.");
  }
}
