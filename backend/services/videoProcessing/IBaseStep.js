/**
 * Base Step for Video Processing Pipeline
 */
class IBaseStep {
  constructor(name) {
    this.name = name;
  }

  /**
   * Execute the step logic
   * @param {Object} context - Shared pipeline context
   * @returns {Promise<void>}
   */
  async execute(context) {
    throw new Error(`execute() must be implemented by ${this.constructor.name}`);
  }

  getName() {
    return this.name;
  }
}

export default IBaseStep;
