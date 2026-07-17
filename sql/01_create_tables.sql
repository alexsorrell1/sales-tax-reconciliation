-- ============================================================
-- 01_create_tables.sql
-- Schema for the multistate sales & use tax reconciliation.
-- Three tables mirror the three source files an accountant
-- actually works from: the processor transaction export, the
-- rate reference table, and the remittance (filing) history.
-- ============================================================

DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS tax_rates;
DROP TABLE IF EXISTS remittances;

-- Raw transaction export from the payment processor.
-- Deliberately NOT deduplicated: real processor exports contain
-- duplicate postings, and the reconciliation must catch them.
CREATE TABLE transactions (
    transaction_id      TEXT NOT NULL,   -- processor's ID (repeats on duplicate postings)
    order_date          TEXT NOT NULL,   -- YYYY-MM-DD
    month               TEXT NOT NULL,   -- YYYY-MM filing period
    state               TEXT NOT NULL,   -- two-letter state code
    channel             TEXT NOT NULL,   -- 'website' (we remit) or 'marketplace' (facilitator remits)
    taxable_sales       REAL NOT NULL,   -- taxable amount of the order
    tax_collected       REAL NOT NULL,   -- tax the processor actually charged
    processor_batch_id  TEXT NOT NULL    -- settlement batch the row arrived in
);

-- Reference rates by state (illustrative combined rates for the demo).
CREATE TABLE tax_rates (
    state          TEXT PRIMARY KEY,
    combined_rate  REAL NOT NULL,
    notes          TEXT
);

-- What was actually filed and paid to each state, by period.
CREATE TABLE remittances (
    state             TEXT NOT NULL,
    month             TEXT NOT NULL,
    tax_remitted      REAL NOT NULL,
    filing_reference  TEXT,
    PRIMARY KEY (state, month)
);
