import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.green,
        body: Center(
          child: Text(
            'PURE MAIN OK',
            style: TextStyle(fontSize: 40, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}
