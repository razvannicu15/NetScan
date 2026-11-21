import 'services/scan_controller.dart';
import 'services/storage.dart';

/// App-wide singletons (kept deliberately simple).
final AppSettings appSettings = AppSettings();
final ScanController scanner = ScanController(appSettings);
