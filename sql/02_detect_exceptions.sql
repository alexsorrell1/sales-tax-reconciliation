-- ============================================================
-- 02_detect_exceptions.sql
-- Transaction-level exception detection.
--
-- Techniques on display:
--   * CTE pipeline (ranked -> deduped -> enriched -> flagged)
--   * ROW_NUMBER() window function for duplicate detection
--   * CASE-based exception classification
--
-- Exception flags produced:
--   DUPLICATE_POSTING        same transaction_id posted more than once
--   MISSING_TAX              taxable order where zero tax was charged
--   RATE_MISMATCH            tax charged at the wrong rate (> $0.02 off)
--   MARKETPLACE_FACILITATOR  facilitator remits; excluded from our liability
--   OK                       clean row
--
-- variance_impact column (dollars):
--   MISSING_TAX / RATE_MISMATCH -> collected minus expected (negative = undercollected)
--   DUPLICATE_POSTING           -> tax double-counted in the processor gross report
--   MARKETPLACE / OK            -> informational, 0.00
-- ============================================================

WITH ranked AS (
    -- Number every posting of the same transaction_id. The first
    -- posting (by batch id) is the keeper; any later one is a duplicate.
    SELECT
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY t.transaction_id
            ORDER BY t.processor_batch_id
        ) AS posting_number
    FROM transactions AS t
),

deduped AS (
    SELECT * FROM ranked WHERE posting_number = 1
),

enriched AS (
    -- Attach the reference rate and compute what SHOULD have been charged.
    SELECT
        d.*,
        r.combined_rate,
        ROUND(d.taxable_sales * r.combined_rate, 2) AS expected_tax
    FROM deduped AS d
    JOIN tax_rates AS r
        ON r.state = d.state
),

flagged AS (
    SELECT
        e.*,
        ROUND(e.tax_collected - e.expected_tax, 2) AS collection_variance,
        CASE
            WHEN e.channel = 'marketplace'
                THEN 'MARKETPLACE_FACILITATOR'
            WHEN e.tax_collected = 0 AND e.expected_tax > 0
                THEN 'MISSING_TAX'
            WHEN ABS(e.tax_collected - e.expected_tax) > 0.02
                THEN 'RATE_MISMATCH'
            ELSE 'OK'
        END AS exception_flag
    FROM enriched AS e
)

SELECT
    transaction_id,
    order_date,
    month,
    state,
    channel,
    taxable_sales,
    tax_collected,
    expected_tax,
    collection_variance,
    exception_flag,
    CASE
        WHEN exception_flag IN ('MISSING_TAX', 'RATE_MISMATCH')
            THEN collection_variance
        ELSE 0.00
    END AS variance_impact
FROM flagged

UNION ALL

-- Duplicate postings, pulled from the ranked CTE (posting_number > 1).
-- Their impact is the full tax amount double-counted in the gross report.
SELECT
    transaction_id,
    order_date,
    month,
    state,
    channel,
    taxable_sales,
    tax_collected,
    NULL              AS expected_tax,
    NULL              AS collection_variance,
    'DUPLICATE_POSTING' AS exception_flag,
    tax_collected     AS variance_impact
FROM ranked
WHERE posting_number > 1

ORDER BY month, state, transaction_id;
