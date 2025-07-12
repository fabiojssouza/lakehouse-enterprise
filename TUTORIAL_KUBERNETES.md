# Tutorial Completo: Execução da Arquitetura Lakehouse Enterprise com Apache Iceberg no Kubernetes

**Autor:** Manus AI  
**Versão:** 2.0  
**Data:** Julho 2025  
**Arquitetura:** Modern Data Stack com Apache Iceberg

## Sumário Executivo

Este tutorial fornece instruções completas para executar a arquitetura Lakehouse Enterprise atualizada com Apache Iceberg no Kubernetes. A arquitetura foi otimizada para suportar modelagem Data Vault com unificação de identidades de leads através de múltiplas chaves hash, integrando dados de CRMs, Facebook Ads e Google Ads.

### Principais Atualizações Implementadas

A versão 2.0 da arquitetura inclui componentes críticos que estavam ausentes na versão anterior:

- **Hive Metastore Standalone**: Componente essencial para funcionamento do Apache Iceberg
- **PostgreSQL Backend**: Base de dados para o Hive Metastore
- **Configurações Otimizadas do Trino**: Melhorias significativas de performance
- **DBT Configurado para Iceberg**: Modelos otimizados para formato Iceberg
- **Macros Específicas**: Utilitários para Data Vault e Iceberg
- **Monitoramento Avançado**: Métricas e alertas específicos

## Pré-requisitos

### Infraestrutura Necessária

Antes de iniciar a execução, certifique-se de que o ambiente Kubernetes atende aos seguintes requisitos:

**Cluster Kubernetes:**
- Versão mínima: 1.24+
- Nodes: Mínimo 3 nodes (1 master + 2 workers)
- CPU total: Mínimo 16 cores
- Memória total: Mínimo 64GB RAM
- Storage: Mínimo 500GB de armazenamento persistente

**Ferramentas Necessárias:**
- kubectl configurado e conectado ao cluster
- Helm 3.8+ instalado
- ArgoCD instalado no cluster
- Git configurado para acesso ao repositório

### Recursos de Hardware Recomendados

Para ambiente de produção, recomendamos a seguinte configuração:

| Componente | CPU | Memória | Storage | Replicas |
|------------|-----|---------|---------|----------|
| PostgreSQL | 2 cores | 4GB | 100GB | 1 |
| Hive Metastore | 2 cores | 4GB | 50GB | 1 |
| Trino Coordinator | 8 cores | 24GB | 100GB | 1 |
| Trino Workers | 8 cores | 24GB | 100GB | 3 |
| MinIO | 4 cores | 8GB | 1TB | 3 |
| Airbyte | 4 cores | 8GB | 100GB | 2 |
| Prefect | 2 cores | 4GB | 50GB | 2 |
| Superset | 4 cores | 8GB | 50GB | 2 |

## Arquitetura Atualizada

### Visão Geral dos Componentes

A arquitetura Lakehouse Enterprise 2.0 é composta pelos seguintes componentes principais:

**Camada de Armazenamento:**
- MinIO: Object storage compatível com S3
- PostgreSQL: Backend para Hive Metastore

**Camada de Metadados:**
- Hive Metastore: Gerenciamento de metadados para Iceberg
- OpenMetadata: Catálogo de dados e linhagem

**Camada de Processamento:**
- Trino: Engine de consulta distribuída
- Spark: Processamento de dados em larga escala
- DBT: Transformação e modelagem de dados

**Camada de Ingestão:**
- Airbyte: Conectores para fontes de dados
- Prefect: Orquestração de pipelines

**Camada de Visualização:**
- Superset: Dashboards e análises

**Camada de Orquestração:**
- ArgoCD: GitOps para Kubernetes
- Kubernetes: Orquestração de containers

### Fluxo de Dados

O fluxo de dados na arquitetura segue o padrão medallion com Data Vault:

1. **Bronze Layer**: Dados brutos ingeridos via Airbyte
2. **Silver Layer**: Modelagem Data Vault (Hubs, Links, Satellites)
3. **Gold Layer**: Marts analíticos para consumo

## Preparação do Ambiente

### Configuração do Namespace

Antes de iniciar o deployment, é necessário configurar os namespaces adequados no Kubernetes:

```bash
# Criar namespaces necessários
kubectl create namespace argocd
kubectl create namespace postgresql
kubectl create namespace hive-metastore
kubectl create namespace trino
kubectl create namespace minio
kubectl create namespace airbyte
kubectl create namespace prefect
kubectl create namespace superset
kubectl create namespace openmetadata
kubectl create namespace monitoring
```

### Configuração do ArgoCD

O ArgoCD será responsável pelo deployment e gerenciamento de todos os componentes. Configure o acesso ao repositório:

```bash
# Adicionar repositório ao ArgoCD
argocd repo add https://github.com/your-org/lakehouse-enterprise \
  --username your-username \
  --password your-token \
  --name lakehouse-enterprise
```

### Configuração de Secrets

Crie os secrets necessários para autenticação entre componentes:

```bash
# Secret para MinIO
kubectl create secret generic minio-credentials \
  --from-literal=access-key=minioadmin \
  --from-literal=secret-key=minioadmin123 \
  -n minio

# Secret para PostgreSQL
kubectl create secret generic postgresql-credentials \
  --from-literal=postgres-password=postgres123 \
  --from-literal=password=hive123 \
  -n postgresql

# Secret para Hive Metastore
kubectl create secret generic hive-metastore-credentials \
  --from-literal=database-password=hive123 \
  --from-literal=s3-access-key=minioadmin \
  --from-literal=s3-secret-key=minioadmin123 \
  -n hive-metastore
```

## Ordem de Deployment

### Fase 1: Infraestrutura Base

A ordem de deployment é crítica para o funcionamento correto da arquitetura. Siga rigorosamente a sequência abaixo:

#### 1.1 PostgreSQL (Backend do Hive Metastore)

O PostgreSQL deve ser o primeiro componente a ser deployado, pois serve como backend para o Hive Metastore:

```bash
# Deploy PostgreSQL via ArgoCD
kubectl apply -f argocd/apps/postgresql-app.yaml

# Verificar status do deployment
kubectl get pods -n postgresql
kubectl logs -f deployment/postgresql -n postgresql
```

Aguarde até que o PostgreSQL esteja completamente funcional antes de prosseguir. Verifique a conectividade:

```bash
# Teste de conectividade
kubectl exec -it deployment/postgresql -n postgresql -- \
  psql -h localhost -U hive -d metastore -c "SELECT version();"
```

#### 1.2 MinIO (Object Storage)

O MinIO fornece armazenamento compatível com S3 para os dados do lakehouse:

```bash
# Deploy MinIO
kubectl apply -f argocd/apps/minio-app.yaml

# Verificar buckets necessários
kubectl exec -it deployment/minio -n minio -- \
  mc mb local/lakehouse-bronze local/lakehouse-silver local/lakehouse-gold
```

### Fase 2: Metastore e Catálogo

#### 2.1 Hive Metastore Standalone

O Hive Metastore é essencial para o funcionamento do Apache Iceberg:

```bash
# Deploy Hive Metastore
kubectl apply -f argocd/apps/hive-metastore-app.yaml

# Verificar inicialização do schema
kubectl logs -f job/hive-metastore-schema-init -n hive-metastore

# Verificar conectividade do Thrift server
kubectl exec -it deployment/hive-metastore -n hive-metastore -- \
  netstat -tlnp | grep 9083
```

#### 2.2 OpenMetadata

Deploy do catálogo de dados:

```bash
kubectl apply -f argocd/apps/openmetadata-app.yaml
```

### Fase 3: Engine de Consulta

#### 3.1 Trino com Configurações Otimizadas

O Trino é o componente central para consultas no lakehouse:

```bash
# Deploy Trino
kubectl apply -f argocd/apps/trino-app.yaml

# Verificar conectividade com Hive Metastore
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "SHOW CATALOGS;"

# Testar criação de tabela Iceberg
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "CREATE SCHEMA IF NOT EXISTS iceberg.test;"
```

### Fase 4: Processamento e Transformação

#### 4.1 Spark

```bash
kubectl apply -f argocd/apps/spark-app.yaml
```

#### 4.2 DBT

O DBT está configurado com otimizações específicas para Iceberg:

```bash
# Deploy DBT
kubectl apply -f argocd/apps/dbt-app.yaml

# Verificar configuração
kubectl exec -it deployment/dbt -n dbt -- \
  dbt debug --profiles-dir /opt/dbt/profiles
```

### Fase 5: Ingestão de Dados

#### 5.1 Airbyte

```bash
kubectl apply -f argocd/apps/airbyte-app.yaml
```

#### 5.2 Prefect

```bash
kubectl apply -f argocd/apps/prefect-app.yaml
```

### Fase 6: Visualização

#### 6.1 Superset

```bash
kubectl apply -f argocd/apps/superset-app.yaml
```

## Configuração dos Conectores de Dados

### Facebook Ads

Configure o conector do Facebook Ads no Airbyte:

```json
{
  "account_id": "your_facebook_account_id",
  "access_token": "your_facebook_access_token",
  "start_date": "2023-01-01",
  "end_date": "2024-12-31",
  "insights_lookback_window": 28
}
```

### Google Ads

Configure o conector do Google Ads:

```json
{
  "customer_id": "your_google_ads_customer_id",
  "developer_token": "your_developer_token",
  "client_id": "your_client_id",
  "client_secret": "your_client_secret",
  "refresh_token": "your_refresh_token",
  "start_date": "2023-01-01"
}
```

### CRM

Configure o conector do seu CRM (ActiveCampaign):

```json
{
  "api_key": "your_activecampaign_api_key",
  "api_url": "https://yourcompany.api-us1.com",
  "start_date": "2023-01-01T00:00:00Z"
}
```

## Execução dos Pipelines DBT

### Configuração Inicial

Após o deployment completo, execute a configuração inicial do DBT:

```bash
# Acessar container DBT
kubectl exec -it deployment/dbt -n dbt -- bash

# Instalar dependências
dbt deps

# Verificar conexão
dbt debug

# Executar seed (dados de referência)
dbt seed

# Executar modelos bronze (dados brutos)
dbt run --models bronze

# Executar modelos silver (Data Vault)
dbt run --models silver

# Executar modelos gold (marts analíticos)
dbt run --models gold

# Executar testes
dbt test
```

### Pipeline de Unificação de Identidades

O pipeline de unificação de identidades é executado através dos modelos Data Vault:

```bash
# Executar especificamente os modelos de unificação
dbt run --models hub_pessoa link_pessoa_produtor sat_pessoa_detalhes

# Verificar resultados
dbt run --models mart_leads_unificados
```

## Monitoramento e Manutenção

### Verificação de Saúde dos Componentes

Execute verificações regulares de saúde:

```bash
# Script de verificação de saúde
#!/bin/bash

echo "=== Verificação de Saúde Lakehouse Enterprise ==="

# PostgreSQL
echo "PostgreSQL:"
kubectl get pods -n postgresql | grep postgresql

# Hive Metastore
echo "Hive Metastore:"
kubectl get pods -n hive-metastore | grep hive-metastore

# Trino
echo "Trino:"
kubectl get pods -n trino | grep trino

# MinIO
echo "MinIO:"
kubectl get pods -n minio | grep minio

# Verificar conectividade Trino -> Hive Metastore
echo "Testando conectividade Trino -> Hive Metastore:"
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "SHOW SCHEMAS FROM iceberg;"
```

### Otimização de Performance

Execute rotinas de otimização regularmente:

```bash
# Otimização de tabelas Iceberg
kubectl exec -it deployment/dbt -n dbt -- \
  dbt run-operation optimize_iceberg_table --args '{table_name: iceberg.silver.hub_pessoa}'

# Limpeza de snapshots antigos
kubectl exec -it deployment/dbt -n dbt -- \
  dbt run-operation expire_iceberg_snapshots --args '{table_name: iceberg.silver.hub_pessoa, older_than_days: 7}'

# Compactação de arquivos pequenos
kubectl exec -it deployment/dbt -n dbt -- \
  dbt run-operation compact_iceberg_table --args '{table_name: iceberg.silver.sat_pessoa_detalhes}'
```

### Backup e Recuperação

Configure backups regulares:

```bash
# Backup PostgreSQL
kubectl exec -it deployment/postgresql -n postgresql -- \
  pg_dump -h localhost -U hive metastore > /backup/metastore_$(date +%Y%m%d).sql

# Backup configurações MinIO
kubectl exec -it deployment/minio -n minio -- \
  mc mirror local/lakehouse-bronze s3://backup-bucket/bronze/

# Backup metadados Iceberg
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "CALL iceberg.system.create_changelog_view(table => 'iceberg.silver.hub_pessoa');"
```

## Solução de Problemas

### Problemas Comuns

#### Hive Metastore não conecta ao PostgreSQL

**Sintomas:**
- Erro de conexão no log do Hive Metastore
- Trino não consegue acessar catálogo iceberg

**Solução:**
```bash
# Verificar conectividade de rede
kubectl exec -it deployment/hive-metastore -n hive-metastore -- \
  telnet postgresql.postgresql.svc.cluster.local 5432

# Verificar credenciais
kubectl get secret postgresql-credentials -n postgresql -o yaml

# Reiniciar Hive Metastore
kubectl rollout restart deployment/hive-metastore -n hive-metastore
```

#### Trino com performance baixa

**Sintomas:**
- Queries lentas
- Timeout em consultas

**Solução:**
```bash
# Verificar configurações de memória
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "SHOW SESSION;"

# Ajustar configurações de sessão
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "SET SESSION query_max_memory = '16GB';"

# Verificar estatísticas das tabelas
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "ANALYZE TABLE iceberg.silver.hub_pessoa;"
```

#### DBT falha na execução

**Sintomas:**
- Erro de compilação de modelos
- Falha na conexão com Trino

**Solução:**
```bash
# Verificar configuração do profiles.yml
kubectl exec -it deployment/dbt -n dbt -- \
  cat /opt/dbt/profiles/profiles.yml

# Testar conexão
kubectl exec -it deployment/dbt -n dbt -- \
  dbt debug --profiles-dir /opt/dbt/profiles

# Limpar cache
kubectl exec -it deployment/dbt -n dbt -- \
  dbt clean
```

### Logs e Debugging

Para debugging avançado, acesse os logs dos componentes:

```bash
# Logs PostgreSQL
kubectl logs -f deployment/postgresql -n postgresql

# Logs Hive Metastore
kubectl logs -f deployment/hive-metastore -n hive-metastore

# Logs Trino Coordinator
kubectl logs -f deployment/trino-coordinator -n trino

# Logs Trino Workers
kubectl logs -f deployment/trino-worker -n trino

# Logs DBT
kubectl logs -f deployment/dbt -n dbt
```

## Validação da Implementação

### Testes de Funcionalidade

Execute os seguintes testes para validar a implementação:

#### Teste 1: Criação de Tabela Iceberg

```sql
-- Conectar ao Trino e executar
CREATE TABLE iceberg.test.sample_table (
  id BIGINT,
  name VARCHAR,
  created_at TIMESTAMP
) WITH (
  format = 'ICEBERG',
  partitioning = ARRAY['bucket(id, 10)']
);

INSERT INTO iceberg.test.sample_table VALUES 
(1, 'Test Record', CURRENT_TIMESTAMP);

SELECT * FROM iceberg.test.sample_table;
```

#### Teste 2: Pipeline DBT

```bash
# Executar pipeline completo
kubectl exec -it deployment/dbt -n dbt -- \
  dbt run --full-refresh

# Verificar resultados
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "SELECT COUNT(*) FROM iceberg.silver.hub_pessoa;"
```

#### Teste 3: Unificação de Identidades

```sql
-- Testar macro de unificação
SELECT 
  generate_person_hash('João Silva', 'joao@email.com', '11999999999') as hash_completo,
  generate_person_hash('João Silva', 'joao@email.com', NULL) as hash_nome_email,
  generate_person_hash(NULL, 'joao@email.com', '11999999999') as hash_email_telefone
FROM (VALUES (1)) AS t(dummy);
```

### Métricas de Performance

Monitore as seguintes métricas:

| Métrica | Valor Esperado | Comando de Verificação |
|---------|----------------|------------------------|
| Tempo de resposta Trino | < 5s para queries simples | `trino --execute "SELECT COUNT(*) FROM iceberg.silver.hub_pessoa;"` |
| Throughput DBT | > 1000 registros/segundo | Verificar logs do DBT |
| Utilização CPU Trino | < 80% | `kubectl top pods -n trino` |
| Utilização Memória | < 85% | `kubectl top pods --all-namespaces` |
| Latência Hive Metastore | < 100ms | Verificar logs do Trino |

## Próximos Passos

### Configuração de Produção

Para ambiente de produção, considere as seguintes melhorias:

1. **Alta Disponibilidade**: Configure múltiplas réplicas para componentes críticos
2. **Backup Automatizado**: Implemente rotinas de backup automatizadas
3. **Monitoramento Avançado**: Configure Prometheus e Grafana
4. **Segurança**: Implemente autenticação e autorização
5. **Disaster Recovery**: Configure replicação entre regiões

### Otimizações Adicionais

1. **Tuning de Performance**: Ajuste configurações baseado no workload
2. **Compactação Automática**: Configure rotinas de compactação
3. **Particionamento Inteligente**: Otimize estratégias de particionamento
4. **Cache de Metadados**: Configure cache distribuído

## Conclusão

Este tutorial fornece uma base sólida para execução da arquitetura Lakehouse Enterprise com Apache Iceberg no Kubernetes. A implementação da modelagem Data Vault com unificação de identidades permite análises avançadas de leads e campanhas de marketing, proporcionando insights valiosos para tomada de decisão.

A arquitetura atualizada resolve as limitações da versão anterior, especialmente a ausência do Hive Metastore, e introduz otimizações significativas de performance e funcionalidade. Com a execução adequada deste tutorial, você terá uma plataforma de dados moderna, escalável e eficiente para suas necessidades analíticas.

Para suporte adicional ou questões específicas, consulte a documentação oficial dos componentes ou entre em contato com a equipe de desenvolvimento.

---

**Documento gerado por:** Manus AI  
**Última atualização:** Julho 2025  
**Versão:** 2.0

