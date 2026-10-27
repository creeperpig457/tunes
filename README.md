# Tunes: minimal local music player (iOS 16+)

## Get an IPA without a Mac
1. Create a new private GitHub repo and upload everything in this folder
   (including the hidden `.github` folder).
2. Repo > Actions > "Build IPA" > Run workflow (it also runs on every push).
3. When it finishes, download the `Tunes-ipa` artifact and unzip it to get `Tunes.ipa`.

## Sideload
Open Tunes.ipa in Sideloadly or AltStore and sign with your Apple ID.
(Free Apple ID = re-sign every 7 days. Paid developer account = 1 year.)

## Using it
- Songs tab > Choose Folder (pick a folder in Files, e.g. On My iPhone or iCloud Drive).
- The folder rescans every 5s while the app is open, on returning to the app, and on pull-to-refresh.
- Long-press a song to add it to a playlist.
- Formats: MP3, FLAC, AAC/M4A, ALAC, WAV, AIFF, CAF. (OGG/Opus are not supported by iOS natively.)
