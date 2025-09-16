// Test script to verify URL parsing logic
// Run with: node test-url-parsing.js

// Test URLs from your logs
const testUrls = [
  'https://res.cloudinary.com/dkklingts/video/upload/s--oNvyyP9O--/q_q_auto:good/v1/snehayog-videos/hls/hls_master_1757662454515.m3u8',
  'https://res.cloudinary.com/dkklingts/video/upload/upload',
  'https://res.cloudinary.com/dkklingts/video/upload/v1/snehayog-videos/hls/hls_master_1757662454515.m3u8',
  'https://res.cloudinary.com/dkklingts/video/upload/sp_hd,q_auto:best/v1/snehayog-videos/hls/hls_master_1757662454515.m3u8'
];

function parseCloudinaryUrl(url) {
  console.log(`\n🔍 Testing URL: ${url}`);
  
  try {
    const urlObj = new URL(url);
    const pathSegments = urlObj.pathname.split('/').filter(segment => segment.length > 0);
    
    console.log(`📁 Path segments: ${JSON.stringify(pathSegments)}`);
    
    // Find 'upload' index
    const uploadIdx = pathSegments.indexOf('upload');
    if (uploadIdx === -1) {
      console.log('❌ No upload segment found');
      return null;
    }
    
    console.log(`📍 Upload found at index: ${uploadIdx}`);
    
    // Look for the actual video ID after upload
    let videoId = null;
    let foundUpload = false;
    
    for (let i = 0; i < pathSegments.length; i++) {
      if (pathSegments[i] === 'upload') {
        foundUpload = true;
        console.log(`🔍 Looking for video ID after upload...`);
        
        // Look for the actual video ID after upload
        for (let j = i + 1; j < pathSegments.length; j++) {
          const segment = pathSegments[j];
          console.log(`  📝 Checking segment ${j}: "${segment}"`);
          
          // Skip transformation segments
          if (segment.startsWith('s--') || 
              segment.startsWith('q_') || 
              segment.startsWith('v') ||
              segment.includes('auto') ||
              segment.length < 10) {
            console.log(`    ⏭️ Skipping transformation: "${segment}"`);
            continue;
          }
          
          // Found the video ID
          if (segment.length > 10 && !segment.includes('--') && !segment.includes(':')) {
            videoId = segment.replace(/\.(m3u8|mp4)$/i, '');
            console.log(`    ✅ Found video ID: "${videoId}"`);
            break;
          }
        }
        break;
      }
    }
    
    if (videoId && foundUpload) {
      const directUrl = `https://res.cloudinary.com/dkklingts/video/upload/${videoId}`;
      const basicUrl = `https://res.cloudinary.com/dkklingts/video/upload/q_auto:low,f_auto/${videoId}.m3u8`;
      
      console.log(`✅ Extracted video ID: ${videoId}`);
      console.log(`🔗 Direct URL: ${directUrl}`);
      console.log(`🔗 Basic quality URL: ${basicUrl}`);
      
      return { videoId, directUrl, basicUrl };
    } else {
      console.log('❌ Could not extract video ID');
      return null;
    }
    
  } catch (error) {
    console.log(`❌ Error parsing URL: ${error.message}`);
    return null;
  }
}

// Test all URLs
console.log('🧪 Testing Cloudinary URL parsing logic...\n');

testUrls.forEach((url, index) => {
  console.log(`\n${'='.repeat(80)}`);
  console.log(`TEST ${index + 1}`);
  console.log(`${'='.repeat(80)}`);
  
  const result = parseCloudinaryUrl(url);
  
  if (result) {
    console.log(`\n✅ SUCCESS: Video ID extracted successfully`);
  } else {
    console.log(`\n❌ FAILED: Could not extract video ID`);
  }
});

console.log(`\n${'='.repeat(80)}`);
console.log('🏁 Testing complete!');
console.log(`${'='.repeat(80)}`);
