{{
  config(
    materialized='incremental',
    unique_key='campanha_hash_key',
    table_type='iceberg',
    incremental_strategy='merge',
    schema='raw_vault'
  )
}}

/*
Hub Campanha - Raw Vault
Entidade para campanhas vindas do Facebook Ads e Google Ads
*/

WITH facebook_campaigns AS (
  SELECT
    campaign_id,
    'facebook_ads' AS platform,
    record_source,
    load_date
  FROM {{ ref('stg_facebook_campaigns') }}
  
  {% if is_incremental() %}
    WHERE load_date > (SELECT MAX(load_date) FROM {{ this }})
  {% endif %}
),

google_campaigns AS (
  SELECT
    campaign_id,
    'google_ads' AS platform,
    record_source,
    load_date
  FROM {{ ref('stg_google_campaigns') }}
  
  {% if is_incremental() %}
    WHERE load_date > (SELECT MAX(load_date) FROM {{ this }})
  {% endif %}
),

all_campaigns AS (
  SELECT * FROM facebook_campaigns
  UNION ALL
  SELECT * FROM google_campaigns
),

campaigns_with_hash AS (
  SELECT
    -- Gerar hash key único por campanha + plataforma
    MD5(CONCAT(campaign_id, '|', platform)) AS campanha_hash_key,
    
    -- Dados originais
    campaign_id,
    platform,
    
    -- Metadados
    load_date,
    record_source
    
  FROM all_campaigns
),

hub_campanha AS (
  SELECT DISTINCT
    campanha_hash_key,
    load_date,
    record_source
    
  FROM campaigns_with_hash
)

SELECT * FROM hub_campanha

