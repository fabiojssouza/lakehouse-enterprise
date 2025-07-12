{{
  config(
    materialized='incremental',
    unique_key='pessoa_campanha_hash_key',
    table_type='iceberg',
    incremental_strategy='merge',
    schema='raw_vault'
  )
}}

/*
Link Pessoa-Campanha - Raw Vault
Relaciona pessoas (CRM) com campanhas (Facebook/Google) via UTM parameters
*/

WITH pessoas_com_utm AS (
  SELECT
    {{ generate_unified_person_hash('email', 'telefone', 'nome') }} AS pessoa_hash_key,
    utm_campaign,
    utm_source,
    utm_medium,
    utm_content,
    load_date,
    record_source
    
  FROM {{ ref('stg_activecampaign_contacts') }}
  WHERE {{ generate_unified_person_hash('email', 'telefone', 'nome') }} IS NOT NULL
    AND utm_campaign IS NOT NULL
    AND utm_campaign != ''
  
  {% if is_incremental() %}
    AND load_date > (SELECT MAX(load_date) FROM {{ this }})
  {% endif %}
),

campanhas_facebook AS (
  SELECT
    MD5(CONCAT(campaign_id, '|', 'facebook_ads')) AS campanha_hash_key,
    campaign_id,
    campaign_name,
    'facebook_ads' AS platform
  FROM {{ ref('stg_facebook_campaigns') }}
),

campanhas_google AS (
  SELECT
    MD5(CONCAT(campaign_id, '|', 'google_ads')) AS campanha_hash_key,
    campaign_id,
    campaign_name,
    'google_ads' AS platform
  FROM {{ ref('stg_google_campaigns') }}
),

todas_campanhas AS (
  SELECT * FROM campanhas_facebook
  UNION ALL
  SELECT * FROM campanhas_google
),

-- Estratégias de matching UTM -> Campanha
matching_por_id AS (
  SELECT
    p.pessoa_hash_key,
    c.campanha_hash_key,
    p.utm_campaign,
    c.campaign_id,
    c.platform,
    'match_by_id' AS match_strategy,
    p.load_date,
    p.record_source
    
  FROM pessoas_com_utm p
  JOIN todas_campanhas c 
    ON p.utm_campaign = c.campaign_id
),

matching_por_nome AS (
  SELECT
    p.pessoa_hash_key,
    c.campanha_hash_key,
    p.utm_campaign,
    c.campaign_name,
    c.platform,
    'match_by_name' AS match_strategy,
    p.load_date,
    p.record_source
    
  FROM pessoas_com_utm p
  JOIN todas_campanhas c 
    ON LOWER(p.utm_campaign) = LOWER(c.campaign_name)
  WHERE p.pessoa_hash_key NOT IN (SELECT pessoa_hash_key FROM matching_por_id)
),

matching_por_source AS (
  SELECT
    p.pessoa_hash_key,
    c.campanha_hash_key,
    p.utm_campaign,
    c.campaign_name,
    c.platform,
    'match_by_source' AS match_strategy,
    p.load_date,
    p.record_source
    
  FROM pessoas_com_utm p
  JOIN todas_campanhas c 
    ON (p.utm_source = 'facebook' AND c.platform = 'facebook_ads')
    OR (p.utm_source = 'google' AND c.platform = 'google_ads')
    OR (p.utm_source = 'fb' AND c.platform = 'facebook_ads')
    OR (p.utm_source = 'adwords' AND c.platform = 'google_ads')
  WHERE p.pessoa_hash_key NOT IN (
    SELECT pessoa_hash_key FROM matching_por_id
    UNION
    SELECT pessoa_hash_key FROM matching_por_nome
  )
),

todos_matches AS (
  SELECT * FROM matching_por_id
  UNION ALL
  SELECT * FROM matching_por_nome  
  UNION ALL
  SELECT * FROM matching_por_source
),

link_pessoa_campanha AS (
  SELECT
    -- Hash key do link
    MD5(CONCAT(pessoa_hash_key, '|', campanha_hash_key)) AS pessoa_campanha_hash_key,
    
    -- Foreign keys
    pessoa_hash_key,
    campanha_hash_key,
    
    -- Metadados
    load_date,
    record_source
    
  FROM todos_matches
)

SELECT DISTINCT * FROM link_pessoa_campanha

