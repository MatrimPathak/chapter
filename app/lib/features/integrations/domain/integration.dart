enum IntegrationId { goodreads, storygraph, kindle, audible, spotify }

/// What an integration really does: declared, never assumed. None of these
/// reads anything from the other service's account (docs/04).
enum IntegrationCapability { importFile, manualProgress, openExternal }

enum IntegrationStatus { available, unavailable }

/// One connected service. Each is isolated behind its own provider, so if one
/// fails only its card is affected (docs/04 §7).
abstract interface class Integration {
  IntegrationId get id;
  Set<IntegrationCapability> get capabilities;
  Stream<IntegrationStatus> get status;
}

/// An integration that needs no account or network to be available.
final class LocalIntegration implements Integration {
  const LocalIntegration(this.id, this.capabilities);

  @override
  final IntegrationId id;

  @override
  final Set<IntegrationCapability> capabilities;

  @override
  Stream<IntegrationStatus> get status => Stream.value(IntegrationStatus.available);
}

const defaultIntegrations = <Integration>[
  LocalIntegration(IntegrationId.goodreads, {IntegrationCapability.importFile}),
  LocalIntegration(IntegrationId.storygraph, {IntegrationCapability.importFile}),
  LocalIntegration(IntegrationId.kindle, {
    IntegrationCapability.importFile,
    IntegrationCapability.manualProgress,
  }),
  LocalIntegration(IntegrationId.audible, {
    IntegrationCapability.manualProgress,
    IntegrationCapability.openExternal,
  }),
  LocalIntegration(IntegrationId.spotify, {IntegrationCapability.openExternal}),
];

/// Links that open in the other service's app or website. Public web addresses
/// only: no accounts, API keys or private endpoints.
abstract final class ExternalLinks {
  /// Audible's stores by country. From elsewhere, audible.com redirects to the
  /// local home page and loses the search, so go to the local store directly.
  static const _audibleStores = {
    'AU': 'www.audible.com.au',
    'BR': 'www.audible.com.br',
    'CA': 'www.audible.ca',
    'DE': 'www.audible.de',
    'ES': 'www.audible.es',
    'FR': 'www.audible.fr',
    'GB': 'www.audible.co.uk',
    'IN': 'www.audible.in',
    'IT': 'www.audible.it',
    'JP': 'www.audible.co.jp',
  };

  static Uri audibleSearch(String title, {String? country}) => Uri.https(
    _audibleStores[country?.toUpperCase()] ?? 'www.audible.com',
    '/search',
    {'keywords': title},
  );

  static Uri spotifySearch(String query) =>
      Uri.parse('https://open.spotify.com/search/${Uri.encodeComponent(query)}/playlists');

  /// Searches, not curated playlists: real playlist links can replace these
  /// once someone has chosen some.
  static final spotifyHome = Uri.parse('https://open.spotify.com');

  static const readingSearch = 'music for reading';
  static const classicalSearch = 'classical for reading';
  static const ambientSearch = 'ambient reading';
}
