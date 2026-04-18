import crypto from 'crypto';

/**
 * Middleware to generate or extract a Trace ID for distributed tracing.
 */
export const traceMiddleware = (req, res, next) => {
  // Extract from header or generate new one
  const traceId = req.headers['x-trace-id'] || req.headers['x-request-id'] || crypto.randomUUID();
  
  // Attach to request object
  req.traceId = traceId;
  
  // Set in response header for observability
  res.setHeader('X-Trace-ID', traceId);
  
  next();
};

/**
 * Utility to log with Trace ID
 */
export const logger = {
  info: (traceId, message, data = {}) => {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      level: 'INFO',
      traceId,
      message,
      ...data
    }));
  },
  error: (traceId, message, error = {}, data = {}) => {
    console.error(JSON.stringify({
      timestamp: new Date().toISOString(),
      level: 'ERROR',
      traceId,
      message,
      error: error.message || error,
      stack: error.stack,
      ...data
    }));
  },
  warn: (traceId, message, data = {}) => {
    console.warn(JSON.stringify({
      timestamp: new Date().toISOString(),
      level: 'WARN',
      traceId,
      message,
      ...data
    }));
  }
};
