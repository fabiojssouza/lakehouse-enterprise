{{
  config(
    materialized='view',
    schema='staging'
  )
}}

/*
Staging model para campanhas do Google Ads
IMPORTANTE: Google Ads NÃO fornece dados de leads, apenas campanhas
*/

WITH google_campaigns_raw AS (
  SELECT *
  FROM {{ source('bronze', 'google_ads_campaigns') }}
  WHERE _load_date >= '{{ var("start_date") }}'
),

campaigns_cleaned AS (
  SELECT
    -- Identificadores únicos
    customer_id,
    campaign_id,
    ad_group_id,
    
    -- Dados da campanha
    campaign_name,
    ad_group_name,
    keyword,
    match_type,
    
    -- Métricas
    CAST(impressions AS BIGINT) AS impressions,
    CAST(clicks AS BIGINT) AS clicks,
    CAST(cost_micros AS BIGINT) AS cost_micros,
    CAST(conversions AS DECIMAL(10,2)) AS conversions,
    CAST(conversion_value AS DECIMAL(10,2)) AS conversion_value,
    
    -- Timestamps
    CAST(date AS DATE) AS campaign_date,
    CAST(_extraction_timestamp AS TIMESTAMP) AS extraction_timestamp,
    
    -- Metadados
    _source_system AS source_system,
    _load_date AS load_date
    
  FROM google_campaigns_raw
),

campaigns_aggregated AS (
  SELECT
    -- Identificadores (agregado por campanha)
    customer_id,
    campaign_id,
    campaign_name,
    
    -- Métricas agregadas
    SUM(impressions) AS total_impressions,
    SUM(clicks) AS total_clicks,
    SUM(cost_micros) AS total_cost_micros,
    SUM(conversions) AS total_conversions,
    SUM(conversion_value) AS total_conversion_value,
    
    -- Métricas calculadas
    CASE 
      WHEN SUM(clicks) > 0 THEN SUM(cost_micros) / 1000000.0 / SUM(clicks)
      ELSE 0 
    END AS avg_cpc,
    
    CASE 
      WHEN SUM(impressions) > 0 THEN SUM(clicks) * 100.0 / SUM(impressions)
      ELSE 0 
    END AS avg_ctr,
    
    -- Período
    MIN(campaign_date) AS start_date,
    MAX(campaign_date) AS end_date,
    COUNT(DISTINCT campaign_date) AS days_active,
    
    -- Metadados
    MAX(extraction_timestamp) AS extraction_timestamp,
    MAX(load_date) AS load_date
    
  FROM campaigns_cleaned
  GROUP BY customer_id, campaign_id, campaign_name
),

final_staging AS (
  SELECT
    -- Identificadores
    customer_id,
    campaign_id,
    campaign_name,
    
    -- Métricas principais
    total_impressions,
    total_clicks,
    total_cost_micros,
    CAST(total_cost_micros AS DECIMAL(15,2)) / 1000000 AS total_cost_brl,
    total_conversions,
    total_conversion_value,
    
    -- Métricas calculadas
    avg_cpc,
    avg_ctr,
    
    -- Período
    start_date,
    end_date,
    days_active,
    
    -- Timestamps
    extraction_timestamp,
    load_date,
    
    -- Campos para Data Vault
    'google_ads' AS origem,
    CONCAT('google_ads_', customer_id) AS record_source,
    
    -- Validações
    CASE 
      WHEN total_impressions > 0 OR total_clicks > 0 OR total_cost_micros > 0 
      THEN TRUE 
      ELSE FALSE 
    END AS has_activity,
    
    -- Categorização de performance
    CASE 
      WHEN avg_ctr >= 2.0 THEN 'Alto'
      WHEN avg_ctr >= 1.0 THEN 'Médio'
      WHEN avg_ctr > 0 THEN 'Baixo'
      ELSE 'Sem Dados'
    END AS performance_categoria,
    
    -- ROI
    CASE 
      WHEN total_cost_brl > 0 THEN (total_conversion_value - total_cost_brl) / total_cost_brl * 100
      ELSE 0
    END AS roi_percent
    
  FROM campaigns_aggregated
)

SELECT * FROM final_staging
WHERE has_activity = TRUE

