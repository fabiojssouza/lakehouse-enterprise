{{
  config(
    materialized='incremental',
    unique_key=['pessoa_hash_key', 'load_date'],
    on_schema_change='append_new_columns',
    file_format='parquet',
    table_type='iceberg',
    incremental_strategy='merge',
    partition_by=['load_date'],
    sort_by=['pessoa_hash_key', 'load_date']
  )
}}

-- Satellite Pessoa Detalhes - Atributos descritivos e histórico de mudanças
-- Armazena informações pessoais dos leads com versionamento temporal

WITH facebook_leads AS (
    SELECT
        {{ generate_person_hash('nome', 'email', 'telefone') }} AS pessoa_hash_key,
        load_date,
        {{ generate_hash_diff(['nome', 'email', 'telefone', 'origem', 'lead_id']) }} AS hash_diff,
        nome,
        email,
        telefone,
        origem,
        'facebook_ads' AS cliente_origem,
        lead_id,
        campaign_id,
        created_timestamp AS created_time,
        record_source
    FROM {{ ref('stg_facebook_leads') }}
    WHERE {{ generate_person_hash('nome', 'email', 'telefone') }} IS NOT NULL
),

activecampaign_contacts AS (
    SELECT
        {{ generate_person_hash('nome_completo', 'email', 'telefone') }} AS pessoa_hash_key,
        load_date,
        {{ generate_hash_diff(['nome_completo', 'email', 'telefone', 'origem', 'contact_id']) }} AS hash_diff,
        nome_completo AS nome,
        email,
        telefone,
        origem,
        'activecampaign' AS cliente_origem,
        contact_id AS lead_id,
        origem_lead AS campaign_id,
        created_timestamp AS created_time,
        record_source
    FROM {{ ref('stg_activecampaign_contacts') }}
    WHERE {{ generate_person_hash('nome_completo', 'email', 'telefone') }} IS NOT NULL
),

-- União de todas as fontes
source_data AS (
    SELECT
        pessoa_hash_key,
        load_date,
        hash_diff,
        nome,
        email,
        telefone,
        origem,
        cliente_origem,
        lead_id,
        campaign_id,
        created_time,
        record_source
    FROM facebook_leads
    
    UNION ALL
    
    SELECT
        pessoa_hash_key,
        load_date,
        hash_diff,
        nome,
        email,
        telefone,
        origem,
        cliente_origem,
        lead_id,
        campaign_id,
        created_time,
        record_source
    FROM activecampaign_contacts
),

-- Identificar mudanças nos dados
ranked_data AS (
    SELECT
        pessoa_hash_key,
        load_date,
        hash_diff,
        nome,
        email,
        telefone,
        origem,
        cliente_origem,
        lead_id,
        campaign_id,
        created_time,
        record_source,
        ROW_NUMBER() OVER (
            PARTITION BY pessoa_hash_key, hash_diff 
            ORDER BY load_date ASC
        ) AS rn
    FROM source_data
),

-- Calcular load_end_date para versionamento
versioned_data AS (
    SELECT
        pessoa_hash_key,
        load_date,
        LEAD(load_date) OVER (
            PARTITION BY pessoa_hash_key 
            ORDER BY load_date ASC
        ) AS load_end_date,
        hash_diff,
        nome,
        email,
        telefone,
        origem,
        cliente_origem,
        lead_id,
        campaign_id,
        created_time,
        record_source
    FROM ranked_data
    WHERE rn = 1  -- Apenas primeira ocorrência de cada hash_diff
),

final AS (
    SELECT
        pessoa_hash_key,
        load_date,
        load_end_date,
        hash_diff,
        COALESCE(TRIM(nome), '') AS nome,
        COALESCE(LOWER(TRIM(email)), '') AS email,
        COALESCE(TRIM(telefone), '') AS telefone,
        origem,
        cliente_origem,
        lead_id,
        campaign_id,
        created_time,
        record_source,
        CURRENT_TIMESTAMP AS dbt_updated_at,
        '{{ var("dbt_run_id", "unknown") }}' AS dbt_run_id,
        
        -- Flags de qualidade de dados
        CASE 
            WHEN nome IS NOT NULL AND TRIM(nome) != '' THEN 1 
            ELSE 0 
        END AS has_nome,
        
        CASE 
            WHEN email IS NOT NULL AND TRIM(email) != '' 
                 AND email LIKE '%@%' THEN 1 
            ELSE 0 
        END AS has_valid_email,
        
        CASE 
            WHEN telefone IS NOT NULL AND TRIM(telefone) != '' 
                 AND LENGTH(TRIM(telefone)) >= 8 THEN 1 
            ELSE 0 
        END AS has_valid_telefone,
        
        -- Score de completude (0-3)
        (CASE WHEN nome IS NOT NULL AND TRIM(nome) != '' THEN 1 ELSE 0 END +
         CASE WHEN email IS NOT NULL AND TRIM(email) != '' AND email LIKE '%@%' THEN 1 ELSE 0 END +
         CASE WHEN telefone IS NOT NULL AND TRIM(telefone) != '' AND LENGTH(TRIM(telefone)) >= 8 THEN 1 ELSE 0 END
        ) AS completude_score
        
    FROM versioned_data
)

SELECT * FROM final

{% if is_incremental() %}
    WHERE load_date > (SELECT COALESCE(MAX(load_date), '1900-01-01') FROM {{ this }})
{% endif %}

