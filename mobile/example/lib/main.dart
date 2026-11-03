import 'package:flutter/material.dart';

void main() {
  runApp(const SqlCipherTestHostApp());
}

class SqlCipherTestHostApp extends StatelessWidget {
  const SqlCipherTestHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('SQLCipher integration test host')),
      ),
    );
  }
}
