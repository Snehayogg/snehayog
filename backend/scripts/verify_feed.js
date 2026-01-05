
import http from 'http';

const PORTS = [5001, 5000, 3000, 8000, 8080];
const PATH = '/api/videos';

function getJson(port, query) {
    return new Promise((resolve, reject) => {
        const url = `http://localhost:${port}${PATH}${query}`;
        http.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        reject(new Error(`Failed to parse JSON from ${url}: ${e.message}`));
                    }
                } else {
                    console.log(`⚠️ Status ${res.statusCode} from ${url}`);
                    console.log(`Body: ${data}`); // Print body to see error details
                    // Resolve with empty/error object so we can try next port if probing
                    reject(new Error(`HTTP ${res.statusCode}`));
                }
            });
        }).on('error', (err) => reject(err));
    });
}

async function findActivePort() {
    for (const port of PORTS) {
        try {
            await getJson(port, '?limit=1');
            console.log(`✅ Found active server on port ${port}`);
            return port;
        } catch (e) {
            // Ignore
        }
    }
    return null;
}

async function runTest() {
    const port = await findActivePort();
    if (!port) {
        console.error('❌ Could not find active server on ports:', PORTS);
        return;
    }

    const BASE_URL = `http://localhost:${port}${PATH}`;
    const TEST_USER_ID = `test_user_${Date.now()}`; // Random platformId
    console.log(`🤖 STARTING VERIFICATION for User: ${TEST_USER_ID}`);
    console.log(`📡 URL: ${BASE_URL}`);

    try {
        // 1. Fetch Batch 1
        console.log('\n--- BATCH 1 ---');
        const batch1 = await getJson(port, `?platformId=${TEST_USER_ID}&limit=5&page=1`);
        console.log(`Received ${batch1.videos?.length} videos`);
        const batch1Ids = batch1.videos?.map(v => v._id) || [];
        console.log('IDs:', batch1Ids);

        if (batch1Ids.length === 0) {
            console.error('❌ Failed to fetch initial videos. DB might be empty?');
            return;
        }

        // 2. Fetch Batch 2 (Refresh app logic)
        console.log('\n--- BATCH 2 (Simulating Refresh) ---');
        // Wait for async background recording
        await new Promise(r => setTimeout(r, 2000));

        const batch2 = await getJson(port, `?platformId=${TEST_USER_ID}&limit=5&page=1`);
        console.log(`Received ${batch2.videos?.length} videos`);
        const batch2Ids = batch2.videos?.map(v => v._id) || [];
        console.log('IDs:', batch2Ids);

        // 3. Verification: Intersection?
        const intersection = batch1Ids.filter(id => batch2Ids.includes(id));

        if (intersection.length === 0) {
            console.log('\n✅ SUCCESS: Batch 2 is completely different from Batch 1!');
            console.log('   (FeedHistory logic filtered out previously seen videos)');
        } else {
            console.error(`\n❌ FAILURE: Found ${intersection.length} duplicates!`);
            console.error('   Duplicates:', intersection);
            console.log('   (FeedHistory logic might be failing)');
        }

    } catch (error) {
        console.error('❌ Test failed with error:', error.message);
    }
}

runTest();
