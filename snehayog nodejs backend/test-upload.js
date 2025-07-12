const express = require('express');
const multer = require('multer');
const cloudinary = require('./config/cloudinary .js');
const fs = require('fs');
const path = require('path');

// Test script to verify server configuration
async function testConfiguration() {
  console.log('🔍 Testing Snehayog Backend Configuration...\n');

  // 1. Check environment variables
  console.log('1. Environment Variables:');
  const requiredVars = ['CLOUD_NAME', 'CLOUD_KEY', 'CLOUD_SECRET', 'MONGO_URI'];
  const missingVars = [];
  
  requiredVars.forEach(varName => {
    const value = process.env[varName];
    if (value) {
      console.log(`   ✅ ${varName}: ${varName.includes('SECRET') ? '***configured***' : value}`);
    } else {
      console.log(`   ❌ ${varName}: missing`);
      missingVars.push(varName);
    }
  });

  if (missingVars.length > 0) {
    console.log(`\n❌ Missing environment variables: ${missingVars.join(', ')}`);
    console.log('Please set these variables in your .env file');
    return false;
  }

  // 2. Check uploads directory
  console.log('\n2. Uploads Directory:');
  const uploadsDir = path.join(__dirname, 'uploads');
  if (fs.existsSync(uploadsDir)) {
    console.log(`   ✅ Uploads directory exists: ${uploadsDir}`);
  } else {
    console.log(`   ❌ Uploads directory missing: ${uploadsDir}`);
    console.log('   Creating uploads directory...');
    fs.mkdirSync(uploadsDir, { recursive: true });
    console.log('   ✅ Uploads directory created');
  }

  // 3. Test Cloudinary configuration
  console.log('\n3. Cloudinary Configuration:');
  try {
    const result = await cloudinary.api.ping();
    console.log('   ✅ Cloudinary connection successful');
    console.log(`   Response: ${JSON.stringify(result)}`);
  } catch (error) {
    console.log('   ❌ Cloudinary connection failed');
    console.log(`   Error: ${error.message}`);
    return false;
  }

  // 4. Test file upload simulation
  console.log('\n4. File Upload Test:');
  try {
    // Create a test file
    const testFilePath = path.join(uploadsDir, 'test-upload.txt');
    fs.writeFileSync(testFilePath, 'Test upload file');
    
    // Test Cloudinary upload
    const uploadResult = await cloudinary.uploader.upload(testFilePath, {
      resource_type: 'auto',
      folder: 'snehayog-test',
    });
    
    console.log('   ✅ Test upload successful');
    console.log(`   URL: ${uploadResult.secure_url}`);
    
    // Clean up test file
    fs.unlinkSync(testFilePath);
    console.log('   ✅ Test file cleaned up');
    
  } catch (error) {
    console.log('   ❌ Test upload failed');
    console.log(`   Error: ${error.message}`);
    return false;
  }

  console.log('\n✅ All tests passed! Server should be ready for video uploads.');
  return true;
}

// Run the test
testConfiguration()
  .then(success => {
    if (success) {
      console.log('\n🎉 Configuration is correct!');
      process.exit(0);
    } else {
      console.log('\n❌ Configuration has issues. Please fix them before running the server.');
      process.exit(1);
    }
  })
  .catch(error => {
    console.error('\n💥 Test failed with error:', error);
    process.exit(1);
  }); 