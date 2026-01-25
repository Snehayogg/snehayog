import crypto from 'crypto';
import fs from 'fs';
import User from '../models/User.js';

/**
 * Calculates video file hash for duplicate detection
 * @param {string} filePath 
 * @returns {Promise<string>}
 */
export async function calculateVideoHash(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);

    stream.on('data', (data) => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', (err) => reject(err));
  });
}

/**
 * Convert likedBy ObjectIds to googleIds for frontend compatibility
 * @param {Array} likedByArray 
 * @returns {Promise<Array>}
 */
export async function convertLikedByToGoogleIds(likedByArray) {
  if (!Array.isArray(likedByArray) || likedByArray.length === 0) {
    return [];
  }

  try {
    // Batch query all users at once for efficiency
    const users = await User.find({
      _id: { $in: likedByArray }
    }).select('googleId').lean();

    // Create a map of ObjectId -> googleId
    const idMap = new Map();
    users.forEach(user => {
      if (user.googleId) {
        idMap.set(user._id.toString(), user.googleId.toString());
      }
    });

    // Convert ObjectIds to googleIds, filter out any that don't have googleId
    return likedByArray
      .map(id => {
        const idStr = id?.toString?.() || String(id);
        return idMap.get(idStr) || null;
      })
      .filter(Boolean); // Remove nulls
  } catch (error) {
    console.error('❌ Error converting likedBy to googleIds:', error);
    // Fallback: return empty array or original IDs as strings
    return likedByArray.map(id => id?.toString?.() || String(id));
  }
}
