/// A stub implementation of TurboVecBindings for web and other non-FFI platforms.
class TurboVecBindings {
  /// A custom path to the turbovec dynamic library (unused on web).
  static String? customLibraryPath;

  /// Singleton instance of the bindings.
  static final TurboVecBindings instance = TurboVecBindings._();

  TurboVecBindings._();
}
