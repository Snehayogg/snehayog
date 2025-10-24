#!/bin/bash

echo "🔍 Verifying Vayu Flutter Setup..."
echo ""

# Check if we're in the frontend directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: Not in frontend directory!"
    echo "   Please run this script from: snehayog/frontend/"
    exit 1
fi

# Check if snehayog_monetization exists
PACKAGE_PATH="../packages/snehayog_monetization"
if [ ! -d "$PACKAGE_PATH" ]; then
    echo "❌ Error: snehayog_monetization package not found!"
    echo "   Expected location: $PACKAGE_PATH"
    echo ""
    echo "📁 Your folder structure should be:"
    echo "   snehayog/"
    echo "   ├── backend/"
    echo "   ├── frontend/ (you are here)"
    echo "   └── packages/"
    echo "       └── snehayog_monetization/ (MISSING!)"
    echo ""
    echo "💡 Solution:"
    echo "   1. Make sure you cloned the complete repository"
    echo "   2. Or copy snehayog_monetization folder to the correct location"
    exit 1
fi

echo "✅ snehayog_monetization package found!"

# Check if package has pubspec.yaml
if [ ! -f "$PACKAGE_PATH/pubspec.yaml" ]; then
    echo "❌ Error: snehayog_monetization/pubspec.yaml not found!"
    exit 1
fi

echo "✅ snehayog_monetization/pubspec.yaml exists!"

# Check Flutter installation
if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter is not installed or not in PATH!"
    echo "   Install Flutter from: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter is installed: $(flutter --version | head -n 1)"

# All checks passed
echo ""
echo "🎉 Setup verification passed!"
echo "✅ All dependencies are in place"
echo ""
echo "📝 Next steps:"
echo "   1. Run: flutter pub get"
echo "   2. Run: flutter run"
echo ""

