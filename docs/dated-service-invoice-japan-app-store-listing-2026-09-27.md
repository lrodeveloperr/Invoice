# 請求書作成・作業記録 — Final Japan App Store listing pack

**Status:** `DRAFT_READY`  
**Run mode:** live App Store Connect draft created; not submitted for review  
**Target storefront:** Japan  
**Supported devices:** iPhone and iPad  
**Primary metadata and first-launch language:** Japanese  
**Optional in-app language:** English, selected from Settings  
**Release option:** Automatically release after App Review approval  
**Reviewed:** 2026-09-27  
**Product source:** `dated-service-invoice-japan-live-validation-process-flow-2026-09-27.md`

Japanese is the customer-facing launch language. The app always starts in Japanese unless the user changes **設定 → 表示言語 → English**. English is a complete user-selectable interface and the owner's control layer; it is not a hidden reviewer mode. App Store metadata launches in Japanese only.

## 1. Decision

The live App Store Connect record, listing copy, ASO fields, category, age rating, pricing, availability, privacy response, review contact/notes, release setting and Lifetime Pro product are configured. The app has not been submitted for review.

The listing remains `DRAFT_READY`, not `READY_TO_SUBMIT`, until the final archive proves the local-only privacy claim, Japanese/English language switch, tax behavior, StoreKit entitlement, PDF output, backup/restore and free/paid boundaries. The iPhone and iPad screenshot sets, the IAP review screenshot and a verified app-specific privacy page also remain required before submission.

### Live App Store Connect state — 2026-09-27

| Field | Live value / state |
| --- | --- |
| Apple ID | `6816748654` |
| Bundle ID | `com.worksbienstudios.serviceinvoicejp` |
| SKU | `serviceinvoicejp-ios-2026` |
| Platform / primary language | iOS / Japanese |
| User access | Full Access |
| Version | 1.0 — Prepare for Submission |
| Release | Automatic after App Review approval |
| Age rating | 4+, no override, not Made for Kids |
| App price / base storefront | Free / Japan (JPY) |
| Availability | Japan only |
| Privacy label | Published: Data Not Collected; Japanese privacy-policy URL deployed, verified and saved; must be re-audited against the signed archive |
| Marketing URL | `https://worksbienstudios.com/apps/dated-service-invoice/` — deployed, verified and saved |
| Support URL | `https://worksbienstudios.com/apps/dated-service-invoice/support/` — deployed, verified and saved |
| Privacy Policy URL | `https://worksbienstudios.com/apps/dated-service-invoice/privacy/` — Japanese page deployed, verified and saved |
| IAP | Non-consumable created; Apple ID `6816749254`; product ID `com.worksbien.serviceinvoice.pro.lifetime`; Japan only; base price ¥2,000; Family Sharing off |
| Submission state | Not added for review and not submitted |

## 2. Final Japanese App Store metadata

| Field | Final Japanese value | English equivalent / owner note | Limit check |
| --- | --- | --- | ---: |
| **Name** | **請求書作成・作業記録｜清掃・修理・メンテナンス** | **Invoice Maker & Work Log \| Cleaning, Repair & Maintenance** | **23 / 30 characters** |
| **Subtitle** | **日付と現場を月末にまとめてPDF発行** | **Combine Dates and Job Sites into a Month-End PDF** | **18 / 30 characters** |
| **Keywords** | `個人事業主,一人親方,インボイス,保守点検,作業日報,未請求,入金管理` | Sole proprietor, independent tradesperson, qualified invoice, maintenance inspection, work report, unbilled work, payment tracking | **93 / 100 UTF-8 bytes** |
| Promotional text | **None at launch** | It is not an ASO ranking field and would create a stale message. | — |
| Primary category | **ビジネス / Business** | The core job is issuing business invoices from completed work. | — |
| Secondary category | **仕事効率化 / Productivity** | The workflow converts daily records into month-end output. | — |
| App price | **無料 / Free** | The download is free. | — |
| In-App Purchase | **買い切りPro / Lifetime Pro** | One non-consumable unlock; no subscription. | — |
| Availability | **Japan only at launch** | English is an in-app control layer, not a signal of global launch scope. | — |
| What's New | **Not applicable to version 1.0** | Draft only for later updates. | — |

### Japanese description

```text
清掃・修理・メンテナンスなど、同じ取引先を何度も訪問する個人事業主や小規模事業者向けの請求書作成・作業記録アプリです。

訪問ごとに作業日、現場、作業内容、数量、単位、単価、税率を記録。未請求の作業を選ぶだけで、複数の日付と現場を1枚の月末請求書PDFにまとめられます。

日付を品名欄に書き足したり、紙のメモやカレンダーを月末に見直したりする必要はありません。毎日の作業記録が、そのまま読みやすい請求明細になります。

【訪問ごとの作業記録】
・取引先と複数の現場を登録
・作業日、内容、数量、単位、単価、税率を記録
・前回の作業を複製して繰り返し入力を短縮
・入力途中でも下書きを端末内に保存

【未請求の作業がすぐ分かる】
・取引先と月ごとに未請求の作業を一覧表示
・離れた日付や過去の月も自由に選択
・請求済みの作業を誤って重複請求しないよう管理

【日付・現場別の請求書PDF】
・選んだ作業を日付と現場ごとに整理
・現場別の小計、税率別の消費税、合計を自動計算
・適格請求書発行事業者の登録番号、振込先、支払期限を設定可能
・長い作業内容は読みやすく改行し、複数ページに自動対応

【送る前に仕上がりを確認】
画面に表示するプレビューと、保存・共有するPDFは同じ内容です。金額、税額、日付、現場、改ページを確認してから発行できます。

発行後の請求書はPDFと一緒に保存され、再共有や入金済みの記録ができます。発行済みの内容を変更するときは、元の請求書を残したまま明示的に訂正します。

【アカウント不要・オフライン対応】
作業記録、取引先情報、請求書は端末内に保存します。アカウント登録は不要です。データとPDFは自分で書き出してバックアップできます。

【無料版と買い切りPro】
無料版では、2件の取引先への作業記録、請求書の完成プレビュー、最初の1通の請求書発行を利用できます。

買い切りのProでは、取引先数と請求書発行数の制限がなくなり、作業テンプレート、締め日・支払条件の保存、ロゴとPDFデザインを利用できます。購入画面にはApp Storeの現在の価格を表示します。サブスクリプションや広告はありません。

購入しなくても、保存した作業記録、発行済みの請求書、データのバックアップには引き続きアクセスできます。

本アプリは請求書作成を補助するツールであり、税務・会計・法務上の助言を行うものではありません。発行前に内容をご確認ください。
```

### English equivalent — owner review only

```text
Designed for sole proprietors and small businesses that repeatedly visit the same customers for cleaning, repair, maintenance and similar services.

Record the work date, job site, work performed, quantity, unit, unit price and tax rate for every visit. Select the unbilled jobs you want, then combine multiple dates and job sites into a single month-end invoice PDF.

There is no need to add dates manually to item descriptions or review paper notes and calendars at the end of every month. Your daily work records automatically become clear, readable invoice details.

[Work records for every visit]
- Register customers and multiple job sites
- Record the date, work performed, quantity, unit, unit price and tax rate
- Duplicate previous jobs to reduce repetitive entry
- Save unfinished records locally as drafts

[See unbilled work immediately]
- View unbilled jobs by customer and month
- Select work from separate dates or previous months
- Track invoiced work to help prevent duplicate billing

[Invoices organized by date and job site]
- Organize selected work by date and job site
- Automatically calculate site subtotals, tax by rate and the total
- Add your qualified invoice registration number, bank details and payment deadline
- Automatically wrap long descriptions and support multi-page invoices

[Check everything before sending]
The on-screen preview shows the same content as the PDF you save or share. Confirm the amounts, tax, dates, job sites and page breaks before issuing the invoice.

Issued invoices are stored with their PDFs so they can be shared again or marked as paid. When changes are required, create an explicit correction while preserving the original invoice.

[No account required and works offline]
Work records, customer information and invoices are stored on your device. No account registration is required. You can export your data and PDFs for backup.

[Free version and one-time Pro purchase]
The free version supports work records for two customers, complete invoice previews and issuance of the first invoice.

The one-time Pro purchase removes customer and invoice limits and unlocks work templates, saved closing dates and payment terms, logos and PDF designs. The purchase screen displays the current App Store price. There are no subscriptions or advertisements.

Without purchasing Pro, you can still access saved work records, previously issued invoices and data backups.

This app assists with creating invoices. It does not provide tax, accounting or legal advice. Please verify all information before issuing an invoice.
```

## 3. Language behavior

| Surface | Japanese | English equivalent / behavior |
| --- | --- | --- |
| First launch | 日本語 | Japanese, regardless of device language |
| Settings row | 表示言語 | Display Language |
| Options | 日本語 / English | Japanese / English |
| Change behavior | 選択後すぐに画面全体を切り替える | Apply the language to the entire interface immediately after selection. |
| Persistence | 選択した言語を端末内に保存 | Save the selected language locally. |
| Reviewer path | 設定 → 表示言語 → English | Settings → Display Language → English |

The English option must expose the same features, paywall, privacy text, errors and purchase-restoration flow as Japanese. It must never reveal debug controls, preloaded data or review-only behavior.

## 4. Lifetime Pro In-App Purchase

| Field | Final value | English equivalent / note |
| --- | --- | --- |
| Type | **Non-Consumable** | Permanent lifetime unlock |
| Reference name | **Dated Service Invoice Pro Lifetime** | Internal only |
| Product ID | **`com.worksbien.serviceinvoice.pro.lifetime`** | Final permanent identifier; verify it is unused before creation because Apple does not allow later editing. |
| Japanese display name | **買い切りPro** | **Lifetime Pro** |
| Japanese description | **取引先・請求書の制限解除と便利機能を永久に利用** | **Permanently remove customer and invoice limits and unlock convenience features** |
| Target Japan price | **¥2,000 one time** | Select the nearest available Apple price point at or below ¥2,000. The app must display StoreKit's live localized price. |
| Subscription | **None** | No recurring billing |
| Ads | **None** | No advertising |
| Family Sharing | **Off at launch** | Avoid promising shared business records or entitlements until tested. |
| App Store promotion | **Off at launch** | No promotional IAP image or storefront promotion required. |

### Purchase-page copy

**Japanese**

```text
買い切りPro

一度の購入で、ずっと利用できます。

・取引先数の制限を解除
・請求書発行数の制限を解除
・作業テンプレートと前回コピー
・締め日と支払条件を保存
・ロゴとPDFデザイン

サブスクリプションではありません。価格はApp Storeから取得して表示します。

［Proを購入］　［購入を復元］
```

**English equivalent**

```text
Lifetime Pro

Pay once and use it permanently.

- Remove the customer limit
- Remove the invoice issuance limit
- Work templates and copy previous visit
- Save closing dates and payment terms
- Logo and PDF designs

This is not a subscription. The current price is displayed directly from the App Store.

[Purchase Pro]  [Restore Purchase]
```

## 5. Screenshot and icon brief

Use three authentic Japanese iPhone screenshots and three authentic Japanese iPad screenshots from the final build. Both device sets use the same three-message sequence. English screenshots are not required for the Japan-only storefront. The English equivalents below are owner translations, not text to place on the Japanese assets.

| Order | Japanese caption | English equivalent | Required source screen | Proof shown |
| ---: | --- | --- | --- | --- |
| 1 | **月末の請求書を、数分で** | **Create Month-End Invoices in Minutes** | 作業 / Work ledger | Several dated, unbilled visits grouped by customer with a clear Record Work action. |
| 2 | **作業日と現場が、そのまま明細に** | **Dates and Job Sites Become Invoice Lines** | 請求内容 / Invoice Builder | Non-consecutive visits selected, grouped by date and site, with visible totals. |
| 3 | **送る前に、PDFを正確に確認** | **Check the Exact PDF Before Sending** | プレビュー・発行 / PDF Preview & Issue | Readable real PDF preview, page count and issue/share action. |

### Screenshot production rules

- iPhone master: **1320 × 2868 px**, portrait, no alpha channel. This is a currently accepted 6.9-inch iPhone size.
- iPad master: **2752 × 2064 px**, landscape, no alpha channel. This is a currently accepted 13-inch iPad size and should visibly prove the split-view list/detail workflow.
- Apple requires the 13-inch screenshot set when the app runs on iPad. Recheck the live specification immediately before export.
- Use one consistent fictional Japanese cleaning or maintenance business, customer and set of visits across all three frames.
- Show Japanese UI only. No mixed Japanese/English interface.
- No static purchase price in screenshots.
- If a screenshot shows a paid-only control, make the paid boundary understandable on the product page; do not add a “Pro” badge to every frame.
- Do not include an app preview video at launch.

### Icon direction

One restrained business icon: a white invoice sheet with three short dated rows and one dark blue checkmark on an indigo square. No text, yen symbol, calculator grid, gradients that reduce contrast or generic document-stack detail. Validate recognizability at small App Store search size against Japanese invoice apps before locking the asset.

## 6. URLs and public pages

The app-specific marketing, support and Japanese privacy paths below were deployed, verified in the live browser and saved in App Store Connect on 2026-09-27. Recheck them against the final binary immediately before submission.

| Field | Reserved URL | Required content |
| --- | --- | --- |
| Marketing URL | `https://worksbienstudios.com/apps/dated-service-invoice/` | Japanese product page; saved in App Store Connect |
| Support URL | `https://worksbienstudios.com/apps/dated-service-invoice/support/` | Japanese help, English-language switch, contact path and purchase restoration; saved in App Store Connect |
| Privacy Policy URL | `https://worksbienstudios.com/apps/dated-service-invoice/privacy/` | Japanese disclosure covering local records, PDF/backup exports, StoreKit, no ads/analytics/tracking and optional support email; saved in App Store Connect |
| Terms URL | `https://worksbienstudios.com/apps/dated-service-invoice/terms` | License, user responsibility for invoice accuracy and liability boundaries |

The marketing, support and privacy URLs are live and saved. The separate terms URL remains reserved and must not be used until deployed and verified; it is not currently an App Store Connect listing field for this app.

## 7. App Store Connect answer pack

These are the intended answers for the planned binary. Re-audit the signed archive and live App Store Connect state before submission.

| Area | Planned answer | Release condition |
| --- | --- | --- |
| App privacy | **No, we do not collect data from this app** | Valid only if neither WorksBien nor any third-party SDK receives user, device, diagnostic, usage or purchase-linked data from the app. |
| Tracking | **No** | No ATT prompt, advertising identifier, tracking SDK or cross-company tracking. |
| Account | **No account creation or sign-in** | All primary functionality remains local and available without registration. |
| Content rights | **The app does not contain, show or access third-party content** | User-entered invoice content does not become developer-supplied third-party content; audit bundled assets and fonts. |
| Advertising | **No ads** | Final build contains no ad SDK or promotional ad surface. |
| User-generated public content | **No** | Records and PDFs are private and device-local; no public sharing service exists. |
| Web access | **No unrestricted web access** | External policy/support links may open system browser; no embedded general browser. |
| In-app controls | **None** | No parental controls because this is a business utility. |
| Objectionable-content descriptors | **None** | No violence, sexual content, profanity, gambling, contests, loot boxes, alcohol/tobacco/drugs, horror or medical content. |
| Expected age rating | **4+ / lowest applicable Apple global rating** | App Store Connect calculates the final country-specific result from the completed questionnaire. Do not override upward unless the final build changes. |
| Made for Kids | **No** | Business invoicing utility. |
| Encryption/export | **Uses only Apple operating-system encryption; no non-exempt custom cryptography planned** | Set `ITSAppUsesNonExemptEncryption = NO` only after dependency and archive inspection confirms this. |
| IAP | **One non-consumable Lifetime Pro product** | Product and Japanese metadata are live at ¥2,000 in Japan. The review screenshot, StoreKit implementation and tested restore flow remain required. |
| Availability | **Japan** | Expand only after a separate localization and legal/tax review. |
| Release | **Automatically release this version after App Review approval** | No manual hold and no scheduled earliest date. Apple may still take up to 24 hours to make the approved app visible on the App Store. |

## 8. App Review notes

Use the following after inserting the final version/build and confirming the feature paths.

```text
This is a local-first invoice and work-record app for Japanese sole service operators. No account or sign-in is required.

The app launches in Japanese. To switch the complete interface to English, open Settings (設定) > Display Language (表示言語) > English.

Core review path:
1. Open Work (作業).
2. Tap Record Work (作業を記録), then create or select a customer and job site.
3. Save visits on multiple dates.
4. Select the unbilled visits and open Invoice Details (請求内容).
5. Tap Check PDF (PDFを確認).
6. The first client-ready invoice can be issued free of charge.

Lifetime Pro is a non-consumable In-App Purchase. Its purchase screen can be reached from Settings > Pro, by attempting to create a third active customer, or by attempting to issue a second client-ready invoice. Restore Purchase is available on the same screen.

The app does not require special hardware, credentials, network access or location access. Work records, customer information, invoice snapshots and PDFs are stored on the device. The system share sheet is used only when the user chooses to export or share a PDF or backup.

The app helps users prepare invoices but does not provide tax, accounting or legal advice.
```

## 9. ASO rationale

### Live Japanese App Store language observed on 2026-09-27

| Search phrase | Live result pattern | Metadata consequence |
| --- | --- | --- |
| `作業記録 請求書` | Returned KIC nippo, GenbaPocket, time-log and trade-job apps. | Put both **請求書作成** and **作業記録** in the name. |
| `清掃 請求書` | Returned GenbaPocket, cleaning-report apps, Estimaid and ServiceCall, mostly without meaningful ratings. | Put **清掃** in the name: it is the clearest underserved launch vertical. |
| `修理 請求書` | Returned repair work-order and field-service products. | Put **修理** in the name to reach the second credible service segment. |
| `メンテナンス 請求書` | Sparse results led by work-report tools rather than a strong invoice specialist. | Put **メンテナンス** in the name as a natural higher-value synonym and whitespace signal. |
| `請求書 日付` | Results were thin; the leading result had only four ratings. | Put **日付** in the subtitle, paired with the outcome. |
| `月末 請求書` | Returned only the two-rating construction attendance/invoice app in the visible results. | Put **月末** in the subtitle; it states the recurring moment of need and exposes weak supply. |
| `訪問サービス 請求書` | Produced one irrelevant institutional result. | Do not spend title space on `訪問サービス`; explain the concept naturally in the description. |

The name contains the primary task and credible service verticals. The subtitle adds the distinct date/site/month-end/PDF workflow without repeating the exact name terms. The keyword field uses omitted customer and workflow language. The readable description supports conversion and web discovery without keyword stuffing.

## 10. Fact ledger and release boundary

| Claim | Current basis | Confidence / release condition |
| --- | --- | --- |
| Customer is a repeat-visit sole service operator | Live review and supply audit in the product specification | High as positioning; conversion remains unmeasured. |
| Japanese default; English selectable in Settings | Explicit owner decision dated 2026-09-27 | Build and test complete feature parity in both languages. |
| Dates, sites, unbilled ledger and exact PDF preview | Locked product design | Must be demonstrated in final build. |
| Local storage, no account, offline use | Locked architecture | Audit final dependencies, network traffic and privacy manifest. |
| One free issued invoice; two active customers | Locked monetization decision | Build, StoreKit and listing must match. |
| Non-consumable lifetime Pro; no subscription or ads | Product created in App Store Connect | Test purchase/restore and confirm the final binary contains no subscription or ad code. |
| Target Japan price ¥2,000 | Live App Store Connect base price and owner-approved product spec | Use StoreKit's live price; do not hard-code it in customer-facing copy. |
| Tax fields and calculations | Planned deterministic engine | Verify with current official Japanese requirements and fixed tests before using the description unchanged. |
| Universal iPhone and iPad launch | Current product decision | Confirm both device families in the final target and pass the compact/regular-width navigation matrix. |

## 11. Validation

- Apple's official App Store Connect references reviewed on 2026-09-27 limit the localized name and subtitle to 30 characters each, description to 4,000 characters and keywords to 100 UTF-8 bytes. The live IAP editor accepted fields within its current 35-character display-name and 55-character description counters.
- Name: **23 characters** — pass.
- Subtitle: **18 characters** — pass.
- Keyword field: **93 UTF-8 bytes** — pass.
- Japanese description: plain text and below 4,000 characters — pass.
- No competitor names, unauthorized trademarks, ranking/download claims or static App Store price appear in customer-facing listing copy or screenshot captions.
- Japanese is the only storefront localization at launch. English is disclosed as an in-app language and must be fully reachable in Settings.
- Final human/build review remains required for tax behavior, privacy, StoreKit, backup/restore, exact PDF output, language parity, accessibility support, screenshots and every free/paid boundary. Recheck all deployed URLs immediately before submission.

**Final listing-stage decision:** `DRAFT_READY`. The live record, non-media listing configuration and Japanese privacy/support pages are complete; only media and build-dependent declarations remain. The next listing action is to produce the final icon, authentic Japanese iPhone and iPad screenshot sets, and the IAP review screenshot; then upload the signed universal build, test the purchase/restore flow, and audit the archive before adding anything for review.
