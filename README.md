# Lakehouse Enterprise - Modern Data Stack v2.0

**Versão:** 2.0  
**Atualização:** Julho 2025  
**Arquitetura:** Modern Data Stack com Apache Iceberg

## 🚀 Novidades da Versão 2.0

Esta versão inclui atualizações críticas que tornam a arquitetura completamente funcional com Apache Iceberg:

### ✅ Componentes Adicionados
- **Hive Metastore Standalone**: Componente essencial para Iceberg (CRÍTICO)
- **PostgreSQL Backend**: Base de dados para Hive Metastore
- **Configurações Otimizadas**: Trino, DBT e outros componentes
- **Macros Específicas**: Utilitários para Data Vault e Iceberg
- **Tutorial Kubernetes**: Guia completo de execução

### 🔧 Melhorias Implementadas
- Configurações de performance otimizadas para Iceberg
- Modelagem Data Vault com unificação de identidades
- Pipelines DBT configurados para formato Iceberg
- Monitoramento e métricas específicas
- Procedimentos de manutenção automatizados

## 📋 Visão Geral

O Lakehouse Enterprise é uma arquitetura moderna de dados que combina o melhor dos data lakes e data warehouses, utilizando Apache Iceberg como formato de tabela principal. A arquitetura suporta:

- **Ingestão de Dados**: Facebook Ads, Google Ads, CRMs
- **Modelagem Data Vault**: Hubs, Links e Satellites
- **Unificação de Identidades**: Múltiplas chaves hash para leads
- **Analytics Ready**: Marts otimizados para análise

## 🏗️ Arquitetura

### Componentes Principais

| Componente | Versão | Função | Status |
|------------|--------|--------|--------|
| **PostgreSQL** | 15.4 | Backend Hive Metastore | ✅ Novo |
| **Hive Metastore** | 4.0.0 | Metadados Iceberg | ✅ Novo |
| **Trino** | 430 | Query Engine | ✅ Otimizado |
| **MinIO** | Latest | Object Storage | ✅ Existente |
| **DBT** | 1.6+ | Data Transformation | ✅ Otimizado |
| **Airbyte** | 0.50+ | Data Ingestion | ✅ Existente |
| **Prefect** | 2.10+ | Workflow Orchestration | ✅ Existente |
| **Superset** | 3.0+ | Data Visualization | ✅ Existente |
| **OpenMetadata** | 1.2+ | Data Catalog | ✅ Existente |
| **ArgoCD** | 2.8+ | GitOps | ✅ Existente |

### Fluxo de Dados

```
                    🎯 PREFECT (Orquestrador)
                           ↓
    ┌─────────────────────────────────────────────────────┐
    │                                                     │
    ▼                                                     ▼
📥 AIRBYTE (Ingestão)                           🔄 DBT (Transformações)
    │                                                     │
    ▼                                                     ▼
CRM/Facebook/Google → MinIO (Bronze) → Staging → Silver (Data Vault) → Gold (Marts)
                         │                                │
                         ▼                                ▼
                 Hive Metastore ← PostgreSQL         Superset
                         │
                         ▼
                      Trino
```

### Responsabilidades por Componente

| Componente | Responsabilidade |
|------------|------------------|
| **Prefect** | Orquestração de Airbyte + DBT |
| **Airbyte** | Ingestão APIs → Bronze |
| **DBT** | Transformações Bronze → Silver → Gold |
| **Trino** | Query Engine para Iceberg |
| **Hive Metastore** | Metadados das tabelas Iceberg |

## 🚀 Início Rápido

### Pré-requisitos

- Kubernetes 1.24+
- Helm 3.8+
- kubectl configurado
- ArgoCD instalado
- Mínimo: 16 CPU cores, 64GB RAM, 500GB storage

### Instalação

1. **Clone o repositório:**
```bash
git clone https://github.com/your-org/lakehouse-enterprise
cd lakehouse-enterprise
```

2. **Siga o tutorial completo:**
```bash
# Leia o tutorial detalhado
cat TUTORIAL_KUBERNETES.md
```

3. **Deploy em ordem:**
```bash
# 1. PostgreSQL (Backend Metastore)
kubectl apply -f argocd/apps/postgresql-app.yaml

# 2. MinIO (Object Storage)
kubectl apply -f argocd/apps/minio-app.yaml

# 3. Hive Metastore (CRÍTICO para Iceberg)
kubectl apply -f argocd/apps/hive-metastore-app.yaml

# 4. Trino (Query Engine)
kubectl apply -f argocd/apps/trino-app.yaml

# 5. Demais componentes...
```

### Verificação Rápida

```bash
# Testar conectividade Iceberg
kubectl exec -it deployment/trino-coordinator -n trino -- \
  trino --execute "SHOW CATALOGS;"

# Verificar Hive Metastore
kubectl exec -it deployment/hive-metastore -n hive-metastore -- \
  netstat -tlnp | grep 9083

# Testar DBT
kubectl exec -it deployment/dbt -n dbt -- \
  dbt debug --profiles-dir /opt/dbt/profiles
```

## 📊 Modelagem Data Vault

### Estratégia de Unificação de Identidades

A arquitetura implementa uma estratégia avançada de unificação de identidades para leads:

```sql
-- Exemplo de hash múltiplo
CASE 
    WHEN nome IS NOT NULL AND email IS NOT NULL AND telefone IS NOT NULL 
    THEN MD5(nome || '|' || email || '|' || telefone)
    
    WHEN nome IS NOT NULL AND email IS NOT NULL 
    THEN MD5(nome || '|' || email)
    
    WHEN email IS NOT NULL AND telefone IS NOT NULL 
    THEN MD5(email || '|' || telefone)
    
    -- Outras combinações...
END
```

### Estrutura Data Vault

- **Hub Pessoa**: Entidade central para leads
- **Link Pessoa-Produtor**: Relacionamentos
- **Satellites**: Detalhes e mudanças ao longo do tempo
- **Hash Diff**: Detecção automática de mudanças

## 🔧 Configurações Específicas do Iceberg

### Otimizações Implementadas

- **Format Version 2**: Recursos avançados do Iceberg
- **Compressão ZSTD**: Melhor performance
- **Target File Size**: 128MB otimizado
- **Metadata Cache**: Cache de metadados habilitado
- **Sorted Writing**: Escrita ordenada
- **Dynamic Filtering**: Filtros dinâmicos

### Configurações DBT

```yaml
models:
  lakehouse_enterprise:
    silver:
      +table_type: iceberg
      +table_properties:
        'format-version': '2'
        'write.target-file-size-bytes': '134217728'
        'write.parquet.compression-codec': 'zstd'
```

## 📈 Monitoramento

### Métricas Importantes

- **Performance Trino**: < 5s para queries simples
- **Throughput DBT**: > 1000 registros/segundo
- **Utilização CPU**: < 80%
- **Latência Metastore**: < 100ms

### Comandos de Verificação

```bash
# Health check completo
./scripts/health-check.sh

# Otimização de tabelas
dbt run-operation optimize_iceberg_table

# Limpeza de snapshots
dbt run-operation expire_iceberg_snapshots
```

## 🛠️ Manutenção

### Rotinas Recomendadas

- **Diário**: Verificação de saúde dos componentes
- **Semanal**: Otimização de tabelas Iceberg
- **Mensal**: Limpeza de snapshots antigos
- **Trimestral**: Análise de performance e tuning

### Backup

```bash
# Backup PostgreSQL (Metastore)
pg_dump -h postgresql -U hive metastore > backup_metastore.sql

# Backup configurações
kubectl get configmaps --all-namespaces -o yaml > backup_configs.yaml
```

## 🐛 Solução de Problemas

### Problemas Comuns

1. **Hive Metastore não conecta**: Verificar PostgreSQL
2. **Trino lento**: Ajustar configurações de memória
3. **DBT falha**: Verificar profiles.yml
4. **Iceberg não funciona**: Verificar Hive Metastore

### Logs Importantes

```bash
# Logs críticos
kubectl logs -f deployment/hive-metastore -n hive-metastore
kubectl logs -f deployment/trino-coordinator -n trino
kubectl logs -f deployment/postgresql -n postgresql
```

## 📚 Documentação

- **[TUTORIAL_KUBERNETES.md](./TUTORIAL_KUBERNETES.md)**: Tutorial completo de execução
- **[DEPLOY.md](./DEPLOY.md)**: Instruções de deployment
- **[todo.md](./todo.md)**: Tarefas e melhorias

## 🤝 Contribuição

Para contribuir com o projeto:

1. Fork o repositório
2. Crie uma branch para sua feature
3. Faça commit das mudanças
4. Abra um Pull Request

## 📄 Licença

Este projeto está licenciado sob a MIT License.

## 🆘 Suporte

Para suporte:
- Abra uma issue no GitHub
- Consulte a documentação oficial dos componentes
- Entre em contato com a equipe de desenvolvimento

---

**Desenvolvido por:** Manus AI  
**Última atualização:** Julho 2025  
**Versão:** 2.0 - Apache Iceberg Ready

