import { IAdTargeter } from '../IAdTargeter.js';

/**
 * **DemographicTargeter**
 * Pluggable targeter that filters and scores ads based on platform, device type, and location matches.
 */
export class DemographicTargeter extends IAdTargeter {
  /**
   * Evaluate demographic and geographic matching
   * @param {Object} ad Ad creative with populated campaignId
   * @param {Object} context Context parameters (e.g. location, platform)
   * @returns {Object} { scoreModifier: number, reason: string }
   */
  evaluate(ad, context = {}) {
    const campaign = ad.campaignId || {};
    const target = campaign.target || {};
    let scoreModifier = 0;
    const matchReasons = [];

    // 1. Location Matching
    const userLocation = context.location;
    const targetLocations = target.locations || [];
    if (userLocation && targetLocations.length > 0) {
      const match = targetLocations.some(
        loc => loc && loc.toLowerCase().trim() === userLocation.toLowerCase().trim()
      );
      if (match) {
        scoreModifier += 30;
        matchReasons.push(`location_match:${userLocation}`);
      } else {
        // Penalize if campaign targeted specific locations and user location does not match
        scoreModifier -= 50;
      }
    }

    // 2. Platform / Device Matching
    const userPlatform = context.platform; // e.g. 'android', 'ios', 'web'
    const targetPlatforms = target.platforms || [];
    if (userPlatform && targetPlatforms.length > 0) {
      const match = targetPlatforms.some(
        p => p && p.toLowerCase().trim() === userPlatform.toLowerCase().trim()
      );
      if (match) {
        scoreModifier += 10;
      } else {
        // Penalize if platform mismatch
        scoreModifier -= 30;
      }
    }

    return {
      scoreModifier,
      reason: matchReasons.length > 0 ? matchReasons.join(', ') : 'demographics_default'
    };
  }
}
