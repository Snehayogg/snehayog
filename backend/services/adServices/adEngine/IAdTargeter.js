/**
 * **IAdTargeter**
 * Abstract base class defining the contract for pluggable targeting rules in Vayu.
 * Every concrete targeter (like GeographicTargeter, ContextualTargeter) must extend this class.
 */
export class IAdTargeter {
  constructor() {
    if (this.constructor === IAdTargeter) {
      throw new Error("IAdTargeter is an abstract class and cannot be instantiated directly.");
    }
  }

  /**
   * Evaluate a candidate ad creative against video/user context.
   * @param {Object} ad AdCreative candidate document (populated with campaignId)
   * @param {Object} context Video/User context (e.g., categories, interests, age, location)
   * @returns {Object} An object containing { scoreModifier: number, reason: string }
   */
  evaluate(ad, context) {
    throw new Error("Method 'evaluate()' must be implemented by concrete subclass.");
  }
}
