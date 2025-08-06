#!/bin/bash

# Comandos rápidos para ArgoCD
# Uso: source quick-argocd.sh

# Configurações
CLUSTER_NAME="argocd-local"
NAMESPACE="argocd"
PORT="8080"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funções de utilidade
argocd_info() { echo -e "${GREEN}[ArgoCD]${NC} $1"; }
argocd_warn() { echo -e "${YELLOW}[ArgoCD]${NC} $1"; }
argocd_error() { echo -e "${RED}[ArgoCD]${NC} $1"; }

# Subir ArgoCD rapidamente
argo-up() {
    argocd_info "Subindo ArgoCD..."
    
    # Criar cluster se não existir
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        argocd_info "Criando cluster..."
        kind create cluster --name "$CLUSTER_NAME"
    fi
    
    # Usar contexto correto
    kubectl config use-context "kind-$CLUSTER_NAME"
    
    # Instalar ArgoCD se não existir
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        argocd_info "Instalando ArgoCD..."
        kubectl create namespace "$NAMESPACE"
        kubectl apply -n "$NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$NAMESPACE"
    fi
    
    # Port forward
    if ! pgrep -f "kubectl port-forward svc/argocd-server" >/dev/null; then
        argocd_info "Iniciando port-forward..."
        kubectl port-forward svc/argocd-server -n "$NAMESPACE" "$PORT:443" >/dev/null 2>&1 &
        sleep 3
    fi
    
    local password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    argocd_info "ArgoCD rodando!"
    echo "URL: https://localhost:$PORT"
    echo "User: admin"
    echo "Pass: $password"
    
    # Login CLI
    echo "$password" | argocd login "localhost:$PORT" --username admin --password-stdin --insecure 2>/dev/null
}

# Parar ArgoCD
argo-down() {
    argocd_info "Parando ArgoCD..."
    pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null || true
    
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        kubectl scale deployment --replicas=0 -n "$NAMESPACE" \
            argocd-server argocd-repo-server argocd-dex-server \
            argocd-redis argocd-notifications-controller \
            argocd-applicationset-controller 2>/dev/null || true
        kubectl delete statefulset argocd-application-controller -n "$NAMESPACE" 2>/dev/null || true
    fi
    
    argocd_info "ArgoCD parado"
}

# Limpar tudo
argo-clean() {
    argocd_warn "Limpando tudo..."
    pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null || true
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
    argocd_info "Tudo limpo!"
}

# Reiniciar
argo-restart() {
    argo-down
    sleep 2
    argo-up
}

# Status
argo-status() {
    echo "=== STATUS ARGOCD ==="
    
    if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        argocd_warn "Cluster não existe"
        return
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        argocd_warn "ArgoCD não instalado"
        return
    fi
    
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null
    
    echo
    if pgrep -f "kubectl port-forward svc/argocd-server" >/dev/null; then
        argocd_info "Port-forward ativo"
        local password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
        echo "URL: https://localhost:$PORT"
        echo "User: admin"
        echo "Pass: $password"
    else
        argocd_warn "Port-forward inativo"
    fi
}

# Password
argo-pass() {
    kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    echo
}

# Logs
argo-logs() {
    local component=${1:-server}
    kubectl logs -f deployment/argocd-$component -n "$NAMESPACE" --tail=50
}

# Apps
argo-apps() {
    argocd app list
}

# Sync app
argo-sync() {
    local app=$1
    if [ -z "$app" ]; then
        argocd_error "Uso: argo-sync <app-name>"
        return 1
    fi
    argocd app sync "$app"
}

# Quick notifications setup
argo-notify() {
    argocd_info "Configuração rápida de notifications..."
    
    read -p "GitHub Token: " -s GITHUB_TOKEN
    echo
    read -p "GitHub Owner: " GITHUB_OWNER
    read -p "GitHub Repo: " GITHUB_REPO
    
    kubectl create secret generic argocd-notifications-secret \
        --from-literal=github-token="$GITHUB_TOKEN" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: $NAMESPACE
data:
  service.github: |
    token: \$github-token
  template.github-deployment: |
    webhook:
      github:
        method: POST
        path: /repos/$GITHUB_OWNER/$GITHUB_REPO/deployments
        body: |
          {
            "ref": "{{.app.status.sync.revision}}",
            "environment": "production",
            "description": "🚀 {{.app.metadata.name}} deployed"
          }
  trigger.on-deployed: |
    - send: [github-deployment]
      when: app.status.sync.status == 'Synced'
  subscriptions: |
    - recipients: [github:$GITHUB_OWNER/$GITHUB_REPO]
      triggers: [on-deployed]
EOF
    
    argocd_info "Notifications configuradas!"
}

# Help
argo-help() {
    echo "=== COMANDOS ARGOCD ==="
    echo "argo-up        - Subir ArgoCD"
    echo "argo-down      - Parar ArgoCD"
    echo "argo-restart   - Reiniciar ArgoCD"
    echo "argo-clean     - Limpar tudo"
    echo "argo-status    - Ver status"
    echo "argo-pass      - Ver senha admin"
    echo "argo-logs [component] - Ver logs (server, repo-server, etc)"
    echo "argo-apps      - Listar aplicações"
    echo "argo-sync <app> - Sincronizar app"
    echo "argo-notify    - Configurar notifications"
    echo "argo-help      - Esta ajuda"
}

# Mostrar comandos disponíveis ao carregar
argocd_info "Comandos ArgoCD carregados!"
echo "Use 'argo-help' para ver todos os comandos"
echo "Comandos principais: argo-up, argo-down, argo-status"
