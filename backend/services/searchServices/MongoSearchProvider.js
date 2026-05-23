import { ISearchProvider } from './ISearchProvider.js';
import Video from '../../models/Video.js';
import User from '../../models/User.js';

/**
 * MongoDB Implementation of ISearchProvider (MongoDB Atlas + Regex Fallbacks).
 */
export default class MongoSearchProvider extends ISearchProvider {
  /**
   * Search for videos using Atlas Compound Search or Regex Fallback.
   * @param {string} query
   * @param {number} limit
   * @returns {Promise<Array>} Normalized videos
   */
  async searchVideos(query, limit) {
    const q = query.trim();
    if (!q) return [];

    console.log(`🔍 MongoSearchProvider: Querying videos for "${q}"`);

    try {
      // Atlas Compound search strategy (Weights: exact=5, fuzzy=2, tags=1)
      const videos = await Video.aggregate([
        {
          $search: {
            index: 'default',
            compound: {
              should: [
                {
                  text: {
                    query: q,
                    path: 'videoName',
                    score: { boost: { value: 5 } }
                  }
                },
                {
                  text: {
                    query: q,
                    path: 'videoName',
                    fuzzy: { maxEdits: 1, prefixLength: 1 },
                    score: { boost: { value: 2 } }
                  }
                },
                {
                  text: {
                    query: q,
                    path: 'tags',
                    score: { boost: { value: 1 } }
                  }
                }
              ],
              minimumShouldMatch: 1
            }
          }
        },
        { $limit: limit },
        {
          $lookup: {
            from: 'users',
            localField: 'uploader',
            foreignField: '_id',
            as: 'uploader'
          }
        },
        { $unwind: '$uploader' },
        {
          $project: {
            score: { $meta: 'searchScore' },
            videoName: 1,
            videoUrl: 1,
            thumbnailUrl: 1,
            uploader: { _id: 1, googleId: 1, name: 1, profilePic: 1 },
            videoType: 1,
            duration: 1,
            uploadedAt: 1,
            views: 1,
            likes: 1,
            category: 1,
            tags: 1,
            videoHash: 1,
            hlsPlaylistUrl: 1,
            hlsMasterPlaylistUrl: 1,
            seriesId: 1,
            episodeNumber: 1
          }
        }
      ]);

      return videos.map(v => ({
        ...v,
        id: v._id.toString()
      }));

    } catch (err) {
      console.error('❌ MongoSearchProvider Atlas Search Error (videos):', err);
      
      // Fallback to basic case-insensitive regex search
      const fallback = await Video.find({
        videoName: { $regex: q, $options: 'i' }
      })
      .limit(limit)
      .populate('uploader', 'googleId name profilePic')
      .sort({ uploadedAt: -1 })
      .lean();

      return fallback.map(v => ({
        ...v,
        id: v._id.toString()
      }));
    }
  }

  /**
   * Search for creators using Atlas Search or Regex Fallback.
   * @param {string} query
   * @param {number} limit
   * @returns {Promise<Array>} Normalized creators
   */
  async searchCreators(query, limit) {
    const q = query.trim();
    if (!q) return [];

    console.log(`🔍 MongoSearchProvider: Querying creators for "${q}"`);

    try {
      let creators = await User.aggregate([
        {
          $search: {
            index: 'default',
            compound: {
              should: [
                {
                  text: {
                    query: q,
                    path: 'name',
                    score: { boost: { value: 3 } }
                  }
                },
                {
                  text: {
                    query: q,
                    path: 'name',
                    fuzzy: { maxEdits: 1 }
                  }
                }
              ]
            }
          }
        },
        { $limit: limit },
        {
          $project: {
            score: { $meta: 'searchScore' },
            _id: 1,
            googleId: 1,
            name: 1,
            profilePic: 1,
            bio: 1,
            followerCount: 1,
            followingCount: 1,
            createdAt: 1
          }
        }
      ]);

      console.log(`📡 MongoSearchProvider Atlas Search (creators): Found ${creators.length} results`);

      // Fallback if Atlas returns nothing
      if (creators.length === 0) {
        console.log('MongoSearchProvider Atlas Search returned 0 creators, attempting regex fallback...');
        creators = await User.find({
          name: { $regex: q, $options: 'i' }
        })
        .limit(limit)
        .lean();
      }

      return creators.map(u => ({
        ...u,
        id: u.googleId || (u._id ? u._id.toString() : ''),
        _id: u._id,
        followersCount: u.followerCount || 0,
        followingCount: u.followingCount || 0,
      }));

    } catch (err) {
      console.error('❌ MongoSearchProvider Search Error (creators):', err);

      try {
        const fallback = await User.find({
          name: { $regex: q, $options: 'i' }
        })
        .limit(limit)
        .lean();

        return fallback.map(u => ({
          ...u,
          id: u.googleId || (u._id ? u._id.toString() : ''),
          followersCount: u.followerCount || 0,
          followingCount: u.followingCount || 0
        }));
      } catch (fallbackErr) {
        console.error('❌ MongoSearchProvider Total Search Failure (creators):', fallbackErr);
        return [];
      }
    }
  }
}
