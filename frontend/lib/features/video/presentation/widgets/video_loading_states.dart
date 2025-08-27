import 'package:flutter/material.dart';

/// Widget for displaying video loading states
/// This follows the const constructor pattern for better performance
class VideoLoadingStates extends StatelessWidget {
  const VideoLoadingStates({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 3, // Show 3 loading cards
      itemBuilder: (context, index) {
        return const VideoLoadingCard();
      },
    );
  }
}

/// Individual loading card widget
class VideoLoadingCard extends StatelessWidget {
  const VideoLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Loading thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),

          // Loading content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Loading title
                Container(
                  height: 20,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                const SizedBox(height: 8),

                // Loading description lines
                Container(
                  height: 16,
                  width: MediaQuery.of(context).size.width * 0.7,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  height: 16,
                  width: MediaQuery.of(context).size.width * 0.5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                const SizedBox(height: 16),

                // Loading uploader info
                Row(
                  children: [
                    // Loading avatar
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Loading name and time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 12,
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Loading video type
                    Container(
                      height: 24,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Loading action buttons
                Row(
                  children: [
                    // Loading like button
                    _buildLoadingActionButton(),

                    const SizedBox(width: 24),

                    // Loading comment button
                    _buildLoadingActionButton(),

                    const SizedBox(width: 24),

                    // Loading share button
                    _buildLoadingActionButton(),

                    const Spacer(),

                    // Loading views
                    Container(
                      height: 12,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingActionButton() {
    return Container(
      height: 24,
      width: 60,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
