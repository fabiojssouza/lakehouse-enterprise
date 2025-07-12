{{
  config(
    materialized='incremental',
    unique_key='produtor_hash_key',
    table_type='iceberg',
    incremental_strategy='merge',
    schema='raw_vault'
  )
}}

/*
Hub Produtor - Raw Vault
Entidade para produtores extraídos dos dados do CRM
*/

WITH activecampaign_data AS (
  SELECT
    -- Extrair produtor de tags ou campos customizados
    CASE 
      WHEN tags LIKE '%produtor_%' THEN 
        REGEXP_EXTRACT(tags, 'produtor_([a-zA-Z0-9_]+)', 1)
      WHEN lead_source IS NOT NULL THEN 
        lead_source
      WHEN utm_source IS NOT NULL THEN 
        utm_source
      ELSE 'unknown'
    END AS produtor_identificado,
    
    -- Metadados
    load_date,
    record_source
    
  FROM {{ ref('stg_activecampaign_contacts') }}
  
  {% if is_incremental() %}
    WHERE load_date > (SELECT MAX(load_date) FROM {{ this }})
  {% endif %}
),

produtores_identificados AS (
  SELECT DISTINCT
    produtor_identificado
  FROM activecampaign_data
  WHERE produtor_identificado IS NOT NULL 
    AND produtor_identificado != ''
    AND produtor_identificado != 'unknown'
),

produtores_with_hash AS (
  SELECT
    -- Gerar hash key para produtor
    MD5(UPPER(TRIM(produtor_identificado))) AS produtor_hash_key,
    
    -- Dados originais
    produtor_identificado,
    
    -- Metadados (usar data atual para novos produtores)
    CURRENT_TIMESTAMP AS load_date,
    'activecampaign' AS record_source
    
  FROM produtores_identificados
),

hub_produtor AS (
  SELECT DISTINCT
    produtor_hash_key,
    load_date,
    record_source
    
  FROM produtores_with_hash
)

SELECT * FROM hub_produtor

