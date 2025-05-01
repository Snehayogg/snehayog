import 'package:flutter/material.dart';

class FeedAdWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        color: Colors.amber[200],
        margin: const EdgeInsets.all(32),
        child: const Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            "Sponsored Ad",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
