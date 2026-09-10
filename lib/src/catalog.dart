/// Widget catalog export.
///
/// Both methods return an empty map: the catalog was never implemented against
/// the widget tree. They are kept only so code written against 0.1.0 still
/// compiles, and they go away once the locator layer can enumerate widgets for
/// real.
@Deprecated('Returns an empty map. Removed in 0.3.0 once locators land.')
class WidgetCatalog {
  @Deprecated('Returns an empty map. Removed in 0.3.0 once locators land.')
  static Map<String, dynamic> exportCatalog() => {};

  @Deprecated('Returns an empty map. Removed in 0.3.0 once locators land.')
  static Map<String, dynamic> exportByScreen() => {};
}

/// Route/flow metadata export.
///
/// Returns an empty map: never implemented. Kept for source compatibility with
/// 0.1.0 only.
@Deprecated('Returns an empty map. Removed in 0.3.0.')
class FlowDiscovery {
  @Deprecated('Returns an empty map. Removed in 0.3.0.')
  static Map<String, dynamic> exportMetadata(dynamic router) => {};
}
