import { IAdTargeter } from '../IAdTargeter.js';
import { calculateCategoryRelevance } from '../../../../config/categoryMap.js';

/**
 * **ContextualTargeter**
 * Pluggable targeter that scores ad relevance based on video categories, tags, keywords, and campaign interests.
 */
export class ContextualTargeter extends IAdTargeter {
  /**
   * Evaluate contextual relevance of an ad candidate
   * @param {Object} ad Ad creative with populated campaignId
   * @param {Object} context Context signals (videoCategory, videoTags, videoKeywords, categories, interests)
   * @returns {Object} { scoreModifier: number, reason: string }
   */
  evaluate(ad, context = {}) {
    const campaign = ad.campaignId || {};
    const campaignInterests = campaign.target?.interests || [];
    
    // If no interests specified, it is a universal ad. We give it a base score modifier.
    if (campaignInterests.length === 0) {
      return { scoreModifier: 50, reason: 'universal_ad' };
    }

    let scoreModifier = 0;
    const matchReasons = [];

    const videoCategory = context.videoCategory || (context.categories && context.categories[0]);
    const videoTags = context.videoTags || [];
    const videoKeywords = context.videoKeywords || context.interests || [];

    // 1. Check interest matching with video category using category mapping
    if (videoCategory) {
      for (const interest of campaignInterests) {
        try {
          const relevance = calculateCategoryRelevance(interest, videoCategory);
          if (relevance && relevance.score > 0) {
            scoreModifier += relevance.score;
            matchReasons.push(`category_${relevance.level}:${interest}(${relevance.score})`);
          }
        } catch (err) {
          // Keep execution safe if categoryMap fails
        }
      }
    }

    // 2. Check interest matching with video tags
    if (videoTags && videoTags.length > 0) {
      for (const interest of campaignInterests) {
        const interestLower = interest.toLowerCase();
        for (const tag of videoTags) {
          if (tag) {
            const tagLower = tag.toLowerCase();
            if (tagLower === interestLower || tagLower.includes(interestLower) || interestLower.includes(tagLower)) {
              scoreModifier += 60;
              matchReasons.push(`tag_match:${tag}`);
            }
          }
        }
      }
    }

    // 3. Check interest matching with video keywords/interests
    if (videoKeywords && videoKeywords.length > 0) {
      for (const interest of campaignInterests) {
        const interestLower = interest.toLowerCase();
        for (const keyword of videoKeywords) {
          if (keyword) {
            const keywordLower = keyword.toLowerCase();
            if (keywordLower === interestLower || keywordLower.includes(interestLower) || interestLower.includes(keywordLower)) {
              scoreModifier += 40;
              matchReasons.push(`keyword_match:${keyword}`);
            }
          }
        }
      }
    }

    return {
      scoreModifier,
      reason: matchReasons.length > 0 ? matchReasons.join(', ') : 'no_context_match'
    };
  }
}
