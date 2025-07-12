{{
  config(
    materialized='incremental',
    unique_key='pessoa_hash_key',
    on_schema_change='append_new_columns',
    file_format='parquet',
    table_type='iceberg',
    incremental_strategy='merge',
    partition_by=['load_date'],
    sort_by=['pessoa_hash_key']
  )
}}

-- Hub Pessoa - Centro da arquitetura Data Vault
-- Unifica identidades de leads através de diferentes estratégias de hash

WITH facebook_leads AS (
    SELECT
        {{ generate_person_hash('nome', 'email', 'telefone') }} AS pessoa_hash_key,
        load_date,
        record_source
    FROM {{ ref('stg_facebook_leads') }}
    WHERE {{ generate_person_hash('nome', 'email', 'telefone') }} IS NOT NULL
),

activecampaign_contacts AS (
    SELECT
        {{ generate_person_hash('nome_completo', 'email', 'telefone') }} AS pessoa_hash_key,
        load_date,
        record_source
    FROM {{ ref('stg_activecampaign_contacts') }}
    WHERE {{ generate_person_hash('nome_completo', 'email', 'telefone') }} IS NOT NULL
),

-- União de todas as fontes
source_data AS (
    SELECT DISTINCT
        pessoa_hash_key,
        load_date,
        record_source
    FROM facebook_leads
    
    UNION ALL
    
    SELECT DISTINCT
        pessoa_hash_key,
        load_date,
        record_source
    FROM activecampaign_contacts
),

-- Deduplica e pega a primeira ocorrência de cada pessoa
hub_pessoa AS (
    SELECT
        pessoa_hash_key,
        MIN(load_date) AS load_date,
        MIN(record_source) AS record_source
    FROM source_data
    GROUP BY pessoa_hash_key
)

SELECT
    pessoa_hash_key,
    load_date,
    record_source,
    CURRENT_TIMESTAMP AS dbt_updated_at,
    '{{ var("dbt_run_id", "unknown") }}' AS dbt_run_id
FROM hub_pessoa

{% if is_incremental() %}
    WHERE load_date > (SELECT COALESCE(MAX(load_date), '1900-01-01') FROM {{ this }})
{% endif %}

