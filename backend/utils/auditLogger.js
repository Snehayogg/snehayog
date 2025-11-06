/**
 * Audit Logger for tracking access to sensitive payment data
 * Logs all access to payment details, account numbers, and other PII
 */

/**
 * Log access to payment details
 * @param {Object} params - Audit log parameters
 * @param {string} params.userId - User ID accessing the data
 * @param {string} params.action - Action performed (view, update, delete)
 * @param {string} params.resource - Resource type (paymentDetails, bankAccount, etc.)
 * @param {string} params.targetUserId - Target user ID (if different from accessing user)
 * @param {Object} params.metadata - Additional metadata
 */
export function logPaymentDataAccess({
  userId,
  action,
  resource,
  targetUserId = null,
  metadata = {}
}) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    userId,
    action, // 'view', 'update', 'delete', 'create'
    resource, // 'paymentDetails', 'bankAccount', 'upiId', 'taxInfo'
    targetUserId: targetUserId || userId,
    metadata,
    severity: action === 'view' ? 'info' : 'warning'
  };

  // Log to console (in production, send to logging service like CloudWatch, DataDog, etc.)
  console.log('🔒 [AUDIT] Payment Data Access:', JSON.stringify(logEntry));

  // TODO: In production, send to:
  // - CloudWatch Logs
  // - DataDog
  // - MongoDB audit collection
  // - Security Information and Event Management (SIEM) system

  return logEntry;
}

/**
 * Log payment profile updates
 * @param {Object} params
 */
export function logPaymentProfileUpdate({
  userId,
  fieldsUpdated = [],
  ipAddress = null,
  userAgent = null
}) {
  return logPaymentDataAccess({
    userId,
    action: 'update',
    resource: 'paymentProfile',
    metadata: {
      fieldsUpdated,
      ipAddress,
      userAgent
    }
  });
}

/**
 * Log payment profile views
 * @param {Object} params
 */
export function logPaymentProfileView({
  userId,
  targetUserId = null,
  ipAddress = null,
  userAgent = null
}) {
  return logPaymentDataAccess({
    userId,
    action: 'view',
    resource: 'paymentProfile',
    targetUserId,
    metadata: {
      ipAddress,
      userAgent
    }
  });
}

/**
 * Log payout processing events
 * @param {Object} params
 */
export function logPayoutProcessing({
  userId,
  payoutId,
  amount,
  currency,
  paymentMethod,
  action, // 'initiated', 'completed', 'failed'
  error = null
}) {
  return logPaymentDataAccess({
    userId,
    action,
    resource: 'payout',
    metadata: {
      payoutId,
      amount,
      currency,
      paymentMethod,
      error
    }
  });
}

/**
 * Middleware to automatically log payment data access
 */
export function auditPaymentAccess(req, res, next) {
  // Log when payment profile endpoints are accessed
  if (req.path.includes('/payment') || req.path.includes('/payout')) {
    const userId = req.user?.id || req.user?.googleId || 'anonymous';
    
    logPaymentProfileView({
      userId,
      ipAddress: req.ip || req.headers['x-forwarded-for'] || req.connection.remoteAddress,
      userAgent: req.headers['user-agent']
    });
  }
  
  next();
}
