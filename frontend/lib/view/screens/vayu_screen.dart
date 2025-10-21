import 'package:flutter/material.dart';

class VayuScreen extends StatelessWidget {
  const VayuScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white70,
      alignment: Alignment.center,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Videos are available only on the Yog tab.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
      ),
    );
  }
}
