/// Route paths (docs/02 §6). Later phases add session routes here.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';

  static const home = '/home';
  static const library = '/library';
  static const read = '/read';
  static const shelves = '/shelves';
  static const search = '/search';
  static const profile = '/profile';

  // Global detail routes (root navigator, docs/02 §6). Keys are
  // `id:<uuid>` or `ref:<provider>:<externalId>`.
  static const scan = '/search/scan';
  static const bookPattern = '/book/:key';
  static const authorPattern = '/author/:key';
  static const seriesPattern = '/series/:id';
  static const shelfPattern = '/shelf/:id';

  /// Full-screen timer / summary of the live session (root navigator).
  static const session = '/session';

  static const goals = '/goals';
  static const notes = '/notes';
  static const deleteAccount = '/delete-account';
  static const about = '/about';
  static const privacy = '/about/privacy';
  static const insights = '/insights';
  static const integrations = '/integrations';
  static const importCsv = '/integrations/import';
  static const importClippings = '/integrations/clippings';

  /// [editionId] opens the book at one specific edition, such as a scanned one.
  static String book(String key, {String? editionId}) =>
      '/book/${Uri.encodeComponent(key)}'
      '${editionId == null ? '' : '?edition=${Uri.encodeQueryComponent(editionId)}'}';
  static String shelf(String id) => '/shelf/${Uri.encodeComponent(id)}';
  static String author(String key) => '/author/${Uri.encodeComponent(key)}';
  static String series(String id) => '/series/${Uri.encodeComponent(id)}';

  /// Routes that only make sense before the user is fully in the app.
  static const gateRoutes = {splash, signIn, onboarding};

  /// Bottom-navigation order (approved TD-3).
  static const tabs = [home, library, shelves, read, profile];
}
