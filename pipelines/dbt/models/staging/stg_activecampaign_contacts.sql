{{
  config(
    materialized='view',
    schema='staging'
  )
}}

/*
Staging model para contatos do ActiveCampaign
Responsável por limpar e padronizar dados brutos da camada Bronze
*/

WITH activecampaign_raw AS (
  SELECT *
  FROM {{ source('bronze', 'activecampaign_contacts') }}
  WHERE _load_date >= '{{ var("start_date") }}'
),

contacts_cleaned AS (
  SELECT
    -- Identificadores únicos
    CAST(id AS VARCHAR) AS contact_id,
    
    -- Dados pessoais
    TRIM(UPPER(COALESCE(firstName, ''))) AS primeiro_nome,
    TRIM(UPPER(COALESCE(lastName, ''))) AS ultimo_nome,
    TRIM(LOWER(email)) AS email,
    REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '') AS telefone,
    
    -- Dados adicionais
    organization,
    TRIM(UPPER(COALESCE(firstName, '') || ' ' || COALESCE(lastName, ''))) AS nome_completo,
    
    -- Status e tags
    CAST(deleted AS BOOLEAN) AS is_deleted,
    CAST(anonymized AS BOOLEAN) AS is_anonymized,
    tags,
    
    -- Timestamps
    CAST(cdate AS TIMESTAMP) AS created_timestamp,
    CAST(udate AS TIMESTAMP) AS updated_timestamp,
    CAST(_extraction_timestamp AS TIMESTAMP) AS extraction_timestamp,
    
    -- Metadados
    _source_system AS source_system,
    _load_date AS load_date,
    
    -- Campos customizados (se existirem)
    COALESCE(JSON_EXTRACT_SCALAR(fields, '$.lead_source'), 'unknown') AS lead_source,
    COALESCE(JSON_EXTRACT_SCALAR(fields, '$.utm_campaign'), '') AS utm_campaign,
    COALESCE(JSON_EXTRACT_SCALAR(fields, '$.utm_source'), '') AS utm_source,
    COALESCE(JSON_EXTRACT_SCALAR(fields, '$.utm_medium'), '') AS utm_medium
    
  FROM activecampaign_raw
),

contacts_enriched AS (
  SELECT
    *,
    
    -- Validações
    CASE 
      WHEN email IS NOT NULL AND email LIKE '%@%' AND email LIKE '%.%'
      THEN TRUE 
      ELSE FALSE 
    END AS has_valid_email,
    
    CASE 
      WHEN LENGTH(telefone) >= 10 
      THEN TRUE 
      ELSE FALSE 
    END AS has_valid_phone,
    
    CASE 
      WHEN LENGTH(TRIM(nome_completo)) > 2 
      THEN TRUE 
      ELSE FALSE 
    END AS has_valid_name,
    
    -- Categorização de qualidade do lead
    CASE 
      WHEN email LIKE '%@%' AND LENGTH(telefone) >= 10 AND LENGTH(TRIM(nome_completo)) > 2 
      THEN 'Completo'
      WHEN email LIKE '%@%' AND LENGTH(TRIM(nome_completo)) > 2 
      THEN 'Parcial'
      WHEN email LIKE '%@%' 
      THEN 'Mínimo'
      ELSE 'Incompleto'
    END AS qualidade_lead,
    
    -- Origem do lead
    CASE 
      WHEN utm_source != '' THEN utm_source
      WHEN lead_source != 'unknown' THEN lead_source
      ELSE 'activecampaign_direct'
    END AS origem_lead
    
  FROM contacts_cleaned
),

final_staging AS (
  SELECT
    -- Identificadores
    contact_id,
    
    -- Dados pessoais limpos
    primeiro_nome,
    ultimo_nome,
    nome_completo,
    email,
    telefone,
    organization,
    
    -- Status
    is_deleted,
    is_anonymized,
    tags,
    
    -- Timestamps
    created_timestamp,
    updated_timestamp,
    extraction_timestamp,
    load_date,
    
    -- Origem e UTMs
    lead_source,
    origem_lead,
    utm_campaign,
    utm_source,
    utm_medium,
    
    -- Validações
    has_valid_email,
    has_valid_phone,
    has_valid_name,
    qualidade_lead,
    
    -- Campos para Data Vault
    'activecampaign' AS origem,
    'activecampaign' AS record_source,
    
    -- Flags adicionais
    CASE 
      WHEN has_valid_email = TRUE OR has_valid_phone = TRUE 
      THEN TRUE 
      ELSE FALSE 
    END AS has_contact_info,
    
    CASE 
      WHEN created_timestamp >= CURRENT_DATE - INTERVAL '30' DAY 
      THEN TRUE 
      ELSE FALSE 
    END AS is_recent_contact,
    
    CASE 
      WHEN tags IS NOT NULL AND tags != '' 
      THEN TRUE 
      ELSE FALSE 
    END AS has_tags
    
  FROM contacts_enriched
)

SELECT * FROM final_staging
WHERE is_deleted = FALSE 
  AND is_anonymized = FALSE 
  AND has_contact_info = TRUE  -- Filtrar apenas contatos válidos com informações de contato

