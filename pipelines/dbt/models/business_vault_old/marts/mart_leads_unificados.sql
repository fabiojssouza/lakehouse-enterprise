{{
  config(
    materialized='table',
    file_format='parquet'
  )
}}

-- Mart de Leads Unificados
-- Visão analítica dos leads com dados de pessoa e campanha

WITH hub_pessoa AS (
    SELECT * FROM {{ ref('hub_pessoa') }}
),

sat_pessoa AS (
    SELECT 
        pessoa_hash_key,
        nome,
        email,
        telefone,
        origem,
        cliente_origem,
        lead_id,
        campaign_id,
        created_time,
        completude_score,
        has_nome,
        has_valid_email,
        has_valid_telefone,
        load_date,
        ROW_NUMBER() OVER (
            PARTITION BY pessoa_hash_key 
            ORDER BY load_date DESC
        ) AS rn
    FROM {{ ref('sat_pessoa_detalhes') }}
    WHERE load_end_date IS NULL OR load_end_date > CURRENT_TIMESTAMP
),

campaigns AS (
    SELECT * FROM {{ ref('campaigns') }}
),

leads_unificados AS (
    SELECT
        h.pessoa_hash_key,
        s.nome,
        s.email,
        s.telefone,
        s.origem,
        s.cliente_origem,
        s.lead_id,
        s.campaign_id,
        s.created_time AS lead_created_time,
        s.completude_score,
        s.has_nome,
        s.has_valid_email,
        s.has_valid_telefone,
        
        -- Dados da campanha
        c.nome AS campaign_name,
        c.plataforma,
        c.objetivo,
        c.status AS campaign_status,
        c.spend AS campaign_spend,
        c.impressions,
        c.clicks,
        c.ctr,
        c.cpc,
        c.performance_ctr,
        c.categoria_cpc,
        
        -- Métricas calculadas
        CASE 
            WHEN s.completude_score >= 3 THEN 'Completo'
            WHEN s.completude_score >= 2 THEN 'Parcial'
            ELSE 'Incompleto'
        END AS qualidade_dados,
        
        DATE_DIFF('day', s.created_time, CURRENT_DATE) AS dias_desde_lead,
        
        CASE
            WHEN DATE_DIFF('day', s.created_time, CURRENT_DATE) <= 7 THEN 'Recente'
            WHEN DATE_DIFF('day', s.created_time, CURRENT_DATE) <= 30 THEN 'Médio'
            ELSE 'Antigo'
        END AS categoria_tempo,
        
        -- Flags de segmentação
        CASE 
            WHEN s.origem = 'facebook_ads' THEN 1 
            ELSE 0 
        END AS is_facebook_lead,
        
        CASE 
            WHEN s.origem = 'google_ads' THEN 1 
            ELSE 0 
        END AS is_google_lead,
        
        CASE 
            WHEN s.origem = 'crm' THEN 1 
            ELSE 0 
        END AS is_crm_lead,
        
        h.load_date AS hub_load_date,
        s.load_date AS sat_load_date,
        CURRENT_TIMESTAMP AS dbt_updated_at
        
    FROM hub_pessoa h
    INNER JOIN sat_pessoa s 
        ON h.pessoa_hash_key = s.pessoa_hash_key 
        AND s.rn = 1
    LEFT JOIN campaigns c 
        ON s.campaign_id = c.campaign_id 
        AND s.origem = c.fonte
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pessoa_hash_key']) }} AS lead_key,
    *
FROM leads_unificados

