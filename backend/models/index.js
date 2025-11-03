// Models index file - Import all models to ensure they are registered with Mongoose
// This prevents "MissingSchemaError: Schema hasn't been registered for model" errors

import './User.js';
import './Video.js';
import './Comment.js';
import './Invoice.js';
import './AdCampaign.js';
import './AdCreative.js';
import './AdImpression.js';
import './CreatorPayout.js';
import './Feedback.js';

console.log('✅ All models imported and registered successfully');
