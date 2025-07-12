{{
  config(
    materialized='view',
    schema='staging'
  )
}}

/*
Staging model para campanhas do Facebook Ads
IMPORTANTE: Facebook Ads NÃO fornece dados de leads, apenas campanhas
*/

WITH facebook_campaigns_raw AS (
  SELECT *
  FROM {{ source('bronze', 'facebook_ads_campaigns') }}
  WHERE _load_date >= '{{ var("start_date") }}'
),

campaigns_cleaned AS (
  SELECT
    -- Identificadores únicos
    id AS campaign_id,
    account_id,
    
    -- Dados da campanha
    name AS campaign_name,
    objective,
    status,
    
    -- Timestamps
    CAST(created_time AS TIMESTAMP) AS created_timestamp,
    CAST(updated_time AS TIMESTAMP) AS updated_timestamp,
    CAST(start_time AS TIMESTAMP) AS start_timestamp,
    CAST(stop_time AS TIMESTAMP) AS stop_timestamp,
    
    -- Budget
    CAST(daily_budget AS DECIMAL(15,2)) / 100 AS daily_budget_brl,
    CAST(lifetime_budget AS DECIMAL(15,2)) / 100 AS lifetime_budget_brl,
    CAST(budget_remaining AS DECIMAL(15,2)) / 100 AS budget_remaining_brl,
    
    -- Metadados
    CAST(_extraction_timestamp AS TIMESTAMP) AS extraction_timestamp,
    _source_system AS source_system,
    _load_date AS load_date
    
  FROM facebook_campaigns_raw
),

campaigns_with_insights AS (
  SELECT
    c.*,
    
    -- Buscar insights da campanha (se disponível)
    i.impressions,
    i.clicks,
    i.spend,
    i.reach,
    i.frequency,
    i.cpm,
    i.cpc,
    i.ctr,
    i.date_start AS insight_date_start,
    i.date_stop AS insight_date_stop
    
  FROM campaigns_cleaned c
  LEFT JOIN {{ source('bronze', 'facebook_ads_campaign_insights') }} i
    ON c.campaign_id = i.campaign_id
    AND i._load_date >= '{{ var("start_date") }}'
),

final_staging AS (
  SELECT
    -- Identificadores
    campaign_id,
    account_id,
    
    -- Dados da campanha
    campaign_name,
    objective,
    status,
    
    -- Timestamps
    created_timestamp,
    updated_timestamp,
    start_timestamp,
    stop_timestamp,
    
    -- Budget
    daily_budget_brl,
    lifetime_budget_brl,
    budget_remaining_brl,
    
    -- Métricas (agregadas se múltiplos insights)
    SUM(COALESCE(impressions, 0)) AS total_impressions,
    SUM(COALESCE(clicks, 0)) AS total_clicks,
    SUM(COALESCE(spend, 0)) AS total_spend_brl,
    SUM(COALESCE(reach, 0)) AS total_reach,
    AVG(COALESCE(frequency, 0)) AS avg_frequency,
    AVG(COALESCE(cpm, 0)) AS avg_cpm,
    AVG(COALESCE(cpc, 0)) AS avg_cpc,
    AVG(COALESCE(ctr, 0)) AS avg_ctr,
    
    -- Campos para Data Vault
    'facebook_ads' AS origem,
    CONCAT('facebook_ads_', account_id) AS record_source,
    
    -- Metadados
    extraction_timestamp,
    load_date,
    
    -- Validações
    CASE 
      WHEN campaign_name IS NOT NULL AND campaign_id IS NOT NULL 
      THEN TRUE 
      ELSE FALSE 
    END AS is_valid_campaign,
    
    CASE 
      WHEN status = 'ACTIVE' 
      THEN TRUE 
      ELSE FALSE 
    END AS is_active,
    
    CASE 
      WHEN total_impressions > 0 OR total_clicks > 0 OR total_spend_brl > 0 
      THEN TRUE 
      ELSE FALSE 
    END AS has_activity,
    
    -- Categorização de performance
    CASE 
      WHEN avg_ctr >= 2.0 THEN 'Alto'
      WHEN avg_ctr >= 1.0 THEN 'Médio'
      WHEN avg_ctr > 0 THEN 'Baixo'
      ELSE 'Sem Dados'
    END AS performance_ctr,
    
    CASE 
      WHEN avg_cpc <= 2.0 THEN 'Baixo Custo'
      WHEN avg_cpc <= 5.0 THEN 'Custo Médio'
      ELSE 'Alto Custo'
    END AS categoria_custo
    
  FROM campaigns_with_insights
  GROUP BY 
    campaign_id, account_id, campaign_name, objective, status,
    created_timestamp, updated_timestamp, start_timestamp, stop_timestamp,
    daily_budget_brl, lifetime_budget_brl, budget_remaining_brl,
    extraction_timestamp, load_date
)

SELECT * FROM final_staging
WHERE is_valid_campaign = TRUE

