-- ============================================================
-- 03_reconcile_remittances.sql
-- State-by-month three-way reconciliation:
--
--   expected tax   (deduped direct sales x reference rate)
--     vs collected (what the processor actually charged)
--     vs remitted  (what was actually filed and paid)
--
-- Marketplace sales are excluded: the facilitator remits those.
--
-- Techniques on display:
--   * multi-step CTE pipeline
--   * ROW_NUMBER() dedup reused as a subquery pattern
--   * LEFT JOIN to catch periods with no filing on record
--   * SUM() OVER (...) running-total window for cumulative exposure
-- ============================================================

WITH deduped AS (
    SELECT *
    FROM (
        SELECT
            t.*,
            ROW_NUMBER() OVER (
                PARTITION BY t.transaction_id
                ORDER BY t.processor_batch_id
            ) AS posting_number
        FROM transactions AS t
    )
    WHERE posting_number = 1
),

direct_with_expected AS (
    -- Only 'website' (direct) sales create OUR remittance obligation.
    SELECT
        d.state,
        d.month,
        d.taxable_sales,
        d.tax_collected,
        ROUND(d.taxable_sales * r.combined_rate, 2) AS expected_tax
    FROM deduped AS d
    JOIN tax_rates AS r
        ON r.state = d.state
    WHERE d.channel = 'website'
),

by_state_month AS (
    SELECT
        state,
        month,
        COUNT(*)                       AS direct_orders,
        ROUND(SUM(taxable_sales), 2)   AS taxable_sales,
        ROUND(SUM(expected_tax), 2)    AS expected_tax,
        ROUND(SUM(tax_collected), 2)   AS tax_collected
    FROM direct_with_expected
    GROUP BY state, month
),

recon AS (
    SELECT
        b.state,
        b.month,
        b.direct_orders,
        b.taxable_sales,
        b.expected_tax,
        b.tax_collected,
        COALESCE(m.tax_remitted, 0)                            AS tax_remitted,
        ROUND(b.tax_collected - b.expected_tax, 2)             AS collection_variance,
        ROUND(COALESCE(m.tax_remitted, 0) - b.tax_collected, 2) AS remittance_variance
    FROM by_state_month AS b
    LEFT JOIN remittances AS m
        ON  m.state = b.state
        AND m.month = b.month
)

SELECT
    state,
    month,
    direct_orders,
    taxable_sales,
    expected_tax,
    tax_collected,
    tax_remitted,
    collection_variance,
    remittance_variance,
    ROUND(SUM(collection_variance) OVER (
        PARTITION BY state
        ORDER BY month
    ), 2) AS cumulative_collection_variance,
    CASE
        WHEN ABS(collection_variance) > 25 OR ABS(remittance_variance) > 25
            THEN 'REVIEW'
        ELSE 'OK'
    END AS status
FROM recon
ORDER BY month, state;
