# PhotoSoap App Store screenshots

This Next.js generator turns current iPhone captures into five App Store marketing slides at Apple's supported portrait sizes.

## Generate screenshots

Run the development server:

```bash
bun run dev
```

Open [http://localhost:3000](http://localhost:3000), select the target device size, and choose **Export All**. Put visually approved 1320×2868 exports in `exports/` so the repository README always shows the same release artwork. Do not publish captures containing test data or mixed locales.

Source captures live in `public/screenshots/`. Refresh them after changing a featured screen. The marketing layouts intentionally crop the app tab bar so an older navigation order cannot leak into a new export.

The generator uses `html-to-image` and performs a warm-up render before each final capture so fonts and images are loaded consistently.
