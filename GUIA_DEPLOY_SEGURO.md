# Guia Completo: Deploy Seguro do Lakehouse Enterprise

## Visão Geral

Este guia fornece instruções detalhadas para expor de forma segura todas as plataformas do Lakehouse Enterprise (ArgoCD, Superset, Trino, etc.) em um servidor Linux com load balancer, SSL/TLS e autenticação centralizada.

## Arquitetura de Segurança

### Componentes de Segurança

| Componente | Função | Porta | Acesso |
|------------|--------|-------|--------|
| **NGINX Ingress** | Load Balancer + Proxy Reverso | 80/443 | Público |
| **OAuth2 Proxy** | Autenticação Centralizada | 4180 | Interno |
| **Cert-Manager** | Gerenciamento SSL/TLS | - | Interno |
| **Network Policies** | Firewall Kubernetes | - | Interno |
| **RBAC** | Controle de Acesso | - | Interno |

### Fluxo de Acesso Seguro

```
Internet → Load Balancer → NGINX Ingress → OAuth2 Proxy → Aplicação
    ↓           ↓              ↓              ↓           ↓
  HTTPS      SSL Term.    Rate Limit    Autenticação   Autorização
```

## Pré-requisitos

### Servidor Linux

- **OS**: Ubuntu 20.04+ ou CentOS 8+
- **CPU**: Mínimo 8 cores, Recomendado 16 cores
- **RAM**: Mínimo 32GB, Recomendado 64GB
- **Storage**: Mínimo 500GB SSD
- **Network**: IP público estático

### Domínio e DNS

- Domínio próprio (ex: `yourdomain.com`)
- Acesso ao DNS para criar subdomínios
- Certificados SSL (Let's Encrypt automático)

### Kubernetes Cluster

- Kubernetes 1.24+
- Helm 3.8+
- kubectl configurado
- Cluster com pelo menos 3 nodes

## Fase 1: Preparação do Ambiente

### 1.1 Configuração do Servidor

#### Atualização do Sistema
```bash
# Ubuntu
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip

# CentOS
sudo yum update -y
sudo yum install -y curl wget git unzip
```

#### Configuração de Firewall
```bash
# Ubuntu (UFW)
sudo ufw enable
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 6443/tcp  # Kubernetes API

# CentOS (firewalld)
sudo systemctl enable firewalld
sudo systemctl start firewalld
sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --reload
```

### 1.2 Configuração DNS

Configure os seguintes subdomínios apontando para o IP público do servidor:

```
argocd.yourdomain.com      → IP_PUBLICO
superset.yourdomain.com    → IP_PUBLICO
trino.yourdomain.com       → IP_PUBLICO
minio.yourdomain.com       → IP_PUBLICO
prefect.yourdomain.com     → IP_PUBLICO
auth.yourdomain.com        → IP_PUBLICO
```

### 1.3 Configuração OAuth Provider

#### Google OAuth (Recomendado)

1. Acesse [Google Cloud Console](https://console.cloud.google.com)
2. Crie um novo projeto ou selecione existente
3. Habilite a API "Google+ API"
4. Vá em "Credentials" → "Create Credentials" → "OAuth 2.0 Client ID"
5. Configure:
   - **Application type**: Web application
   - **Authorized redirect URIs**: `https://auth.yourdomain.com/oauth2/callback`
6. Anote o **Client ID** e **Client Secret**

#### GitHub OAuth (Alternativa)

1. Acesse GitHub → Settings → Developer settings → OAuth Apps
2. Clique "New OAuth App"
3. Configure:
   - **Homepage URL**: `https://yourdomain.com`
   - **Authorization callback URL**: `https://auth.yourdomain.com/oauth2/callback`
4. Anote o **Client ID** e **Client Secret**

## Fase 2: Deploy da Infraestrutura de Segurança

### 2.1 Deploy do NGINX Ingress Controller

```bash
# Aplicar configuração do NGINX Ingress
kubectl apply -f security/ingress/nginx-ingress-controller.yaml

# Aguardar deployment
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Verificar IP externo do Load Balancer
kubectl get svc -n ingress-nginx
```

### 2.2 Deploy do Cert-Manager

```bash
# Aplicar cert-manager
kubectl apply -f security/certificates/cert-manager.yaml

# Aguardar deployment
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=cert-manager \
  --timeout=300s

# Verificar ClusterIssuers
kubectl get clusterissuer
```

### 2.3 Configuração do OAuth2 Proxy

#### Atualizar Secrets
```bash
# Editar arquivo de secrets
nano security/auth/oauth2-proxy.yaml

# Substituir valores:
# - your-google-client-id → Seu Client ID
# - your-google-client-secret → Seu Client Secret  
# - your-32-char-cookie-secret → Gerar com: openssl rand -base64 32

# Aplicar OAuth2 Proxy
kubectl apply -f security/auth/oauth2-proxy.yaml

# Verificar deployment
kubectl get pods -n auth-system
```

### 2.4 Aplicar Network Policies

```bash
# Aplicar políticas de rede
kubectl apply -f security/network-policies.yaml

# Verificar políticas
kubectl get networkpolicy --all-namespaces
```

### 2.5 Configurar RBAC

```bash
# Editar usuários no RBAC
nano security/auth/rbac.yaml

# Substituir emails pelos usuários reais:
# - admin@yourdomain.com
# - dev@yourdomain.com  
# - analyst@yourdomain.com

# Aplicar RBAC
kubectl apply -f security/auth/rbac.yaml

# Verificar roles
kubectl get clusterrole | grep lakehouse
```

## Fase 3: Deploy Seguro das Aplicações

### 3.1 Atualizar Configurações de Domínio

Antes de aplicar os Ingress, atualize todos os arquivos substituindo `yourdomain.com` pelo seu domínio real:

```bash
# Substituir domínio em todos os arquivos
find security/ -name "*.yaml" -exec sed -i 's/yourdomain.com/SEUDOMINIO.com/g' {} \;
```

### 3.2 Deploy do ArgoCD com Ingress Seguro

```bash
# Aplicar Ingress do ArgoCD
kubectl apply -f security/ingress/argocd-ingress.yaml

# Aguardar certificado SSL
kubectl wait --for=condition=Ready certificate/argocd-tls -n argocd --timeout=300s

# Verificar acesso
curl -I https://argocd.SEUDOMINIO.com
```

### 3.3 Deploy do Superset com Ingress Seguro

```bash
# Aplicar Ingress do Superset
kubectl apply -f security/ingress/superset-ingress.yaml

# Aguardar certificado SSL
kubectl wait --for=condition=Ready certificate/superset-tls -n superset --timeout=300s

# Verificar acesso
curl -I https://superset.SEUDOMINIO.com
```

### 3.4 Criar Ingress para Outras Aplicações

#### Trino Ingress
```yaml
# security/ingress/trino-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: trino-ingress
  namespace: trino
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-url: "https://auth.SEUDOMINIO.com/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://auth.SEUDOMINIO.com/oauth2/start?rd=https://$host$request_uri"
    nginx.ingress.kubernetes.io/rate-limit: "50"
spec:
  tls:
  - hosts:
    - trino.SEUDOMINIO.com
    secretName: trino-tls
  rules:
  - host: trino.SEUDOMINIO.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: trino
            port:
              number: 8080
```

#### MinIO Ingress
```yaml
# security/ingress/minio-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minio-ingress
  namespace: minio
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/auth-url: "https://auth.SEUDOMINIO.com/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://auth.SEUDOMINIO.com/oauth2/start?rd=https://$host$request_uri"
    nginx.ingress.kubernetes.io/proxy-body-size: "1000m"
spec:
  tls:
  - hosts:
    - minio.SEUDOMINIO.com
    secretName: minio-tls
  rules:
  - host: minio.SEUDOMINIO.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: minio
            port:
              number: 9001
```

```bash
# Aplicar Ingress adicionais
kubectl apply -f security/ingress/trino-ingress.yaml
kubectl apply -f security/ingress/minio-ingress.yaml
```

## Fase 4: Configurações de Segurança Avançada

### 4.1 Rate Limiting Avançado

```yaml
# security/rate-limiting.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-rate-limit-config
  namespace: ingress-nginx
data:
  rate-limit.conf: |
    # Rate limiting por IP
    limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=200r/m;
    
    # Rate limiting por usuário autenticado
    limit_req_zone $http_x_auth_request_user zone=user:10m rate=1000r/m;
```

### 4.2 Monitoramento de Segurança

```yaml
# security/monitoring/security-monitoring.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: security-alerts
  namespace: monitoring
data:
  security-rules.yml: |
    groups:
    - name: security.rules
      rules:
      - alert: HighFailedLoginRate
        expr: rate(nginx_ingress_controller_requests_total{status=~"401|403"}[5m]) > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High failed login rate detected"
          
      - alert: SuspiciousTraffic
        expr: rate(nginx_ingress_controller_requests_total[5m]) > 1000
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Suspicious traffic pattern detected"
```

### 4.3 Backup de Configurações

```bash
# Script de backup das configurações
#!/bin/bash
# backup-security-config.sh

BACKUP_DIR="/backup/lakehouse-security-$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup dos secrets
kubectl get secrets --all-namespaces -o yaml > $BACKUP_DIR/secrets.yaml

# Backup das configurações
kubectl get configmaps --all-namespaces -o yaml > $BACKUP_DIR/configmaps.yaml

# Backup dos certificados
kubectl get certificates --all-namespaces -o yaml > $BACKUP_DIR/certificates.yaml

# Backup do RBAC
kubectl get clusterroles,clusterrolebindings,roles,rolebindings --all-namespaces -o yaml > $BACKUP_DIR/rbac.yaml

echo "Backup salvo em: $BACKUP_DIR"
```

## Fase 5: Testes e Validação

### 5.1 Testes de Conectividade

```bash
# Testar conectividade HTTPS
curl -I https://argocd.SEUDOMINIO.com
curl -I https://superset.SEUDOMINIO.com
curl -I https://auth.SEUDOMINIO.com

# Testar redirecionamento HTTP → HTTPS
curl -I http://argocd.SEUDOMINIO.com

# Testar certificados SSL
openssl s_client -connect argocd.SEUDOMINIO.com:443 -servername argocd.SEUDOMINIO.com
```

### 5.2 Testes de Autenticação

```bash
# Testar fluxo OAuth
curl -L https://argocd.SEUDOMINIO.com

# Verificar headers de segurança
curl -I https://superset.SEUDOMINIO.com | grep -E "(X-Frame-Options|X-Content-Type-Options|Strict-Transport-Security)"
```

### 5.3 Testes de Rate Limiting

```bash
# Testar rate limiting
for i in {1..150}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://superset.SEUDOMINIO.com
done
```

### 5.4 Validação de Network Policies

```bash
# Testar conectividade entre pods
kubectl exec -it deployment/superset -n superset -- nc -zv trino.trino.svc.cluster.local 8080

# Testar bloqueio de tráfego não autorizado
kubectl exec -it deployment/superset -n superset -- nc -zv postgresql.postgresql.svc.cluster.local 5432
```

## Fase 6: Operação e Manutenção

### 6.1 Monitoramento Contínuo

```bash
# Verificar status dos certificados
kubectl get certificates --all-namespaces

# Verificar logs do Ingress
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Verificar logs do OAuth2 Proxy
kubectl logs -n auth-system deployment/oauth2-proxy

# Verificar métricas de segurança
kubectl top pods --all-namespaces
```

### 6.2 Renovação Automática de Certificados

Os certificados Let's Encrypt são renovados automaticamente pelo cert-manager. Para verificar:

```bash
# Verificar status da renovação
kubectl describe certificate argocd-tls -n argocd

# Forçar renovação manual (se necessário)
kubectl delete certificate argocd-tls -n argocd
kubectl apply -f security/ingress/argocd-ingress.yaml
```

### 6.3 Atualizações de Segurança

```bash
# Atualizar NGINX Ingress
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx

# Atualizar cert-manager
helm upgrade cert-manager jetstack/cert-manager -n cert-manager

# Atualizar OAuth2 Proxy
kubectl set image deployment/oauth2-proxy oauth2-proxy=quay.io/oauth2-proxy/oauth2-proxy:v7.5.0 -n auth-system
```

## Troubleshooting

### Problemas Comuns

#### Certificado SSL não gerado
```bash
# Verificar ClusterIssuer
kubectl describe clusterissuer letsencrypt-prod

# Verificar CertificateRequest
kubectl get certificaterequest --all-namespaces

# Verificar logs do cert-manager
kubectl logs -n cert-manager deployment/cert-manager
```

#### OAuth2 não funcionando
```bash
# Verificar configuração
kubectl get configmap oauth2-proxy-config -n auth-system -o yaml

# Verificar secrets
kubectl get secret oauth2-proxy-secrets -n auth-system

# Verificar logs
kubectl logs -n auth-system deployment/oauth2-proxy
```

#### Rate limiting muito restritivo
```bash
# Ajustar configuração do NGINX
kubectl edit configmap nginx-configuration -n ingress-nginx

# Adicionar/modificar:
# limit-rps: "500"
# limit-rpm: "30000"
```

### Logs Importantes

```bash
# Logs de acesso do NGINX
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep "GET\|POST"

# Logs de autenticação
kubectl logs -n auth-system deployment/oauth2-proxy | grep "authentication"

# Logs de certificados
kubectl logs -n cert-manager deployment/cert-manager | grep "certificate"
```

## Considerações de Produção

### Performance

- **Load Balancer**: Configure múltiplas réplicas do NGINX Ingress
- **Cache**: Habilite cache para recursos estáticos
- **Compressão**: Configure compressão gzip no NGINX
- **Keep-Alive**: Configure conexões persistentes

### Alta Disponibilidade

- **Multi-Zone**: Distribua pods em múltiplas zonas
- **Health Checks**: Configure probes adequados
- **Backup**: Implemente backup automático das configurações
- **Disaster Recovery**: Documente procedimentos de recuperação

### Compliance e Auditoria

- **Logs**: Centralize logs de acesso e autenticação
- **Auditoria**: Habilite audit logs do Kubernetes
- **Retenção**: Configure retenção adequada de logs
- **Alertas**: Configure alertas para eventos de segurança

Este guia fornece uma base sólida para exposição segura do Lakehouse Enterprise. Adapte as configurações conforme suas necessidades específicas de segurança e compliance.

