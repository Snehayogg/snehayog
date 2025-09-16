# Widget Organization

This directory contains all Flutter widgets organized in a clean, logical structure.

## 📁 Directory Structure

### Core Widgets
- `action_buttons_widget.dart` - Action buttons for videos (like, comment, share)
- `ad_display_widget.dart` - Advertisement display components
- `carousel_ad_widget.dart` - Carousel advertisement widget
- `comments_sheet_widget.dart` - Comments bottom sheet
- `external_link_button.dart` - External link button component
- `follow_button_widget.dart` - Follow/unfollow button
- `loading_button.dart` - Loading button with states
- `video_actions_widget.dart` - Video action buttons
- `video_info_widget.dart` - Video information display
- `video_loading_states.dart` - Video loading state components
- `video_ui_components.dart` - Reusable video UI components

### Subdirectories

#### `create_ad/`
Advertisement creation widgets:
- `ad_details_form_widget.dart` - Ad details form
- `ad_type_selector_widget.dart` - Ad type selection
- `campaign_preview_widget.dart` - Campaign preview
- `campaign_settings_widget.dart` - Campaign settings
- `media_uploader_widget.dart` - Media upload component
- `payment_handler_widget.dart` - Payment handling
- `targeting_section_widget.dart` - Targeting options

#### `profile/`
Profile-related widgets:
- `profile_actions_widget.dart` - Profile action buttons
- `profile_error_widget.dart` - Profile error states
- `profile_header_widget.dart` - Profile header component
- `video_selection_widget.dart` - Video selection for profile

#### `video_overlays/`
Video overlay components:
- `video_error_widget.dart` - Video error display
- `video_loading_widget.dart` - Video loading indicator
- `video_play_pause_overlay.dart` - Play/pause overlay
- `video_progress_bar.dart` - Video progress bar
- `video_seeking_indicator.dart` - Seeking indicator

## 🧹 Cleanup History

### Removed Duplicates
- ❌ `lib/view/widgets/` (empty folder)
- ❌ `lib/core/widgets/` (moved to main widget folder)
- ❌ `lib/features/video/presentation/widgets/video_loading_states.dart` (duplicate)
- ❌ `instant_thumbnail_preview_demo.dart` (unused demo file)
- ❌ `video_card_widget.dart` (unused)
- ❌ `video_feed_widget.dart` (unused)
- ❌ `video_item_widget.dart` (unused - duplicate video player logic)

### Consolidated
- ✅ All widgets now in single `lib/view/widget/` directory
- ✅ Consistent naming convention
- ✅ Logical subdirectory organization
- ✅ No duplicate files

## 📋 Usage Guidelines

1. **New Widgets**: Add new widgets to the main directory or appropriate subdirectory
2. **Naming**: Use descriptive names ending with `_widget.dart`
3. **Organization**: Group related widgets in subdirectories
4. **Imports**: Use relative imports within the widget directory
5. **Documentation**: Add comments for complex widgets

## 🚀 Benefits

- **Single Source of Truth**: All widgets in one place
- **Easy Navigation**: Logical folder structure
- **No Duplicates**: Clean, maintainable codebase
- **Consistent Naming**: Easy to find and use widgets
- **Better Performance**: No unused files cluttering the project
