export const requireAdminDashboardKey = (req, res, next) => {
  const adminKey = process.env.ADMIN_DASHBOARD_KEY;
  const providedKey =
    req.headers['x-admin-key'] || req.query.adminKey || req.query.apiKey;

  if (!adminKey) {
    if (process.env.NODE_ENV !== 'production') {
      console.warn(
        '⚠️ ADMIN_DASHBOARD_KEY is not set. Allowing access because NODE_ENV is not production.'
      );
      return next();
    }

    console.error(
      '❌ ADMIN_DASHBOARD_KEY missing and NODE_ENV=production. Rejecting request.'
    );
    return res
      .status(503)
      .json({ error: 'Admin dashboard access not configured' });
  }

  if (providedKey && providedKey === adminKey) {
    return next();
  }

  return res
    .status(401)
    .json({ error: 'Unauthorized: invalid admin dashboard key' });
};

export default requireAdminDashboardKey;

