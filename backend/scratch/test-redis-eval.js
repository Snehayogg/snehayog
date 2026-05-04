import '../config/env.js';
import redisService from '../services/caching/redisService.js';

async function testEval() {
    console.log('🧪 Testing Redis EVAL fix...');
    const connected = await redisService.connect();
    if (!connected) {
        console.error('❌ Could not connect to Redis');
        return;
    }

    try {
        const key = 'test:eval:key';
        const script = 'return redis.call("SET", KEYS[1], ARGV[1])';
        
        console.log('📡 Sending EVAL...');
        // Standard EVAL in Redis: EVAL script numkeys key1 key2 arg1 arg2
        // For Upstash .execute: ["EVAL", script, numkeys, key1, key2, arg1, arg2]
        const result = await redisService.call('EVAL', script, 1, key, 'hello-world');
        console.log('✅ EVAL Result:', result);

        const val = await redisService.get(key);
        console.log('✅ GET Result:', val);

        await redisService.del(key);
    } catch (error) {
        console.error('❌ EVAL Test Failed:', error);
    } finally {
        await redisService.disconnect();
    }
}

testEval();
