# Guia de Deploy - Lakehouse Enterprise

## Pré-requisitos

### Infraestrutura
- Cluster Kubernetes 1.20+
- kubectl configurado
- Helm 3.x instalado
- Acesso de administrador ao cluster
- Pelo menos 32GB RAM e 8 CPUs disponíveis
- 500GB de storage persistente

### Ferramentas
```bash
# Instalar kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Instalar Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verificar instalação
kubectl version --client
helm version
```

## Deploy com ArgoCD (Recomendado)

### 1. Instalar ArgoCD
```bash
# Aplicar manifesto de instalação
kubectl apply -f argocd/install-argocd.yaml

# Aguardar pods ficarem prontos
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Obter senha inicial do admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 2. Acessar ArgoCD UI
```bash
# Port forward para acessar UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Acessar: https://localhost:8080
# Usuário: admin
# Senha: obtida no passo anterior
```

### 3. Deploy das Aplicações
```bash
# Aplicar todas as aplicações ArgoCD
kubectl apply -f argocd/apps/

# Verificar status das aplicações
kubectl get applications -n argocd
```

### 4. Monitorar Deploy
```bash
# Verificar pods em todos os namespaces
kubectl get pods --all-namespaces

# Verificar logs específicos
kubectl logs -f deployment/minio -n minio
kubectl logs -f deployment/airbyte-server -n airbyte
kubectl logs -f deployment/trino-coordinator -n trino
```

## Deploy Manual (Alternativo)

### 1. Adicionar Repositórios Helm
```bash
helm repo add minio https://charts.min.io/
helm repo add airbyte https://airbytehq.github.io/helm-charts
helm repo add trino https://trinodb.github.io/charts
helm repo add prefect https://prefecthq.github.io/prefect-helm
helm repo add superset https://apache.github.io/superset
helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator
helm repo add openmetadata https://helm.open-metadata.org
helm repo update
```

### 2. Instalar Componentes
```bash
# MinIO
helm install minio minio/minio -f infra/minio/values.yaml --create-namespace --namespace minio

# Airbyte
helm install airbyte airbyte/airbyte -f infra/airbyte/values.yaml --create-namespace --namespace airbyte

# Trino
helm install trino trino/trino -f infra/trino/values.yaml --create-namespace --namespace trino

# Prefect
helm install prefect prefect/prefect-server -f infra/prefect/values.yaml --create-namespace --namespace prefect

# Superset
helm install superset superset/superset -f infra/superset/values.yaml --create-namespace --namespace superset

# Spark Operator
helm install spark-operator spark-operator/spark-operator -f infra/spark-operator/values.yaml --create-namespace --namespace spark-operator

# OpenMetadata
helm install openmetadata openmetadata/openmetadata -f infra/openmetadata/values.yaml --create-namespace --namespace openmetadata
```

## Configuração Pós-Deploy

### 1. Configurar MinIO
```bash
# Port forward para acessar console
kubectl port-forward svc/minio-console -n minio 9001:9001

# Acessar: http://localhost:9001
# Usuário: minioadmin
# Senha: minioadmin123

# Criar buckets adicionais se necessário
```

### 2. Configurar Airbyte
```bash
# Port forward para acessar UI
kubectl port-forward svc/airbyte-webapp-svc -n airbyte 8000:80

# Acessar: http://localhost:8000
# Configurar conexões com Facebook Ads, Google Ads
# Importar configuração: pipelines/airbyte/facebook_ads_to_minio.json
```

### 3. Configurar Trino
```bash
# Port forward para acessar
kubectl port-forward svc/trino -n trino 8080:8080

# Testar conexão
curl http://localhost:8080/v1/info

# Conectar via cliente SQL
trino --server localhost:8080 --catalog iceberg --schema lakehouse
```

### 4. Configurar dbt
```bash
# Instalar dbt no ambiente Prefect
pip install dbt-trino

# Executar modelos
cd pipelines/dbt
dbt deps
dbt run
dbt test
```

### 5. Configurar Prefect
```bash
# Port forward para acessar UI
kubectl port-forward svc/prefect-server -n prefect 4200:4200

# Acessar: http://localhost:4200
# Registrar flows: pipelines/prefect/etl_minio_iceberg.py
```

### 6. Configurar Superset
```bash
# Port forward para acessar UI
kubectl port-forward svc/superset -n superset 8088:8088

# Acessar: http://localhost:8088
# Usuário: admin
# Senha: admin123

# Importar dashboard: bi/superset_dashboard_example.yaml
```

## Verificação de Saúde

### 1. Verificar Conectividade
```bash
# Testar conectividade entre componentes
kubectl run test-pod --image=curlimages/curl --rm -it -- sh

# Dentro do pod:
curl http://minio.minio.svc.cluster.local:9000/minio/health/live
curl http://trino.trino.svc.cluster.local:8080/v1/info
curl http://airbyte-server-svc.airbyte.svc.cluster.local:8001/api/v1/health
```

### 2. Verificar Logs
```bash
# Verificar logs de cada componente
kubectl logs -f deployment/minio -n minio
kubectl logs -f deployment/airbyte-server -n airbyte
kubectl logs -f deployment/trino-coordinator -n trino
kubectl logs -f deployment/prefect-server -n prefect
kubectl logs -f deployment/superset -n superset
```

### 3. Verificar Recursos
```bash
# Verificar uso de recursos
kubectl top nodes
kubectl top pods --all-namespaces
```

## Configuração de Dados

### 1. Configurar Fontes de Dados
- Facebook Ads: Configurar access token e account ID
- Google Ads: Configurar credenciais OAuth
- CRM: Configurar conexões específicas

### 2. Executar Pipeline Inicial
```bash
# Executar pipeline Prefect manualmente
python pipelines/prefect/etl_minio_iceberg.py
```

### 3. Verificar Dados
```bash
# Conectar ao Trino e verificar tabelas
trino --server localhost:8080 --catalog iceberg --schema lakehouse

# Executar queries de teste
SHOW TABLES;
SELECT COUNT(*) FROM hub_pessoa;
SELECT COUNT(*) FROM sat_pessoa_detalhes;
```

## Monitoramento

### 1. Métricas
- Verificar dashboards do Superset
- Monitorar logs do Prefect
- Acompanhar métricas do OpenMetadata

### 2. Alertas
- Configurar alertas para falhas de pipeline
- Monitorar uso de recursos
- Verificar qualidade dos dados

## Troubleshooting

### Problemas Comuns

1. **Pods não iniciam**
   - Verificar recursos disponíveis
   - Verificar logs: `kubectl logs <pod-name>`
   - Verificar eventos: `kubectl describe pod <pod-name>`

2. **Conectividade entre serviços**
   - Verificar DNS interno do cluster
   - Verificar network policies
   - Testar conectividade com curl

3. **Problemas de storage**
   - Verificar PVCs: `kubectl get pvc --all-namespaces`
   - Verificar storage class disponível
   - Verificar permissões de acesso

4. **Problemas de performance**
   - Aumentar recursos nos values.yaml
   - Verificar configurações de JVM (Trino)
   - Otimizar queries dbt

### Comandos Úteis
```bash
# Restart de deployment
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# Verificar configuração
kubectl get configmap <configmap-name> -o yaml

# Debug de pod
kubectl exec -it <pod-name> -- /bin/bash

# Verificar secrets
kubectl get secrets --all-namespaces
```

## Backup e Recuperação

### 1. Backup de Dados
```bash
# Backup do MinIO
mc mirror minio/lakehouse-bronze s3://backup-bucket/bronze/
mc mirror minio/lakehouse-silver s3://backup-bucket/silver/
mc mirror minio/lakehouse-gold s3://backup-bucket/gold/
```

### 2. Backup de Configurações
```bash
# Backup de configurações Kubernetes
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml
```

### 3. Recuperação
- Restaurar dados do backup
- Reaplicar configurações
- Verificar integridade dos dados

## Atualizações

### 1. Atualizar Componentes
```bash
# Atualizar via Helm
helm upgrade minio minio/minio -f infra/minio/values.yaml -n minio
helm upgrade airbyte airbyte/airbyte -f infra/airbyte/values.yaml -n airbyte
```

### 2. Atualizar Modelos dbt
```bash
cd pipelines/dbt
dbt run --full-refresh
```

### 3. Atualizar Pipelines
- Atualizar código Python
- Redeployar flows Prefect
- Testar pipelines

---

**Suporte**: Para dúvidas e problemas, consulte a documentação ou abra uma issue no repositório.

