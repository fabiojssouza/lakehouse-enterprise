{{
  config(
    materialized='incremental',
    unique_key='pessoa_hash_key',
    table_type='iceberg',
    incremental_strategy='merge',
    schema='raw_vault'
  )
}}

/*
Hub Pessoa - Raw Vault
Entidade central para pessoas/leads vindos APENAS do CRM
*/

WITH source_data AS (
  SELECT
    -- Dados da pessoa
    email,
    telefone,
    nome,
    
    -- Metadados
    extraction_timestamp,
    load_date,
    record_source
    
  FROM {{ ref('stg_activecampaign_contacts') }}
  
  {% if is_incremental() %}
    WHERE load_date > (SELECT MAX(load_date) FROM {{ this }})
  {% endif %}
),

pessoa_with_hash AS (
  SELECT
    -- Gerar hash key usando macro de unificação
    {{ generate_unified_person_hash('email', 'telefone', 'nome') }} AS pessoa_hash_key,
    
    -- Dados originais para validação
    email,
    telefone, 
    nome,
    
    -- Metadados
    extraction_timestamp AS load_date,
    record_source
    
  FROM source_data
  WHERE {{ generate_unified_person_hash('email', 'telefone', 'nome') }} IS NOT NULL
),

hub_pessoa AS (
  SELECT DISTINCT
    pessoa_hash_key,
    load_date,
    record_source
    
  FROM pessoa_with_hash
)

SELECT * FROM hub_pessoa

