/**
 * Access Control Middleware
 * Ensures users can only access/modify their own payment data
 */

/**
 * Middleware to verify user owns the resource
 * Checks if the authenticated user matches the requested user ID
 */
export function verifyResourceOwnership(req, res, next) {
  try {
    const authenticatedUserId = req.user?.id || req.user?.googleId;
    
    if (!authenticatedUserId) {
      return res.status(401).json({ 
        error: 'Authentication required' 
      });
    }

    // Extract user ID from params or body
    const requestedUserId = req.params.userId || req.body.userId || req.query.userId;
    
    // If no specific user ID requested, allow (user accessing their own data via token)
    if (!requestedUserId) {
      return next();
    }

    // Verify ownership
    if (authenticatedUserId !== requestedUserId && 
        authenticatedUserId !== req.params.id &&
        authenticatedUserId !== req.body.id) {
      console.warn('⚠️ Access denied: User', authenticatedUserId, 'attempted to access resource for', requestedUserId);
      return res.status(403).json({ 
        error: 'Access denied: You can only access your own data' 
      });
    }

    next();
  } catch (error) {
    console.error('❌ Access control error:', error);
    return res.status(500).json({ 
      error: 'Access control verification failed' 
    });
  }
}

/**
 * Middleware to mask sensitive payment data in responses
 * Only shows masked values for non-owner requests
 */
export function maskSensitiveData(req, res, next) {
  const originalJson = res.json.bind(res);
  
  res.json = function(data) {
    const authenticatedUserId = req.user?.id || req.user?.googleId;
    const requestedUserId = req.params.userId || req.params.id || req.body.userId;
    
    // If user is accessing their own data, don't mask
    if (authenticatedUserId === requestedUserId || !requestedUserId) {
      return originalJson(data);
    }

    // Mask sensitive fields for other users
    if (data && typeof data === 'object') {
      const masked = maskPaymentData(data);
      return originalJson(masked);
    }

    return originalJson(data);
  };

  next();
}

/**
 * Mask sensitive payment data
 */
function maskPaymentData(obj) {
  if (!obj || typeof obj !== 'object') {
    return obj;
  }

  if (Array.isArray(obj)) {
    return obj.map(item => maskPaymentData(item));
  }

  const masked = { ...obj };

  // Mask account numbers (show last 4 digits)
  if (masked.accountNumber) {
    const acc = String(masked.accountNumber);
    masked.accountNumber = acc.length > 4 
      ? `****${acc.slice(-4)}` 
      : '****';
  }

  // Mask IFSC codes (show only first 2 characters)
  if (masked.ifscCode) {
    const ifsc = String(masked.ifscCode);
    masked.ifscCode = ifsc.length > 2 
      ? `${ifsc.slice(0, 2)}****` 
      : '****';
  }

  // Mask PAN numbers (show only first 2 and last 2)
  if (masked.panNumber) {
    const pan = String(masked.panNumber);
    masked.panNumber = pan.length > 4 
      ? `${pan.slice(0, 2)}****${pan.slice(-2)}` 
      : '****';
  }

  // Mask UPI IDs (show only username part)
  if (masked.upiId) {
    const upi = String(masked.upiId);
    const atIndex = upi.indexOf('@');
    masked.upiId = atIndex > 0 
      ? `${upi.slice(0, Math.min(3, atIndex))}***@${upi.slice(atIndex + 1)}` 
      : '***';
  }

  // Recursively mask nested objects
  if (masked.paymentDetails) {
    masked.paymentDetails = maskPaymentData(masked.paymentDetails);
  }

  if (masked.bankAccount) {
    masked.bankAccount = maskPaymentData(masked.bankAccount);
  }

  if (masked.taxInfo) {
    masked.taxInfo = maskPaymentData(masked.taxInfo);
  }

  return masked;
}

/**
 * Middleware to ensure only admins can access admin endpoints
 */
export function requireAdmin(req, res, next) {
  try {
    // TODO: Implement admin role checking
    // For now, you can add an isAdmin field to User model
    const user = req.user;
    
    if (!user || !user.isAdmin) {
      return res.status(403).json({ 
        error: 'Admin access required' 
      });
    }

    next();
  } catch (error) {
    console.error('❌ Admin check error:', error);
    return res.status(500).json({ 
      error: 'Admin verification failed' 
    });
  }
}
