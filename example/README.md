# Fieldnotes example

Run with `flutter run` on iOS 18+ or Android 12+.

The sample indexes three in-memory notes at startup. The search field queries
the native index, the add/delete controls mutate notes and their index entries,
and the toolbar can clear or rebuild the notes domain. Restarting restores the
sample notes. iOS exposes the semantic-search toggle; Android exposes an
opt-in system-visibility toggle.

For Spotlight, leave the app, search for "Lemon pasta" in system search, and
select the result. The activation stream resolves the note by domain and ID.
Indexing may take time. Android launcher results depend on the launcher; the
in-app search works independently of launcher support.

See the package README for API setup and integration-test instructions.
