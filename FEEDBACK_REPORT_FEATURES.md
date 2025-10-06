# Feedback and Report Features

This document describes the professional feedback and report features that have been added to the Snehayog application.

## Overview

The feedback and report system provides users with a comprehensive way to:
- Submit feedback about the app and their experience
- Report inappropriate content or behavior
- Track the status of their submissions
- Help improve the platform

## Backend Implementation

### Models

#### Feedback Model (`/backend/models/Feedback.js`)
- **User Information**: Links to the user who submitted the feedback
- **Type**: bug_report, feature_request, general_feedback, user_experience, content_issue
- **Category**: video_playback, upload_issues, ui_ux, performance, monetization, social_features, other
- **Content**: title, description, rating (1-5 stars)
- **Metadata**: priority, status, device info, screenshots, tags
- **Admin Fields**: admin notes, assigned moderator, resolution

#### Report Model (`/backend/models/Report.js`)
- **Reporter Information**: User who submitted the report
- **Reported Content**: User, video, or comment being reported
- **Report Details**: type, reason, description, evidence
- **Moderation**: priority, severity, status, assigned moderator
- **Actions**: moderator notes, action taken, resolution

### Services

#### Feedback Service (`/backend/services/feedbackService.js`)
- Create, read, update feedback
- Search and filter functionality
- Statistics and analytics
- User feedback history

#### Report Service (`/backend/services/reportService.js`)
- Create, read, update reports
- Moderation workflow management
- Related reports detection
- Escalation handling

### Controllers

#### Feedback Controller (`/backend/controllers/feedbackController.js`)
- RESTful API endpoints
- Input validation
- Error handling
- Authentication and authorization

#### Report Controller (`/backend/controllers/reportController.js`)
- Report submission and management
- Moderator actions
- Admin functions
- Security checks

### Routes

#### Feedback Routes (`/backend/routes/feedbackRoutes.js`)
```
POST   /api/feedback              - Create feedback
GET    /api/feedback              - List feedback (admin)
GET    /api/feedback/:id          - Get feedback by ID
PATCH  /api/feedback/:id/status   - Update status (admin)
GET    /api/feedback/stats/overview - Get statistics (admin)
GET    /api/feedback/user/:userId - Get user's feedback
GET    /api/feedback/search       - Search feedback
DELETE /api/feedback/:id          - Delete feedback (admin)
```

#### Report Routes (`/backend/routes/reportRoutes.js`)
```
POST   /api/reports               - Create report
GET    /api/reports               - List reports (admin/moderator)
GET    /api/reports/:id           - Get report by ID
PATCH  /api/reports/:id/status    - Update status (admin/moderator)
PATCH  /api/reports/:id/assign    - Assign to moderator (admin)
PATCH  /api/reports/:id/escalate  - Escalate report (admin/moderator)
GET    /api/reports/stats/overview - Get statistics (admin/moderator)
GET    /api/reports/user/:userId  - Get user's reports
GET    /api/reports/video/:videoId - Get video reports (admin/moderator)
DELETE /api/reports/:id           - Delete report (admin)
```

## Frontend Implementation

### Models

#### Feedback Model (`/frontend/lib/model/feedback_model.dart`)
- Complete data model with helper methods
- Display name formatting
- Status and priority indicators
- Device information handling

#### Report Model (`/frontend/lib/model/report_model.dart`)
- Comprehensive report data structure
- Evidence management
- Status tracking
- Content identification

### Services

#### Feedback Service (`/frontend/lib/services/feedback_service.dart`)
- API communication
- Error handling
- Data transformation
- Authentication headers

#### Report Service (`/frontend/lib/services/report_service.dart`)
- Report submission
- Status updates
- Evidence management
- Moderator actions

### UI Components

#### Feedback Form Widget (`/frontend/lib/view/widget/feedback/feedback_form_widget.dart`)
- Professional form design
- Type and category selection
- Star rating system
- Device information collection
- Tag selection
- Screenshot support (future)

#### Report Form Widget (`/frontend/lib/view/widget/report/report_form_widget.dart`)
- Report type selection
- Evidence attachment
- Content identification
- Privacy information

#### Feedback Screen (`/frontend/lib/view/screens/feedback_screen.dart`)
- User's feedback history
- Status tracking
- Visual feedback indicators
- Pull-to-refresh functionality

#### Reports Screen (`/frontend/lib/view/screens/reports_screen.dart`)
- User's report history
- Action taken tracking
- Evidence viewing
- Report information

#### Settings Screen (`/frontend/lib/view/screens/settings_screen.dart`)
- Centralized access to feedback and reports
- Help and FAQ information
- Contact support options
- App information

#### Profile Actions Widget (`/frontend/lib/view/widget/profile/feedback_report_actions_widget.dart`)
- Quick access from profile
- Visual action cards
- Integrated navigation

## Usage Instructions

### For Users

1. **Submitting Feedback**:
   - Go to Settings → Submit Feedback
   - Select feedback type (bug report, feature request, etc.)
   - Choose appropriate category
   - Provide title and detailed description
   - Rate your experience (1-5 stars)
   - Add relevant tags
   - Submit

2. **Reporting Content**:
   - Use the report button on any content
   - Select report type (spam, harassment, etc.)
   - Provide reason and description
   - Add evidence if available
   - Submit report

3. **Viewing Submissions**:
   - Go to Settings → My Feedback or My Reports
   - View status of your submissions
   - See any responses from the team

### For Administrators

1. **Managing Feedback**:
   - Access admin panel (future implementation)
   - Review and respond to feedback
   - Update status and priority
   - Assign to team members
   - Generate reports and analytics

2. **Moderating Reports**:
   - Review reported content
   - Take appropriate actions
   - Communicate with users
   - Track resolution status

## Features

### Feedback Features
- ✅ Multiple feedback types and categories
- ✅ Star rating system
- ✅ Device information collection
- ✅ Tag-based organization
- ✅ Status tracking
- ✅ Admin response system
- ✅ Search and filter functionality
- ✅ Statistics and analytics

### Report Features
- ✅ Comprehensive report types
- ✅ Evidence attachment
- ✅ Priority and severity levels
- ✅ Moderation workflow
- ✅ Action tracking
- ✅ Escalation system
- ✅ Related reports detection
- ✅ Repeat report prevention

### Security Features
- ✅ Authentication required
- ✅ Input validation
- ✅ Rate limiting (future)
- ✅ Spam prevention
- ✅ Privacy protection
- ✅ Admin authorization

## Integration

To integrate these features into your existing app:

1. **Add to Profile Screen**:
   ```dart
   import 'package:snehayog/view/widget/profile/feedback_report_actions_widget.dart';
   
   // Add this widget to your profile screen
   const FeedbackReportActionsWidget(),
   ```

2. **Add to Navigation**:
   ```dart
   // Add settings screen to your navigation
   Navigator.push(context, MaterialPageRoute(
     builder: (context) => const SettingsScreen(),
   ));
   ```

3. **Add Report Buttons**:
   ```dart
   // Add report button to video or user cards
   IconButton(
     icon: const Icon(Icons.report),
     onPressed: () => Navigator.push(context, MaterialPageRoute(
       builder: (context) => ReportFormWidget(
         reportedVideoId: videoId,
         reportedVideoTitle: videoTitle,
       ),
     )),
   ),
   ```

## Future Enhancements

- [ ] Admin dashboard for managing feedback and reports
- [ ] Email notifications for status updates
- [ ] Advanced analytics and reporting
- [ ] Bulk actions for moderators
- [ ] Integration with external moderation tools
- [ ] Automated response system
- [ ] Mobile app push notifications
- [ ] Advanced search and filtering
- [ ] Export functionality
- [ ] API rate limiting and abuse prevention

## Dependencies

### Backend
- express-validator (validation)
- mongoose (database)
- jsonwebtoken (authentication)

### Frontend
- device_info_plus (device information)
- package_info_plus (app version)
- http (API communication)
- shared_preferences (local storage)

## Testing

The system includes comprehensive error handling and validation:

1. **Input Validation**: All forms validate required fields and data formats
2. **Error Handling**: Graceful error messages and fallback states
3. **Network Handling**: Offline support and retry mechanisms
4. **Security**: Authentication checks and authorization validation

## Support

For technical support or questions about implementing these features:
- Check the inline code documentation
- Review the API endpoints and request/response formats
- Test with the provided example implementations
- Contact the development team for integration assistance
