'use strict';

/**
 * New Relic agent configuration.
 *
 * See lib/config/default.js in the agent distribution for a full list of
 * configuration variables and their default values.
 */
exports.config = {
  /**
   * Array of application names.
   */
  app_name: ['Snehayog Backend'],
  /**
   * Your New Relic license key.
   * This is provided via environment variable.
   */
  license_key: process.env.NEW_RELIC_LICENSE_KEY,
  /**
   * This setting controls the agent's log level.
   */
  logging: {
    level: 'trace'
  },
  /**
   * When true, all request headers except for those listed in attributes.exclude
   * will be sent to New Relic for all transactions.
   */
  allow_all_headers: true,
  attributes: {
    /**
     * Prefix of attributes to exclude from all destinations.
     */
    exclude: [
      'request.headers.cookie',
      'request.headers.authorization',
      'request.headers.proxyAuthorization',
      'request.headers.setCookie*',
      'request.headers.x*',
      'response.headers.cookie',
      'response.headers.authorization',
      'response.headers.proxyAuthorization',
      'response.headers.setCookie*',
      'response.headers.x*'
    ]
  }
};
