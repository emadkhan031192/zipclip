import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Render the first frame immediately; the database, settings and clipboard
  // all load in the background (see providers/bootstrap.dart).
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: ZipClipApp()));
}
