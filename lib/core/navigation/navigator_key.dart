import 'package:flutter/material.dart';

/// Global navigator key so push-notification tap handlers (which run
/// outside any widget's BuildContext — e.g. when the app was fully closed)
/// can still navigate to the right screen once the app opens.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();