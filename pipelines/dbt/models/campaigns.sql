{{
  config(
    materialized='table',
    file_format='parquet'
  )
}}

-- Modelo unificado de campanhas
-- Consolida dados de campanhas de Facebook Ads, Google Ads e outras fontes

WITH facebook_campaigns AS (
    SELECT
        campaign_id,
        campaign_name AS nome,
        'facebook_ads' AS plataforma,
        objective AS objetivo,
        status,
        created_time,
        updated_time,
        start_time,
        stop_time,
        daily_budget,
        lifetime_budget,
        budget_remaining,
        account_id,
        'facebook' AS fonte
    FROM {{ source('bronze', 'facebook_campaigns') }}
),

google_campaigns AS (
    SELECT
        campaign_id,
        campaign_name AS nome,
        'google_ads' AS plataforma,
        campaign_type AS objetivo,
        status,
        created_time,
        updated_time,
        start_date AS start_time,
        end_date AS stop_time,
        daily_budget,
        total_budget AS lifetime_budget,
        remaining_budget AS budget_remaining,
        account_id,
        'google' AS fonte
    FROM {{ source('bronze', 'google_campaigns') }}
),

unified_campaigns AS (
    SELECT * FROM facebook_campaigns
    UNION ALL
    SELECT * FROM google_campaigns
),

campaign_metrics AS (
    SELECT
        c.*,
        COALESCE(m.impressions, 0) AS impressions,
        COALESCE(m.clicks, 0) AS clicks,
        COALESCE(m.spend, 0) AS spend,
        COALESCE(m.reach, 0) AS reach,
        COALESCE(m.frequency, 0) AS frequency,
        COALESCE(m.cpm, 0) AS cpm,
        COALESCE(m.cpc, 0) AS cpc,
        COALESCE(m.ctr, 0) AS ctr,
        
        -- Métricas calculadas
        CASE 
            WHEN m.clicks > 0 THEN m.spend / m.clicks 
            ELSE 0 
        END AS custo_por_click_calculado,
        
        CASE 
            WHEN m.impressions > 0 THEN (m.clicks * 100.0) / m.impressions 
            ELSE 0 
        END AS ctr_calculado,
        
        CASE 
            WHEN m.impressions > 0 THEN (m.spend * 1000.0) / m.impressions 
            ELSE 0 
        END AS cpm_calculado,
        
        -- Classificação de performance
        CASE
            WHEN m.ctr >= 2.0 THEN 'Alto'
            WHEN m.ctr >= 1.0 THEN 'Médio'
            WHEN m.ctr > 0 THEN 'Baixo'
            ELSE 'Sem dados'
        END AS performance_ctr,
        
        CASE
            WHEN m.cpc <= 1.0 THEN 'Baixo'
            WHEN m.cpc <= 3.0 THEN 'Médio'
            WHEN m.cpc > 3.0 THEN 'Alto'
            ELSE 'Sem dados'
        END AS categoria_cpc,
        
        -- Flags de status
        CASE 
            WHEN UPPER(c.status) IN ('ACTIVE', 'ENABLED') THEN 1 
            ELSE 0 
        END AS is_active,
        
        CASE 
            WHEN c.stop_time IS NOT NULL AND c.stop_time < CURRENT_DATE THEN 1 
            ELSE 0 
        END AS is_expired,
        
        CASE 
            WHEN c.budget_remaining IS NOT NULL AND c.budget_remaining <= 0 THEN 1 
            ELSE 0 
        END AS is_budget_exhausted,
        
        CURRENT_TIMESTAMP AS dbt_updated_at,
        '{{ var("dbt_run_id", "unknown") }}' AS dbt_run_id
        
    FROM unified_campaigns c
    LEFT JOIN {{ ref('campaign_insights_aggregated') }} m
        ON c.campaign_id = m.campaign_id 
        AND c.plataforma = m.plataforma
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['campaign_id', 'plataforma']) }} AS campaign_key,
    *
FROM campaign_metrics

