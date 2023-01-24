import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

@internal
class ActionNotifier extends ChangeNotifier {
  bool _isActionNeeded = true;

  set isActionNeeded(bool doAction) {
    _isActionNeeded = doAction;
    if (doAction) {
      notifyListeners();
    }
  }

  bool get isActionNeeded => _isActionNeeded;
}