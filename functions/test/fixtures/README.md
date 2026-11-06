# Provider fixtures

| File                 | Source                                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `openlibrary_*.json` | **Recorded live** from openlibrary.org on 2026-11-04 (public API, no key).                                                                                                                                                      |
| `googlebooks_*.json` | **Hand-built from the documented v1 `volumes` schema.** Live recording was impossible because keyless requests returned HTTP 429 with a per-day quota of 0. Re-record once a `GOOGLE_BOOKS_KEY` exists.                         |
| `hardcover_*.json`   | **Hand-built from the documented GraphQL shapes** (docs.hardcover.app: searching, getting book details). There's no API token yet (`SPIKE-88083021`). Re-record against the live API before relying on Hardcover in production. |

The provider tests never call the network; they replay these files through an injected `FetchJson`.
