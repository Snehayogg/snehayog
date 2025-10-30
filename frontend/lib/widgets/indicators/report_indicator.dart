import 'package:flutter/material.dart';

class ReportIndicator extends StatelessWidget {
  final VoidCallback onTap;
  const ReportIndicator({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 0.7,
      duration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Report',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}
