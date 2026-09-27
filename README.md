# Invoice — Japan iPhone app package

This repository contains the product specification, finalized App Store listing pack, and deterministic App Store screenshot-shell tooling for the Japan-first dated-service invoice app.

## Product

- Japanese name: **請求書作成・作業記録｜清掃・修理・メンテナンス**
- English equivalent: **Invoice Maker & Work Log | Cleaning, Repair & Maintenance**
- Platform: iPhone
- Launch storefront: Japan
- Default language: Japanese
- Optional in-app control language: English via **設定 → 表示言語 → English** (Settings → Display Language → English)
- Monetization: free download with one non-consumable **買い切りPro** (Lifetime Pro) purchase

## Repository structure

- `docs/dated-service-invoice-japan-live-validation-process-flow-2026-09-27.md` — validated workflow, engine, pricing gate, and screen specification.
- `docs/dated-service-invoice-japan-app-store-listing-2026-09-27.md` — finalized non-media App Store listing and submission boundary.
- `docs/screenshot-research-2026-09-27.md` — live Japanese App Store evidence and the resulting creative decision.
- `marketing/screenshots/render_screenshot_shells.py` — deterministic shell renderer.
- `marketing/screenshots/ja-JP/iphone-6.9/shells/` — three 1320 × 2868 Japanese screenshot shells.
- `marketing/screenshots/ja-JP/iphone-6.9/contact-sheet.png` — thumbnail review sheet.
- `marketing/screenshots/ja-JP/iphone-6.9/manifest.json` — captions, geometry, output properties, and hashes.

## Screenshot captions

| Order | Japanese storefront caption | English equivalent |
| ---: | --- | --- |
| 1 | 月末の請求書を、数分で | Create Month-End Invoices in Minutes |
| 2 | 作業日と現場が、そのまま明細に | Dates and Job Sites Become Invoice Lines |
| 3 | 送る前に、PDFを正確に確認 | Check the Exact PDF Before Sending |

The English text is owner-facing only and does not appear on the Japanese storefront assets.

## Rendering

Run from the repository root:

```bash
python3 marketing/screenshots/render_screenshot_shells.py
```

The script regenerates the three blank shells, contact sheet, and manifest. To compose authentic final UI, place full-resolution Japanese screenshots at:

```text
marketing/screenshots/source/ja-JP/01.png
marketing/screenshots/source/ja-JP/02.png
marketing/screenshots/source/ja-JP/03.png
```

Then run:

```bash
python3 marketing/screenshots/render_screenshot_shells.py --with-sources
```

Only proportional scaling and centered clipping are applied inside the locked aperture. The source UI is not redrawn, translated, stretched, or fabricated.

## Release status

The non-media App Store record is configured. The app remains `DRAFT_READY`: final authentic UI screenshots, the IAP review screenshot, a signed build, purchase/restore testing, and archive-level privacy/compliance verification remain before review submission.
