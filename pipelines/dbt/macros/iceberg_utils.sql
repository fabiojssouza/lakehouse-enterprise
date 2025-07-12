-- Macros utilitárias para Apache Iceberg
-- Lakehouse Enterprise - DBT Macros

-- Macro para gerar hash keys múltiplas para unificação de identidades
{% macro generate_person_hash(nome, email, telefone) %}
    CASE 
        WHEN {{ nome }} IS NOT NULL AND {{ email }} IS NOT NULL AND {{ telefone }} IS NOT NULL 
        THEN MD5(LOWER(TRIM({{ nome }})) || '|' || LOWER(TRIM({{ email }})) || '|' || REGEXP_REPLACE({{ telefone }}, '[^0-9]', ''))
        
        WHEN {{ nome }} IS NOT NULL AND {{ email }} IS NOT NULL 
        THEN MD5(LOWER(TRIM({{ nome }})) || '|' || LOWER(TRIM({{ email }})))
        
        WHEN {{ email }} IS NOT NULL AND {{ telefone }} IS NOT NULL 
        THEN MD5(LOWER(TRIM({{ email }})) || '|' || REGEXP_REPLACE({{ telefone }}, '[^0-9]', ''))
        
        WHEN {{ nome }} IS NOT NULL AND {{ telefone }} IS NOT NULL 
        THEN MD5(LOWER(TRIM({{ nome }})) || '|' || REGEXP_REPLACE({{ telefone }}, '[^0-9]', ''))
        
        WHEN {{ email }} IS NOT NULL 
        THEN MD5(LOWER(TRIM({{ email }})))
        
        ELSE NULL 
    END
{% endmacro %}

-- Macro para criar tabelas Iceberg com configurações otimizadas
{% macro create_iceberg_table(table_name, columns, partition_by=none, sort_by=none, table_properties={}) %}
  
  {% set default_properties = {
    'format-version': '2',
    'write.target-file-size-bytes': var('iceberg_target_file_size', '134217728'),
    'write.parquet.compression-codec': var('iceberg_compression', 'zstd'),
    'write.metadata.compression-codec': 'gzip',
    'write.object-storage.enabled': 'true'
  } %}
  
  {% set merged_properties = default_properties.update(table_properties) or default_properties %}
  
  CREATE TABLE IF NOT EXISTS {{ table_name }} (
    {% for column in columns %}
      {{ column.name }} {{ column.type }}{% if not loop.last %},{% endif %}
    {% endfor %}
  )
  {% if partition_by %}
  PARTITIONED BY ({{ partition_by | join(', ') }})
  {% endif %}
  {% if sort_by %}
  SORTED BY ({{ sort_by | join(', ') }})
  {% endif %}
  WITH (
    format = 'ICEBERG',
    {% for key, value in merged_properties.items() %}
    '{{ key }}' = '{{ value }}'{% if not loop.last %},{% endif %}
    {% endfor %}
  )

{% endmacro %}

-- Macro para otimizar tabelas Iceberg
{% macro optimize_iceberg_table(table_name, where_clause=none) %}
  
  {% set optimize_sql %}
    OPTIMIZE {{ table_name }}
    {% if where_clause %}
    WHERE {{ where_clause }}
    {% endif %}
  {% endset %}
  
  {{ log("Optimizing Iceberg table: " ~ table_name, info=True) }}
  {{ run_query(optimize_sql) }}
  
{% endmacro %}

-- Macro para expirar snapshots antigos
{% macro expire_iceberg_snapshots(table_name, older_than_days=7) %}
  
  {% set expire_sql %}
    CALL iceberg.system.expire_snapshots(
      table => '{{ table_name }}',
      older_than => TIMESTAMP '{{ (modules.datetime.datetime.now() - modules.datetime.timedelta(days=older_than_days)).strftime('%Y-%m-%d %H:%M:%S') }}'
    )
  {% endset %}
  
  {{ log("Expiring snapshots for table: " ~ table_name, info=True) }}
  {{ run_query(expire_sql) }}
  
{% endmacro %}

-- Macro para remover arquivos órfãos
{% macro remove_iceberg_orphan_files(table_name, older_than_days=3) %}
  
  {% set remove_sql %}
    CALL iceberg.system.remove_orphan_files(
      table => '{{ table_name }}',
      older_than => TIMESTAMP '{{ (modules.datetime.datetime.now() - modules.datetime.timedelta(days=older_than_days)).strftime('%Y-%m-%d %H:%M:%S') }}'
    )
  {% endset %}
  
  {{ log("Removing orphan files for table: " ~ table_name, info=True) }}
  {{ run_query(remove_sql) }}
  
{% endmacro %}

-- Macro para compactar arquivos pequenos
{% macro compact_iceberg_table(table_name, target_file_size_mb=128) %}
  
  {% set compact_sql %}
    CALL iceberg.system.rewrite_data_files(
      table => '{{ table_name }}',
      strategy => 'sort',
      options => map(
        array['target-file-size-bytes'],
        array['{{ target_file_size_mb * 1024 * 1024 }}']
      )
    )
  {% endset %}
  
  {{ log("Compacting table: " ~ table_name, info=True) }}
  {{ run_query(compact_sql) }}
  
{% endmacro %}

-- Macro para gerar estatísticas de tabela Iceberg
{% macro analyze_iceberg_table(table_name) %}
  
  {% set analyze_sql %}
    ANALYZE TABLE {{ table_name }} COMPUTE STATISTICS
  {% endset %}
  
  {{ log("Analyzing table: " ~ table_name, info=True) }}
  {{ run_query(analyze_sql) }}
  
{% endmacro %}

-- Macro para verificar saúde da tabela Iceberg
{% macro check_iceberg_table_health(table_name) %}
  
  {% set health_check_sql %}
    SELECT 
      '{{ table_name }}' as table_name,
      COUNT(*) as total_files,
      SUM(file_size_in_bytes) as total_size_bytes,
      AVG(file_size_in_bytes) as avg_file_size_bytes,
      MIN(file_size_in_bytes) as min_file_size_bytes,
      MAX(file_size_in_bytes) as max_file_size_bytes,
      COUNT(CASE WHEN file_size_in_bytes < 16777216 THEN 1 END) as small_files_count,
      COUNT(CASE WHEN file_size_in_bytes > 268435456 THEN 1 END) as large_files_count
    FROM iceberg."$files"
    WHERE table_name = '{{ table_name }}'
  {% endset %}
  
  {{ return(run_query(health_check_sql)) }}
  
{% endmacro %}

-- Macro para configurar propriedades de tabela Iceberg
{% macro set_iceberg_table_properties(table_name, properties) %}
  
  {% for key, value in properties.items() %}
    {% set alter_sql %}
      ALTER TABLE {{ table_name }} SET TBLPROPERTIES ('{{ key }}' = '{{ value }}')
    {% endset %}
    {{ run_query(alter_sql) }}
  {% endfor %}
  
{% endmacro %}

-- Macro para criar partições otimizadas baseadas em Data Vault
{% macro create_data_vault_partitions(load_date_column='load_date', partition_strategy='daily') %}
  
  {% if partition_strategy == 'daily' %}
    {% set partition_expr = "date_trunc('day', " ~ load_date_column ~ ")" %}
  {% elif partition_strategy == 'weekly' %}
    {% set partition_expr = "date_trunc('week', " ~ load_date_column ~ ")" %}
  {% elif partition_strategy == 'monthly' %}
    {% set partition_expr = "date_trunc('month', " ~ load_date_column ~ ")" %}
  {% else %}
    {% set partition_expr = load_date_column %}
  {% endif %}
  
  {{ return(partition_expr) }}
  
{% endmacro %}

-- Macro para monitoramento de performance Iceberg
{% macro monitor_iceberg_performance(table_name) %}
  
  {% set monitoring_sql %}
    WITH table_stats AS (
      SELECT 
        '{{ table_name }}' as table_name,
        COUNT(*) as total_snapshots,
        MAX(committed_at) as last_commit,
        MIN(committed_at) as first_commit
      FROM iceberg."$snapshots"
      WHERE table_name = '{{ table_name }}'
    ),
    file_stats AS (
      SELECT 
        COUNT(*) as total_files,
        SUM(file_size_in_bytes) as total_size_bytes,
        AVG(file_size_in_bytes) as avg_file_size_bytes
      FROM iceberg."$files"
      WHERE table_name = '{{ table_name }}'
    ),
    manifest_stats AS (
      SELECT 
        COUNT(*) as total_manifests,
        SUM(length) as total_manifest_size
      FROM iceberg."$manifests"
      WHERE table_name = '{{ table_name }}'
    )
    SELECT 
      ts.*,
      fs.*,
      ms.*,
      CURRENT_TIMESTAMP as check_timestamp
    FROM table_stats ts
    CROSS JOIN file_stats fs
    CROSS JOIN manifest_stats ms
  {% endset %}
  
  {{ return(run_query(monitoring_sql)) }}
  
{% endmacro %}

-- Macro para gerar hash_diff para Data Vault Satellites
{% macro generate_hash_diff(columns) %}
  MD5(
    CONCAT(
      {% for column in columns %}
        COALESCE(CAST({{ column }} AS VARCHAR), '')
        {%- if not loop.last %} || '|' || {% endif %}
      {% endfor %}
    )
  )
{% endmacro %}

-- Macro para gerar load_date padrão
{% macro generate_load_date() %}
  CURRENT_TIMESTAMP
{% endmacro %}

-- Macro para gerar record_source
{% macro generate_record_source(source_name) %}
  '{{ source_name }}'
{% endmacro %}

