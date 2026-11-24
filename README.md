# Photos Album Restore

macOS app that helps recreate missing albums in an iCloud Photos library from an older `.photoslibrary` backup — without copying assets.

Use this when Photos has dropped albums but the photos/videos are still in the library, and you still have a backup (for example from 2023) that contains the correct album membership.

## How it works

PhotoKit can only see the **System Photo Library**. A second library on an external drive cannot be opened side by side through Photos.app without switching libraries (risky with iCloud).

This app therefore:

1. Reads album membership from the **backup** library by scanning `Photos.sqlite` inside the `.photoslibrary` package (read-only).
2. Builds an asset index from the **current** iCloud-synced library via PhotoKit.
3. Matches old album members to current assets by fingerprint (filename, dates, dimensions, duration — not library-local IDs).
4. Writes a dry-run **restore plan** JSON describing which current assets belong in which albums.

Actually creating albums in Photos (`Restore Albums`) is not implemented yet.

## Typical workflow

1. Keep your iCloud library as the System Photo Library. Do **not** open the backup in Photos.app.
2. Run the app and grant Photos access when asked.
3. **Scan Backup Library…** — choose the backup `.photoslibrary` (e.g. on an SSD) and save `backup_album_manifest.json`.
4. **Export Current Asset Index** — save an index of assets in the live library.
5. **Create Restore Plan** — select the manifest and index; review the dry-run report and saved `restore_plan.json`.

Optional: **Manifest from System Library** exports selected albums from the currently open system library via PhotoKit (useful if you temporarily switched libraries; not needed for the SSD backup path).

## Matching notes

- Assets are matched by metadata fingerprints, not by UUID across libraries.
- Expect some unmatched or ambiguous rows (renames, edits, duplicates). The dry-run report lists examples.
- No assets are copied or deleted; the plan only maps album membership.

## Requirements

- macOS, Xcode project for local builds
- Photos library permission for the live library
- User-selected file access to choose the backup `.photoslibrary` (Full Disk Access may be needed if the open panel cannot read the package)

## Safety

- The backup scanner opens `database/Photos.sqlite` read-only (copies to a temp file if the DB is locked).
- Avoid opening the backup library in Photos while iCloud Photos is enabled on that Mac.
- Review the restore plan before any future write step that recreates albums.
