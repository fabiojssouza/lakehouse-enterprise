{{
  config(
    materialized='incremental',
    unique_key='pessoa_produtor_hash_key',
    table_type='iceberg',
    incremental_strategy='merge',
    schema='raw_vault'
  )
}}

/*
Link Pessoa-Produtor - Raw Vault
Relaciona pessoas com produtores baseado em dados do CRM
*/

WITH activecampaign_data AS (
  SELECT
    -- Hash da pessoa
    {{ generate_unified_person_hash('email', 'telefone', 'nome') }} AS pessoa_hash_key,
    
    -- Identificar produtor
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
  WHERE {{ generate_unified_person_hash('email', 'telefone', 'nome') }} IS NOT NULL
  
  {% if is_incremental() %}
    AND load_date > (SELECT MAX(load_date) FROM {{ this }})
  {% endif %}
),

with_produtor_hash AS (
  SELECT
    pessoa_hash_key,
    MD5(UPPER(TRIM(produtor_identificado))) AS produtor_hash_key,
    produtor_identificado,
    load_date,
    record_source
    
  FROM activecampaign_data
  WHERE produtor_identificado IS NOT NULL 
    AND produtor_identificado != ''
    AND produtor_identificado != 'unknown'
),

link_pessoa_produtor AS (
  SELECT
    -- Hash key do link
    MD5(CONCAT(pessoa_hash_key, '|', produtor_hash_key)) AS pessoa_produtor_hash_key,
    
    -- Foreign keys
    pessoa_hash_key,
    produtor_hash_key,
    
    -- Metadados
    load_date,
    record_source
    
  FROM with_produtor_hash
)

SELECT DISTINCT * FROM link_pessoa_produtor

