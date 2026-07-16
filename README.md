# Multistate Sales & Use Tax Reconciliation

A SQL + Python reconciliation engine that takes a raw payment-processor transaction export and answers the question every controller asks at close: **did we charge the right tax, and did we pay it to the right state?**

It performs a three-way reconciliation — **expected tax** (deduplicated sales × reference rates) vs **collected tax** (what the processor actually charged) vs **remitted tax** (what was actually filed and paid) — and flags every discrepancy with its dollar impact.

Built as a companion to my [FP&A Variance Analyzer](https://github.com/alexsorrell1/fpa-variance-analyzer): that project explains P&L variances; this one protects the balance sheet. Together they cover both sides of a month-end close.

## Why this project

At a multistate DTC company I found recurring sales tax discrepancies, isolated them to third-party processor errors, validated balances against state confirmations, and posted the corrections. This repo generalizes that workflow into a repeatable, reviewable tool. The sample data intentionally contains the four error types I've seen in the wild:

| Flag | What it means | Root cause simulated |
|---|---|---|
| `DUPLICATE_POSTING` | Same transaction posted twice | Processor re-posted a settlement batch |
| `RATE_MISMATCH` | Tax charged at the wrong rate | State-only rate applied, local/district taxes dropped |
| `MISSING_TAX` | Taxable order, zero tax charged | Nexus misconfiguration after a system update |
| Remittance gap | Collected ≠ filed/paid | Short filing in one state-period |

Marketplace-facilitator sales are excluded from company liability, since the facilitator remits tax on those orders.

## What it produces

Running one command generates three deliverables in `output/`:

1. **`tax_reconciliation_report.xlsx`** — color-coded workbook: state-by-month three-way reconciliation with REVIEW flags beyond a $25 materiality threshold, plus a transaction-level Exception Detail tab
2. **`tax_reconciliation_charts.png`** — collection variance by state and the monthly variance trend
3. **`executive_summary.txt`** — auto-written narrative: total exposure, findings with root causes, and recommended actions

Finished examples are in [`sample_outputs/`](sample_outputs/) so you can see the results without running anything.

## The SQL

All reconciliation logic lives in plain, commented SQL in [`sql/`](sql/) — the Python only orchestrates and formats:

- `01_create_tables.sql` — schema for transactions, rates, and remittances
- `02_detect_exceptions.sql` — CTE pipeline with a `ROW_NUMBER()` window function for duplicate detection and CASE-based exception classification
- `03_reconcile_remittances.sql` — state-month three-way reconciliation with a `SUM() OVER` running total for cumulative exposure

Techniques used: multi-step CTEs, window functions (`ROW_NUMBER`, running totals), joins, `LEFT JOIN` gap detection, aggregation, and materiality thresholds.

## How to run it

Requires Python 3.9+.

```bash
pip install -r requirements.txt
python tax_reconciler.py
```

Expected console output:

```
Multistate Sales & Use Tax Reconciliation
---------------------------------------------
1/5  Data loaded into SQLite
2/5  SQL reconciliation complete: 374 rows analyzed, 103 exceptions flagged
3/5  Excel report written: tax_reconciliation_report.xlsx
4/5  Charts written: tax_reconciliation_charts.png
5/5  Executive summary written: executive_summary.txt
---------------------------------------------
Total estimated exposure: $2,181.11
```

## Using your own data

Replace the three CSVs in `data/` and keep the same columns:

- `transactions.csv`: `transaction_id, order_date, month, state, channel, taxable_sales, tax_collected, processor_batch_id`
- `tax_rates.csv`: `state, combined_rate, notes`
- `remittances.csv`: `state, month, tax_remitted, filing_reference`

`month` values must sort chronologically (`YYYY-MM`). `channel` must be `website` or `marketplace`.

## Project structure

```
sales-tax-reconciliation/
├── tax_reconciler.py        # orchestration, Excel/chart/summary generation
├── requirements.txt
├── sql/                     # all reconciliation logic, reviewable on its own
│   ├── 01_create_tables.sql
│   ├── 02_detect_exceptions.sql
│   └── 03_reconcile_remittances.sql
├── data/                    # sample inputs with seeded, documented errors
│   ├── transactions.csv
│   ├── tax_rates.csv
│   └── remittances.csv
└── sample_outputs/          # what the tool produces
```

## Disclaimer

Sample data and tax rates are illustrative and simplified for demonstration. This tool is a reconciliation aid, not tax advice; filing positions should always be validated against current state rules.
