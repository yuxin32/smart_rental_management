import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presentation preferences only. Muting indicators does not mark records as
/// read, stop delivery, request OS push permission or change server history.
class DevicePreferences extends ChangeNotifier {
  String? _account;
  int _generation = 0;
  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  bool bookingIndicators = true, messageIndicators = true, ready = false;
  Future<void> bindAccount(String? account) async {
    if (_account == account && ready) return;
    _account = account;
    final generation = ++_generation;
    ready = false;
    bookingIndicators = messageIndicators = true;
    notifyListeners();
    if (account == null) return;
    try {
      final store = await SharedPreferences.getInstance();
      if (generation != _generation) return;
      bookingIndicators =
          store.getBool('ui:$account:bookingIndicators') ?? true;
      messageIndicators =
          store.getBool('ui:$account:messageIndicators') ?? true;
      ready = true;
      notifyListeners();
    } catch (_) {
      // Loading failure leaves controls unavailable rather than claiming saved.
      if (generation == _generation) notifyListeners();
    }
  }

  Future<bool> save({required bool booking, required bool enabled}) async {
    final account = _account, generation = _generation;
    if (account == null || !ready) return false;
    try {
      final store = await SharedPreferences.getInstance();
      final ok = await store.setBool(
          'ui:$account:${booking ? 'bookingIndicators' : 'messageIndicators'}',
          enabled);
      if (!ok || generation != _generation) return false;
      if (booking) {
        bookingIndicators = enabled;
      } else {
        messageIndicators = enabled;
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
