# Snehayog Backend - Refactored Architecture

## 🏗️ Project Structure

```
snehayog nodejs backend/
├── config/                 # Configuration files
│   ├── database.js        # Database connection management
│   ├── upload.js          # File upload configuration
│   └── cloudinary.js      # Cloudinary configuration
├── constants/              # Application constants
│   └── index.js           # Centralized constants
├── controllers/            # Business logic controllers (legacy)
├── middleware/             # Express middleware
│   ├── errorHandler.js    # Error handling middleware
│   └── validation.js      # Input validation middleware
├── models/                 # Mongoose models
├── routes/                 # API route definitions
│   ├── adRoutes/          # Modular ad routes
│   │   ├── index.js       # Main ad routes index
│   │   ├── campaignRoutes.js
│   │   ├── creativeRoutes.js
│   │   ├── paymentRoutes.js
│   │   └── analyticsRoutes.js
│   ├── authRoutes.js
│   ├── billingRoutes.js
│   ├── creatorPayoutRoutes.js
│   ├── userRoutes.js
│   └── videoRoutes.js
├── services/               # Business logic services
│   ├── adService.js       # Ad-related business logic
│   ├── automatedPayoutService.js
│   └── payoutProcessorService.js
├── utils/                  # Utility functions
│   ├── common.js          # Common helper functions
│   └── verifytoken.js     # JWT verification
├── uploads/                # File uploads
├── server.js              # Main application entry point
└── package.json
```

## 🚀 Key Improvements

### 1. **Modular Architecture**
- **Routes**: Split large route files into focused, single-responsibility modules
- **Services**: Business logic separated from route handlers
- **Middleware**: Centralized validation and error handling

### 2. **Separation of Concerns**
- **Routes**: Handle HTTP requests/responses only
- **Services**: Contain business logic and data operations
- **Models**: Define data structure and validation
- **Middleware**: Handle cross-cutting concerns

### 3. **Error Handling**
- Centralized error handling middleware
- Consistent error response format
- Async error wrapper for automatic error catching

### 4. **Input Validation**
- Centralized validation middleware
- Reusable validation functions
- Consistent error messages

### 5. **Configuration Management**
- Environment-specific configuration
- Centralized constants
- Database connection management

## 📁 File Descriptions

### **Configuration Files**

#### `config/database.js`
- Manages MongoDB connection lifecycle
- Handles connection events and errors
- Provides connection status information

#### `config/upload.js`
- Configures file upload settings
- Handles different file types (ads, videos)
- Manages upload directories

### **Constants**

#### `constants/index.js`
- Application-wide constants
- Configuration values
- Error and success messages
- Business rules (budgets, limits, etc.)

### **Middleware**

#### `middleware/errorHandler.js`
- Centralized error handling
- Consistent error response format
- Development vs production error details

#### `middleware/validation.js`
- Input validation functions
- Reusable validation logic
- Consistent validation error messages

### **Services**

#### `services/adService.js`
- Ad creation and management logic
- Payment processing
- Analytics calculations
- Business rule enforcement

### **Utilities**

#### `utils/common.js`
- Helper functions for common operations
- Currency formatting
- Date validation
- Pagination helpers

## 🔧 Usage Examples

### **Creating a New Route Module**

1. Create a new route file in the appropriate directory:
```javascript
// routes/exampleRoutes.js
import express from 'express';
import { asyncHandler } from '../middleware/errorHandler.js';
import { validateExample } from '../middleware/validation.js';

const router = express.Router();

router.post('/', validateExample, asyncHandler(async (req, res) => {
  // Route logic here
}));

export default router;
```

2. Add it to the main index file:
```javascript
// routes/exampleRoutes/index.js
import exampleRoutes from './exampleRoutes.js';

const router = express.Router();
router.use('/examples', exampleRoutes);
export default router;
```

### **Using the Service Layer**

```javascript
// In a route handler
import exampleService from '../services/exampleService.js';

router.get('/:id', asyncHandler(async (req, res) => {
  const result = await exampleService.getExample(req.params.id);
  res.json(result);
}));
```

### **Adding New Constants**

```javascript
// constants/index.js
export const NEW_CONFIG = {
  KEY: 'value',
  LIMIT: 100
};
```

## 🎯 Best Practices

### **1. Route Organization**
- Keep routes focused on a single resource
- Use descriptive route names
- Group related endpoints together

### **2. Error Handling**
- Always use `asyncHandler` for async routes
- Throw descriptive errors
- Let middleware handle error responses

### **3. Validation**
- Validate input at the route level
- Use centralized validation functions
- Provide clear error messages

### **4. Business Logic**
- Keep routes thin
- Put business logic in services
- Use models for data operations

### **5. File Naming**
- Use descriptive, consistent names
- Follow the established pattern
- Group related functionality

## 🚀 Getting Started

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. **Start the server**:
   ```bash
   npm run dev
   ```

## 📊 Code Quality Metrics

- **File Size**: Most files are now under 100 lines
- **Single Responsibility**: Each file has one clear purpose
- **Dependency Injection**: Services are easily testable
- **Error Handling**: Consistent error responses
- **Validation**: Centralized input validation

## 🔄 Migration Notes

The refactoring maintains backward compatibility:
- All existing API endpoints work the same way
- Database models remain unchanged
- Environment variables are the same
- Only internal structure has been improved

## 🧪 Testing

The modular structure makes testing easier:
- Services can be unit tested independently
- Routes can be tested with mocked services
- Middleware can be tested in isolation

## 📈 Performance Benefits

- **Reduced Memory Usage**: Smaller, focused modules
- **Better Caching**: Modular imports allow better tree-shaking
- **Easier Debugging**: Clear separation of concerns
- **Faster Development**: Easier to locate and modify code

## 🤝 Contributing

When adding new features:
1. Follow the established modular pattern
2. Use the service layer for business logic
3. Add appropriate validation middleware
4. Update constants as needed
5. Document new endpoints

## 📚 Additional Resources

- [Express.js Best Practices](https://expressjs.com/en/advanced/best-practices-performance.html)
- [Node.js Design Patterns](https://nodejs.org/en/docs/guides/nodejs-docker-webapp/)
- [MongoDB Best Practices](https://docs.mongodb.com/manual/core/data-modeling-introduction/)
