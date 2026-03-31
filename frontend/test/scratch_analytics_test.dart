import 'package:vayug/features/profile/analytics/domain/models/analytics_models.dart';
import 'dart:convert';

void main() {
  const jsonStr = """
  {
    "core": {
      "totalViews": 100.5,
      "totalShares": 10,
      "totalWatchTime": 45.2,
      "avgWatchDuration": 30.0,
      "skipRate": 0.15,
      "viewsGrowth": 5,
      "watchTimeGrowth": 12.3
    },
    "topVideos": [
      {
        "id": "v1",
        "title": "Video 1",
        "views": 50.0,
        "shares": 2,
        "watchTime": 20.8
      }
    ],
    "dailyPerformance": [
      {
        "date": "2024-03-29",
        "views": 10,
        "watchTime": 5.5
      }
    ],
    "audience": {
      "topLocations": [
        { "name": "IN", "value": 80.0 }
      ],
      "activeTimes": [
        { "hour": 10.0, "count": 5 }
      ],
      "newVsReturning": {
        "new": 70.0,
        "returning": 30
      }
    }
  }
  """;

  try {
    final Map<String, dynamic> data = json.decode(jsonStr);
    final analytics = CreatorAnalytics.fromJson(data);
    print("✅ Success: CreatorAnalytics parsed correctly with mixed int/double values");
    print("Core Watch Time: ${analytics.core.totalWatchTime}");
    print("Top Video 1 Watch Time: ${analytics.topVideos[0].watchTime}");
    print("Daily Performance 1 Watch Time: ${analytics.dailyPerformance[0].watchTime}");
  } catch (e) {
    print("❌ Error: Failed to parse CreatorAnalytics: $e");
  }
}
