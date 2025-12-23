## Yug Tab – High Level Flow (Vayu)

Ye doc sirf Yug tab (long‑form feed) ka **logical map** hai, taaki tumko samajh aaye app ka flow kaise work karta hai.

---

## 1. Entry Point – App se Yug tab tak

### 1.1 `main.dart`
- App start:
  - `main()` → `runApp(MyApp)` / similar root widget.
- Root widget:
  - Bottom navigation / tab bar banata hai.
  - Yug tab ke liye `VideoFeedAdvanced` screen use hota hai:
    - `VideoFeedAdvanced(videoType: 'yog')`

### 1.2 `VideoFeedAdvanced`
- File: `video_feed_advanced.dart`
- Ye ek **StatefulWidget** hai jo multiple parts me split hai:
  - `video_feed_advanced_state_fields.dart` → saare fields, controllers, flags.
  - `video_feed_advanced_initialization.dart` → `initState` + services setup.
  - `video_feed_advanced_data.dart` → API calls, pagination, ranking.
  - `video_feed_advanced_preload.dart` → preload, autoplay, scroll auto‑advance.
  - `video_feed_advanced_ui.dart` → PageView UI, overlay, ads, etc.

**Yad rakho:** Yug tab = `VideoFeedAdvanced` (`videoType = 'yog'`).

---

## 2. Data Flow – Videos kaise load hote hain?

### 2.1 Initialization
File: `video_feed_advanced_initialization.dart`

- `initState()` me:
  - `_initializeServices()` call hota hai.
  - Uske andar:
    - `VideoService`, `AuthService`, `VideoViewTracker`, `SmartCacheManager`, `VideoControllerManager`, etc. init hote hain.
    - Phir `_loadVideos(page: 1, append: false)` call hota hai.

### 2.2 `_loadVideos` (cache + API)
File: `video_feed_advanced_data.dart`

- Signature:
  - `Future<void> _loadVideos({int page = 1, bool append = false, bool useCache = true})`
- Kaam:
  1. Agar `page == 1` aur `useCache == true`:
     - `SmartCacheManager` se first page ke videos cache se lene ki koshish karta hai (instant load).
  2. Fir hamesha background me fresh data ke liye:
     - `_loadVideosFromAPI(page: page, append: append)`

### 2.3 `_loadVideosFromAPI`
- Backend se real data fetch karta hai:

```dart
final response = await _videoService.getVideos(
  page: page,
  limit: _videosPerPage,  // Yug tab me default 20
  videoType: widget.videoType, // 'yog'
);
```

- Response me aata hai:
  - `videos` (List<VideoModel>)
  - `hasMore` (bool)
  - `total`, `page` (info)

- Ye response ko:
  - `_rankVideosWithEngagement` + `_filterAndRankNewVideos` se process karta hai.
  - `setState` se `_videos`, `_currentPage`, `_hasMore` update karta hai.
  - Preload + autoplay trigger karta hai (`_preloadVideo`, `_tryAutoplayCurrent`).

### 2.4 `VideoService.getVideos`
File: `services/video_service.dart`

- URL banata hai:

```dart
String url = '$baseUrl/api/videos?page=$page&limit=$limit';
if (videoType == 'yog' || videoType == 'vayu') {
  url += '&videoType=$videoType';
}
```

- HLS / CDN URL normalize karta hai.
- JSON ko `VideoModel` me convert karke return karta hai:

```dart
return {
  'videos': List<VideoModel>.from(videos),
  'hasMore': responseData['hasMore'] ?? false,
  'total': responseData['total'] ?? videos.length,
  'currentPage': responseData['page'] ?? page,
};
```

---

## 3. Backend Feed – Saare yog videos ka LRU loop

File: `backend/routes/videoRoutes.js` (route: `GET /api/videos`)

### 3.1 Identities
- `userIdentifier = userId || deviceId`
  - `userId` = Google ID (authenticated).
  - `deviceId` = anonymous device identifier.

### 3.2 Base filter (yog videos)

```js
const baseQueryFilter = {
  uploader: { $exists: true, $ne: null },
  processingStatus: { $ne: 'failed' },
  $or: [
    { videoUrl: { $exists: true, $ne: null, $ne: '' } },
    { hlsMasterPlaylistUrl: { $exists: true, $ne: null, $ne: '' } },
    { hlsPlaylistUrl: { $exists: true, $ne: null, $ne: '' } },
  ],
  videoType: 'yog' // jab query me videoType=yog aata hai
};
```

### 3.3 Personalized LRU logic (jab `userIdentifier` hai)
High‑level:
- `WatchHistory` se `lastWatchedAt` map nikalta hai:
  - `videoId -> oldest lastWatchedAt`.
- `Video.find(baseQueryFilter)` se saare yog videos nikalta hai.
- Har video ke saath `_lastWatchedAt` attach karta hai:
  - `null` => kabhi nahi dekha.
- Sort:
  - Pehle sab `null` (never watched).
  - Fir watched videos `lastWatchedAt` ascending (least‑recently‑watched first).
- Pagination:
  - `skip = (page-1)*limit`, `pagedVideos = videosWithHistory.slice(skip, skip+limit)`.
  - `hasMore = skip + pagedVideos.length < totalVideosForUser`.

**Effect:**  
Yug tab me:
- Pehle sab **never‑watched** yog videos aaenge.
- Jab sab dekh liye jayenge, tab feed hamesha **sabse purane watched video** se phir se start karega (in a loop).

---

## 4. UI Flow – PageView + scrolling

File: `video_feed_advanced_ui.dart`

### 4.1 PageView

```dart
Widget _buildVideoFeed() {
  return RefreshIndicator(
    onRefresh: refreshVideos,
    child: PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      physics: const ClampingScrollPhysics(),
      onPageChanged: _onPageChanged,
      itemCount: _getTotalItemCount(),
      itemBuilder: (context, index) => _buildFeedItem(index),
    ),
  );
}
```

### 4.2 Item count + end‑of‑feed item
- `_getTotalItemCount()`:
  - Hamesha `videos.length + 1` return karta hai (ek extra “end” item).
- `_buildFeedItem(index)`:
  - Agar `index < _videos.length` → normal video item.
  - Agar `index == _videos.length` → **end‑of‑feed item**:
    - Agar `_hasMore` → `_loadMoreVideos()` call karta hai (loading indicator).
    - Agar `_hasMore == false` → `startOver()` call karke feed restart karta hai.

Isse scroll kabhi “block” nahi hota – hamesha ek extra item hota hai jo ya to **next page load** karta hai ya **feed restart** karta hai.

---

## 5. Scroll + Autoplay – Page change & auto‑advance

File: `video_feed_advanced_preload.dart`

### 5.1 Manual scroll
- `PageView.onPageChanged` → `_onPageChanged(int index)`:
  - Debounce ke baad `_handlePageChangeDebounced(index)` call.
- `_handlePageChangeDebounced`:
  - Purane video ke view tracking ko stop karta hai.
  - Saare controllers pause karta hai.
  - `_currentIndex = index` set karta hai.
  - Memory cleanup + `_reprimeWindowIfNeeded()` call.

### 5.2 Auto‑advance jab video khatam ho
- `_attachEndListenerIfNeeded` har controller pe ek listener lagata hai.
- `handleVideoEnd()` jab completion detect karta hai, tab:
  - `_handleVideoCompleted(index)` call.

```dart
void _handleVideoCompleted(int index) {
  if (_userPaused[index] == true) return;
  if (_autoAdvancedForIndex.contains(index)) return;
  _autoAdvancedForIndex.add(index);

  if (index < _videos.length) {
    final video = _videos[index];
    _viewTracker.stopViewTracking(video.id);

    // Track completion for watch history
    final controller = _controllerPool[index];
    if (controller != null && controller.value.isInitialized) {
      final duration = controller.value.duration.inSeconds;
      _viewTracker.trackVideoCompletion(video.id, duration: duration);
    }
  }

  _resetControllerForReplay(index);

  if (_autoScrollEnabled) {
    _queueAutoAdvance(index); // scroll to next page
  } else {
    _autoAdvancedForIndex.remove(index);
  }
}
```

- `_queueAutoAdvance`:
  - `_pageController.animateToPage(nextIndex)` call karta hai.
  - Animation complete hone par `_isAnimatingPage` reset hota hai.

---

## 6. Watch History – Frontend + Backend

### 6.1 Frontend – `VideoViewTracker`
File: `services/video_view_tracker.dart`

3 main kaam:
1. **startViewTracking(videoId)**:
   - 2 sec ke baad `incrementView(videoId)` call karta hai.
2. **incrementView(videoId)**:
   - `/api/videos/:id/watch` ko `completed: false` ke saath call karta hai.
   - Auth + deviceId dono support karta hai.
3. **trackVideoCompletion(videoId)**:
   - `/api/videos/:id/watch` ko `completed: true` ke saath call karta hai.
   - Ab yeh bhi **deviceId + optional token** use karta hai.

### 6.2 Backend – `/api/videos/:id/watch`
File: `videoRoutes.js`

- Identity:
  - `identityId = userId (googleId) || deviceId`
- `WatchHistory.trackWatch(identityId, videoId, { duration, completed })`
- `views` count update karta hai.
- Redis cache clear karta hai taaki feed fresh ho.

Is watch history ko personalized `/api/videos` LRU feed use karta hai (section 3.3).

---

## 7. Kaise padhoge / seekhoge (recommended order)

1. **Start**: `main.dart` → kaise `VideoFeedAdvanced` tak aata hai.
2. **Screen skeleton**: `video_feed_advanced.dart` (sirf parts & `initState` / `build` dekhna).
3. **Data load**:
   - `video_feed_advanced_data.dart` → `_loadVideos`, `_loadVideosFromAPI`, `_loadMoreVideos`.
   - `services/video_service.dart` → `getVideos`.
4. **Backend feed**:
   - `routes/videoRoutes.js` → `GET /api/videos` LRU logic.
5. **UI behaviour**:
   - `video_feed_advanced_ui.dart` → `PageView`, `_getTotalItemCount`, `_buildFeedItem`.
6. **Autoplay + preloading**:
   - `video_feed_advanced_preload.dart` → `_preloadVideo`, `_handleVideoCompleted`, `_queueAutoAdvance`.
7. **Watch history**:
   - `video_view_tracker.dart` → `startViewTracking`, `incrementView`, `trackVideoCompletion`.
   - `/api/videos/:id/watch` route.

Agar tum is order me daily thoda‑thoda padhoge aur chhote notes banao, to dheere‑dheere pura Yug tab ka logic clear ho jayega.  

