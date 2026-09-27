# 日付別請求書・作業明細 — Dated Service Invoice

## Live Japan App Store validation, locked process flow and commercial model

**Observed:** 27 September 2026 on the live Japan iPhone App Store using the cloud browser. Ratings and prices are storefront snapshots. Apple exposes selected reviews rather than a representative or complete review sample, and it does not disclose downloads or conversion.

## Decision

**Build a narrow local-first app for cleaners, maintenance operators, repair contractors and similar one-person service businesses that visit the same customer on several dates and need one readable monthly invoice.**

Do **not** build a generic invoice maker, construction attendance ledger, field-service CRM, scheduling system, quote engine, accounting package or photo-report platform.

The product promise is:

> Record each completed visit in seconds. At month-end, select the unbilled visits and produce one client-ready invoice whose work dates and sites are explicit, readable and correct.

The opportunity is **moderate-confidence but buildable**. Large established apps validate demand and payment. Multiple reviews expose failures that matter at the moment of billing. Direct work-log-to-invoice supply has expanded rapidly, but the closest products have only 0–9 Japan ratings and are concentrated in construction. The defensible wedge is therefore **multi-visit service invoicing outside construction**, with deterministic calculations, safe drafts, exact PDF preview, full local ownership and no subscription.

## What the live market says

### Established demand and paid proof

| App | Live Japan evidence | What it teaches us |
| --- | --- | --- |
| [Misoca](https://apps.apple.com/jp/app/id1026534800) | **4.7 / about 15,000 ratings**. Light plan **¥500**; invoice tickets also sold. | Large demand for simple mobile invoice creation. It is document-first and cloud-account oriented, not a daily visit ledger. |
| [Jimuu](https://apps.apple.com/jp/app/id880562158) | **4.5 / 5,674 ratings**; Premium **¥500/month**, consolidated-invoice option **¥100/month**. Listing claims 400,000 cumulative downloads and 10,000 Premium users as of 1 October 2025; this is the developer's claim, not Apple data. | Strongest evidence for the exact problem. A cleaner explicitly asks for a date on every invoice line so several visits can appear on one invoice; the developer's workaround is to type the date into the item name. |
| [Estilynx](https://apps.apple.com/jp/app/id1400019566) | **4.1 / 1,033 ratings**, **¥2,500 upfront**, #3 in paid Business during this pass. | Strong proof that Japanese sole operators pay once for offline document software. Reviews request more flexible fields, source-withholding support, clearer navigation and a company logo. |
| [スマホで請求書](https://apps.apple.com/jp/app/id984892840) | **3.5 / 636 ratings**, **¥900** unlock. | Low-cost buyout demand, but repeated 2024–2025 reports describe freezing while adding invoice lines or customers, including after upgrading. Users fear deleting the app because of existing invoice data. |
| [シンプル請求書作成アプリ](https://apps.apple.com/jp/app/id6747994154) | **4.6 / 653 ratings**, three invoices/month free, then **¥380/month**. | Strong evidence that a narrowly simple invoice interface can attract use. Recent reviews ask for a unit field and for dates to be blank or flexible when work spans or skips days. |
| [Remodela Office](https://apps.apple.com/jp/app/id1563191136) | **2.7 / 63 ratings**, **¥980** subscription. | The cost of failure is explicit: purchase-screen crashes, blank preview, unreadably tiny printed text, incorrect tax output, app launch failures and login friction. |

### Direct and adjacent supply

| App | Live Japan evidence | Supply assessment |
| --- | --- | --- |
| [現場請求 — Site Billing](https://apps.apple.com/jp/app/id6792292495) | No displayed rating average. **¥980/month or ¥9,800/year** after 30 days. Completed fieldwork becomes monthly invoice candidates; includes scheduling, payment status and multi-user sharing. | Closest high-level workflow, but heavier, account/cloud/team oriented and unvalidated by rating volume. |
| [出面帳＆請求書](https://apps.apple.com/jp/app/id6787174190) | **5.0 / 2 ratings**, **¥1,500 one-time**. Daily construction attendance becomes invoice and attendance PDFs; local-first, backup and optional iCloud. | Near-exact construction product. Its tiny rating base does not validate traffic or satisfaction. It confirms that ¥1,500 is the current low direct-buyout anchor. |
| [親方帳](https://apps.apple.com/jp/app/id6789149108) | **3.8 / 5 ratings**, **¥2,000 one-time**. Construction attendance, expenses and tax return workflow. | A recent user could not invoice older months; the developer admitted the date-range limitation and added historical months plus an unbilled queue. This directly validates the need for arbitrary historical periods and an explicit unbilled ledger. |
| [KIC nippo](https://apps.apple.com/jp/app/id6776567549) | **5.0 / 9 ratings**; IAPs shown at **¥1,000** and **¥2,000** for Pro/MAX. | Broad construction system covering daily reports, payroll, attendance, invoices and photos. The tiny, uniformly positive review base does not establish durable demand for its whole bundle. |
| [GenbaPocket](https://apps.apple.com/jp/app/id6785335353) | No displayed rating average. **¥600/month or ¥4,500/year**. | Very broad local-first product for cleaning, construction, therapy, tutoring and visits, including schedules, reports, photos, quotes, invoices and widgets. Breadth is its risk; it does not establish traction for the exact monthly multi-visit invoice job. |
| [Estimaid](https://apps.apple.com/jp/app/id6777764178) | No displayed rating average. Japan IAPs **¥3,000/month or ¥25,000/year**. | Cleaning-specific but quote-first: room/area pricing, deposits and conversion to invoice. It does not solve the recurring completed-visits-to-monthly-invoice job, and its price is far above Japanese local utility anchors. |
| [ServiceCall](https://apps.apple.com/jp/app/id6740412025) | No displayed rating average. **¥3,000/month or ¥30,000/year**. | Full field-service CRM with routes, booking, quoting, invoicing and payment links. It is an overbuilt and expensive substitute for a one-person operator who only needs visit records and monthly invoices. |

### Complaint-derived requirements

1. **Dates and sites are real fields.** Never ask the operator to hide a date inside an item description. Each invoice line retains its work date and site.
2. **Several non-consecutive visits belong on one invoice.** The invoice builder accepts any historical period and manual selection, not only the current or previous month.
3. **The PDF is the product.** Long Japanese descriptions wrap and paginate; text never shrinks below a readable minimum merely to stay on one page.
4. **Preview and export are identical.** No blank final preview, missing content or different tax result after sharing.
5. **Drafts survive interruption.** A failed save, update, purchase or share action cannot trap the app in a loop or destroy the work ledger.
6. **Tax and rounding are explicit.** Each line supports 10%, 8% or 0%; the chosen rounding policy is visible and covered by fixed test cases. No automatic tax advice is claimed.
7. **No double billing.** An issued invoice snapshots its lines and atomically marks the source visits billed. Cancelled sharing does not consume an invoice allowance or change billing state.
8. **No mandatory account.** Version one works offline and local-first. The operator can export and restore the complete data archive.
9. **The paid gate never holds records hostage.** Work entries, previews, issued invoices and raw archive export remain accessible after cancellation of a purchase sheet or restoration problem.

## Customer and scope

### Primary launch customer

- A Japanese sole operator or very small service business.
- Typical work: cleaning, building maintenance, equipment servicing, repairs or repeat on-site support.
- Visits several sites or the same customer several times each month.
- Bills one customer at month-end and needs the recipient to see exactly when and where each service occurred.
- Does not need staff dispatch, payroll, accounting integration or online card collection.

### Explicitly excluded from version one

- Estimates and proposals.
- Scheduling, customer self-booking and route optimization.
- Team accounts, payroll and attendance.
- Payment processing, reminders sent from a server and bank reconciliation.
- FAX, postal fulfillment or e-signing.
- AI/OCR and receipt capture.
- Construction photos, job reports and public-works compliance.
- Cloud accounts or automatic sync.
- Tax or legal advice.

These exclusions are the differentiation. Existing products become unreliable or confusing when they attempt to cover every document and back-office workflow.

## Locked end-to-end process

| Step | Operator action | App action | Invariant / exception |
| --- | --- | --- | --- |
| 0. Business setup | Enter issuer name, address, optional qualified-invoice number, bank details, default tax and rounding. | Saves locally and shows a sample header. | Setup is editable from Settings; no separate account or onboarding wizard. Missing legally relevant fields are warned before issue, not fabricated. |
| 1. Create customer and sites | Add a customer and one or more service sites. | Remembers the customer's closing day, payment term and default service prices. | Customer and site are separate: one customer can have several locations. |
| 2. Record a completed visit | Tap **作業を記録**, choose customer/site/date, add service lines, quantity, unit, price, tax and an optional note. | Autosaves a recoverable draft, calculates the visit total deterministically and adds the visit to Unbilled. | Target: a routine repeat visit in under 30 seconds by copying the previous visit or using a service template. |
| 3. Review unbilled work | Open a customer/month group and inspect dates, sites and totals. | Shows unbilled, selected, billed and needs-attention states. | Historical months remain available. A billed source entry cannot silently re-enter another invoice. |
| 4. Build invoice | Select a customer, date range and individual unbilled visits. Reorder or exclude entries. | Groups lines by date then site, calculates site subtotals and tax totals, and warns about missing site/date/price/registration details. | Selection is not limited to adjacent days or the previous month. No source visit is changed by previewing. |
| 5. Inspect exact preview | Read the actual paginated PDF before issuing. | Uses the same rendering result for the on-screen preview and exported file. Long rows wrap; headers repeat; a line is never split illegibly. | A render or storage failure blocks issue and leaves the draft intact. |
| 6. Issue and share | Tap **発行して共有**. If free allowance is exhausted, buy or restore Pro first. | Creates an immutable invoice snapshot, assigns the number, marks included visits billed in one transaction, stores the PDF, then opens the iOS share sheet. | Cancelling the share sheet does not undo issue or consume an extra allowance. The stored PDF remains available for re-share. |
| 7. Track payment or correct | Mark paid, re-share, duplicate, void or correct through an explicit replacement flow. | Preserves the issued original and audit relation. Voiding can return visits to Unbilled only after explicit confirmation. | Never silently edit an issued invoice. No automatic bank status. |
| 8. Export or restore | Export all app data and PDFs, or restore a user-selected archive. | Validates the archive and reports conflicts before import. | Full user-data export is free and never depends on Pro. |

## Screen model

**Six custom screens with three persistent destinations.** Customer/site editing, tax selection, date-range selection, purchase and sharing are sheets or system surfaces, not additional navigation destinations.

### Persistent navigation

1. **作業 / Work — unbilled ledger**
   - First viewport: current month, customer groups, unbilled total and a prominent **作業を記録** action.
   - Each row shows date, site, short service description, amount and billing state.
   - Month and customer filters are compact; no dashboard cards, chart wall or calendar-first navigation.
   - Empty state creates the first customer/site and visit without a tutorial carousel.

2. **請求書 / Invoices — issued archive**
   - Sections: Draft, Issued/Unpaid, Paid and Voided.
   - Shows invoice number, customer, covered period, amount, state and last share date.
   - Re-share, mark paid and explicit correction/void actions live here.

3. **設定 / Settings & Data**
   - Issuer profile, qualified-invoice number, bank details, numbering, payment terms, tax/rounding, PDF style, service templates, backup/restore, Pro/restore purchase, privacy and help.
   - No promotional dashboard.

### Pushed workflow screens

4. **作業記録 / Visit Editor**
   - Customer, site and work date remain visible.
   - Repeating line editor: service, quantity, unit, unit price, tax and note.
   - Copy previous visit and reusable service templates reduce repeat entry.
   - Autosave indicator and recoverable draft state are explicit.

5. **請求内容 / Invoice Builder**
   - Customer and covered period at top; eligible unbilled visits below.
   - Default selection includes all eligible entries, with clear per-row date/site/amount.
   - Shows subtotal by site, tax by rate, total and any missing-field warnings.
   - One primary action: **PDFを確認**.

6. **プレビュー・発行 / PDF Preview & Issue**
   - True paginated preview at readable width, page count and included visit count.
   - Visible free/paid state and current StoreKit price.
   - Primary action: **発行して共有**; secondary: save draft/back.
   - The purchase sheet appears only after the user has inspected the final outcome.

## Data and calculation model

Core entities:

- `BusinessProfile`
- `Customer`
- `Site`
- `ServiceTemplate`
- `Visit`
- `VisitLine`
- `InvoiceDraft`
- `IssuedInvoiceSnapshot`
- `PaymentStatus`

Critical rules:

- Money uses integer yen or an explicit decimal-money type; never binary floating-point.
- A visit date is independent of creation timestamp.
- Issued invoice lines are immutable snapshots, not live references whose values change after a service template is edited.
- Invoice number assignment, snapshot write and source-visit billing state occur atomically.
- PDF layout is deterministic for the same snapshot.
- Tax rate, taxable basis, rounding mode and computed amount are stored on each issued snapshot.
- Backup includes originals, current records, invoices, PDFs, entitlement-neutral data and schema version.

## Monetization decision

### Model

**Free app with one non-consumable lifetime Pro unlock. No subscription, ads or account.**

The app has no recurring server cost in version one. A subscription would imitate heavier competitors without providing an ongoing hosted service. Ads would undermine trust at the moment a business document is created.

### Free boundary

- One business profile.
- Up to two active customers and their sites.
- Unlimited visit records for those customers.
- Unlimited invoice building and exact watermarked previews.
- **One client-ready invoice may be issued and exported without a watermark.**
- Existing work records, the issued invoice and complete raw backup/export remain accessible forever.

### Paid boundary

Pro unlocks:

- Unlimited active customers.
- Unlimited clean invoice issue/export.
- Reusable service templates and copy-previous shortcuts.
- Customer closing-day presets and saved payment terms.
- Logo and selectable restrained PDF styles.
- All future versions of the local single-user workflow.

The gate appears when the user taps **発行して共有** for the second client-ready invoice, or tries to add a third active customer. It does not appear during recording, editing, previewing, backup, restore or access to already-created data.

### Locked Japan launch price

**¥2,000 one time.**

Rationale:

- Matches 親方帳's current one-time ¥2,000 anchor.
- Sits above the tiny-rating construction-only 出面帳＆請求書 at ¥1,500 because the product includes a safer invoice-state engine, one genuine free invoice and service-business positioning.
- Undercuts Estilynx's proven ¥2,500 paid-app price.
- Costs less than four months of Jimuu plus its consolidated-invoice option (¥600/month), about two months of Site Billing (¥980/month), and far less than the ¥3,000/month international field-service tools.
- Preserves a credible business-tool price without pretending that the current evidence supports ¥3,500.

Do not launch at ¥900 merely to match the cheapest generic buyout. The job is more specific and the reliability burden is higher. Do not hard-code `¥2,000` in the binary; show StoreKit's localized live price. If Apple does not offer that exact Japan price point at setup, use the closest price point at or below ¥2,000 rather than moving above ¥2,500 without new evidence.

## Release and test gates

The build is not ready for listing until it passes all of these:

1. A 100-visit customer across non-consecutive dates produces one correct invoice in under one minute after the work is recorded.
2. Historical visits from any prior month can be selected.
3. Long Japanese service descriptions wrap across pages without shrinking below the chosen minimum print size.
4. Preview and exported PDF match byte-for-rendering inputs and visible totals.
5. 0%, 8% and 10% tax lines plus each supported rounding mode pass fixed calculation fixtures reviewed against current official Japanese requirements.
6. Force-quit during visit edit, invoice build, purchase, issue and share does not lose or double-bill data.
7. Cancelling a share sheet does not consume an invoice allowance or create a duplicate invoice.
8. Purchase cancellation, interruption and restoration preserve every record and the free invoice entitlement correctly.
9. Full archive export and restore work on a clean device build.
10. No login, network connection, photo permission, tracking or server is required for the promised flow.

## Final build order

1. Deterministic money, tax, rounding and invoice-number engine.
2. Visit/unbilled/issued state machine with crash-safe persistence and immutable snapshots.
3. PDF renderer with pagination and legibility tests.
4. Backup/restore and transaction-recovery tests.
5. Six-screen native shell.
6. StoreKit gate and entitlement recovery.
7. Japanese fixtures, smallest-iPhone QA, iPad decision, accessibility and final listing assets.

**Final decision:** proceed. The launch succeeds only if it remains the fastest and safest path from **several completed service visits** to **one dated monthly invoice**. Every feature that does not strengthen that path is out of scope for version one.
