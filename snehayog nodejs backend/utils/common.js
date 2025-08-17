// Common utility functions

/**
 * Generate a unique order ID
 * @returns {string} Unique order ID
 */
export const generateOrderId = () => {
  return `ORDER_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
};

/**
 * Calculate estimated impressions based on budget and CPM
 * @param {number} budget - Budget in INR
 * @param {number} cpm - Cost per mille (per 1000 impressions)
 * @returns {number} Estimated impressions
 */
export const calculateEstimatedImpressions = (budget, cpm = 30) => {
  return Math.floor((budget / cpm) * 1000);
};

/**
 * Calculate revenue share for creator and platform
 * @param {number} totalAmount - Total amount in INR
 * @param {number} creatorShare - Creator share percentage (default: 0.80)
 * @returns {Object} Revenue split
 */
export const calculateRevenueSplit = (totalAmount, creatorShare = 0.80) => {
  const creatorRevenue = totalAmount * creatorShare;
  const platformRevenue = totalAmount * (1 - creatorShare);
  
  return {
    creatorRevenue: Math.round(creatorRevenue * 100) / 100,
    platformRevenue: Math.round(platformRevenue * 100) / 100
  };
};

/**
 * Format currency amount
 * @param {number} amount - Amount to format
 * @param {string} currency - Currency code (default: 'INR')
 * @returns {string} Formatted currency string
 */
export const formatCurrency = (amount, currency = 'INR') => {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2
  }).format(amount);
};

/**
 * Calculate CTR (Click Through Rate)
 * @param {number} clicks - Number of clicks
 * @param {number} impressions - Number of impressions
 * @returns {number} CTR percentage
 */
export const calculateCTR = (clicks, impressions) => {
  if (impressions === 0) return 0;
  return (clicks / impressions) * 100;
};

/**
 * Calculate spend based on impressions and CPM
 * @param {number} impressions - Number of impressions
 * @param {number} cpm - Cost per mille
 * @returns {number} Total spend
 */
export const calculateSpend = (impressions, cpm) => {
  return (impressions / 1000) * cpm;
};

/**
 * Validate date range
 * @param {Date|string} startDate - Start date
 * @param {Date|string} endDate - End date
 * @returns {boolean} True if valid
 */
export const validateDateRange = (startDate, endDate) => {
  const start = new Date(startDate);
  const end = new Date(endDate);
  
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return false;
  }
  
  return start < end;
};

/**
 * Generate pagination info
 * @param {number} page - Current page
 * @param {number} limit - Items per page
 * @param {number} total - Total items
 * @returns {Object} Pagination info
 */
export const generatePaginationInfo = (page, limit, total) => {
  return {
    currentPage: page,
    totalPages: Math.ceil(total / limit),
    total,
    hasMore: (page * limit) < total,
    hasPrevious: page > 1,
    nextPage: (page * limit) < total ? page + 1 : null,
    previousPage: page > 1 ? page - 1 : null
  };
};

/**
 * Sanitize object by removing undefined and null values
 * @param {Object} obj - Object to sanitize
 * @returns {Object} Sanitized object
 */
export const sanitizeObject = (obj) => {
  const sanitized = {};
  
  for (const [key, value] of Object.entries(obj)) {
    if (value !== undefined && value !== null) {
      sanitized[key] = value;
    }
  }
  
  return sanitized;
};

/**
 * Generate random string
 * @param {number} length - Length of string
 * @returns {string} Random string
 */
export const generateRandomString = (length = 8) => {
  return Math.random().toString(36).substring(2, length + 2);
};
