# Ledgerline — Personal Finance Dashboard

A single-page personal finance dashboard built from bank statement CSVs. Everything runs in the browser; statement files are parsed locally and never uploaded.

## Features

- **Upload** — drag-and-drop CSV import with a 10-row preview, per-column mapping (Date / Description / Debit / Credit / Balance / Amount) with automatic best-guess, and a simulated parsing progress state.
- **Dashboard** — date-range filter, monthly income vs expense, spend by category, top 10 merchants, and month-on-month spend trend.
- **Transactions** — sortable, filterable (month, category, amount range), paginated table with inline category editing that creates a merchant rule.
- **Anomalies** — flags payments at 3× their category average and high first-time payments to new merchants.
- **Rules** — view, add and delete pattern → category rules.

Opens with a sample statement (Jan–Sep 2026) so every screen has data before you import your own.

## Run locally

No build step or dependencies. On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File serve.ps1
```

Then open http://localhost:8080. Use `-Port 3000` to pick another port.

Any static server works too, e.g. `npx serve .` or `python -m http.server 8080`, or just open `index.html` directly.

Charts use Chart.js from cdnjs, so an internet connection is needed for them to render.

## Notes

- Amounts are formatted in Indian rupees (₹); change the `INR` formatter near the top of the script in `index.html` to switch currency.
- Imported data, category edits and rules live in memory and reset on reload.
