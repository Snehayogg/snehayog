// Ensure NODE_ENV is set before any modules are loaded
process.env.NODE_ENV = 'test';

module.exports = {
  // Use node environment for backend tests
  testEnvironment: 'node',
  
  // Projects with "type": "module" in package.json need special handling
  transform: {},
  
  // Inform Jest about the test locations
  testMatch: ['**/tests/**/*.test.js'],
  
  // Reset mocks between tests
  clearMocks: true,
  
  // Timeout for async tests (30s)
  testTimeout: 30000,

  // Ignore node_modules
  testPathIgnorePatterns: ['/node_modules/'],

  // Enforce ESM behavior
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },

  // Setup file for DB connections
  setupFilesAfterEnv: ['./tests/setup.js'],
};
