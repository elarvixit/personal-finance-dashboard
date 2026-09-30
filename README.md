# Ledgerline — Personal Finance Dashboard

A single-page personal finance dashboard built from bank statement CSVs. Everything runs in the browser; statement files are parsed locally and never uploaded.

## Features

- **Upload** — drag-and-drop CSV import with a 10-row preview, per-column mapping (Date / Description / Debit / Credit / Balance / Amount) with automatic best-guess, and a simulated parsing progress state.
- **Dashboard** — date-range filter, monthly income vs expense, spend by category, top 10 merchants, and month-on-month spend trend.
- **Transactions** — sortable, filterable (month, category, amount range), paginated table with inline category editing that creates a merchant rule.
- **Anomalies** — flags payments at 3× their category average and high first-time payments to new merchants.
- **Rules** — view, add and delete pattern → category rules.

Opens with a sample statement (Jan–Sep 2026) so every screen has data before you import your own.

## Supabase backend

Signed-out visitors get the sample statement, with nothing saved. After signing in (Supabase Auth, email and password), statements, transactions, category edits, rules and "Mark as expected" reviews are saved to Supabase. Row-level security makes every row visible only to its owner.

### 1. Create the tables

In Supabase: **SQL Editor → New query**, paste the contents of [`supabase/schema.sql`](supabase/schema.sql), and click **Run**. It is safe to run again.

| Table | Holds |
| --- | --- |
| `vidhya_personal_finance_dashboard_profiles` | One row per user; set up on first sign-in |
| `vidhya_personal_finance_dashboard_statements` | One row per imported CSV |
| `vidhya_personal_finance_dashboard_transactions` | Transactions, linked to their statement |
| `vidhya_personal_finance_dashboard_category_rules` | Pattern → category rules |
| `vidhya_personal_finance_dashboard_anomaly_reviews` | Flagged payments marked as expected |

It also creates two functions the app calls: `vidhya_personal_finance_dashboard_init_user` (adds default rules on first sign-in) and `vidhya_personal_finance_dashboard_import_statement` (saves a statement and all its rows in one transaction).

### 2. Configure Auth URLs

**Authentication → URL Configuration**:
- **Site URL**: your Vercel URL, e.g. `https://personal-finance-dashboard-eight-rho.vercel.app`
- **Redirect URLs**: add the Vercel URL and `http://localhost:8080`

Confirmation emails link back to these addresses.

### 3. Environment variables

From **Project Settings → API** (or **Connect**):

| Variable | Value |
| --- | --- |
| `SUPABASE_URL` | Project URL, e.g. `https://abcd1234.supabase.co` |
| `SUPABASE_ANON_KEY` | The **anon / publishable** public key. Never the `service_role` / secret key. |

- **Vercel**: Project → Settings → Environment Variables, add both, then redeploy. [`api/config.js`](api/config.js) serves them to the page at `/api/config`.
- **Localhost**: copy `.env.example` to `.env.local` and fill it in. `serve.ps1` reads it on every request. `.env.local` is git-ignored.

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
