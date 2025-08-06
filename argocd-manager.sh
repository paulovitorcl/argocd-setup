#!/bin/bash

# ArgoCD Manager - Gerencie o ArgoCD facilmente
# Subir, parar, limpar e reconfigurar quando quiser

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configurações
CLUSTER_NAME="argocd-local"
NAMESPACE="argocd"
PORT_FORWARD_PORT="8080"
CONFIG_DIR="./argocd-config"

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

echo_title() {
    echo -e "${PURPLE}=== $1 ===${NC}"
}

# Verificar pré-requisitos
check_prerequisites() {
    local missing_tools=()
    
    command -v kubectl >/dev/null || missing_tools+=("kubectl")
    command -v kind >/dev/null || missing_tools+=("kind")
    command -v argocd >/dev/null || missing_tools+=("argocd")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo_error "Ferramentas necessárias não encontradas: ${missing_tools[*]}"
        echo_info "Instale com: brew install ${missing_tools[*]}"
        exit 1
    fi
}

# Verificar se cluster existe
cluster_exists() {
    kind get clusters | grep -q "^${CLUSTER_NAME}$"
}

# Verificar se ArgoCD está instalado
argocd_installed() {
    kubectl get namespace "$NAMESPACE" &>/dev/null
}

# Verificar se port-forward está ativo
port_forward_active() {
    pgrep -f "kubectl port-forward svc/argocd-server" >/dev/null
}

# Obter status do ArgoCD
get_argocd_status() {
    if ! cluster_exists; then
        echo "CLUSTER_DOWN"
    elif ! argocd_installed; then
        echo "NOT_INSTALLED"
    elif ! kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running | grep -q argocd-server; then
        echo "PODS_DOWN"
    elif port_forward_active; then
        echo "RUNNING"
    else
        echo "NO_ACCESS"
    fi
}

# Mostrar status atual
show_status() {
    echo_title "STATUS DO ARGOCD"
    
    local status=$(get_argocd_status)
    
    case $status in
        "CLUSTER_DOWN")
            echo_warn "Cluster kind não existe"
            ;;
        "NOT_INSTALLED")
            echo_warn "Cluster existe mas ArgoCD não está instalado"
            ;;
        "PODS_DOWN")
            echo_warn "ArgoCD instalado mas pods não estão rodando"
            kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
            ;;
        "NO_ACCESS")
            echo_warn "ArgoCD rodando mas sem port-forward ativo"
            ;;
        "RUNNING")
            echo_success "ArgoCD está rodando e acessível!"
            echo_info "URL: https://localhost:$PORT_FORWARD_PORT"
            local password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "N/A")
            echo_info "Usuário: admin"
            echo_info "Senha: $password"
            ;;
    esac
    
    echo
    echo_info "Cluster kind: $(cluster_exists && echo "✅ Existe" || echo "❌ Não existe")"
    echo_info "Namespace ArgoCD: $(argocd_installed && echo "✅ Instalado" || echo "❌ Não instalado")"
    echo_info "Port-forward: $(port_forward_active && echo "✅ Ativo" || echo "❌ Inativo")"
}

# Criar cluster kind
create_cluster() {
    echo_title "CRIANDO CLUSTER KIND"
    
    if cluster_exists; then
        echo_warn "Cluster $CLUSTER_NAME já existe"
        return 0
    fi
    
    cat <<EOF > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
EOF
    
    echo_info "Criando cluster kind..."
    kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml
    kubectl config use-context "kind-$CLUSTER_NAME"
    echo_success "Cluster criado!"
}

# Instalar ArgoCD
install_argocd() {
    echo_title "INSTALANDO ARGOCD"
    
    if argocd_installed; then
        echo_warn "ArgoCD já está instalado"
        return 0
    fi
    
    echo_info "Criando namespace..."
    kubectl create namespace "$NAMESPACE"
    
    echo_info "Instalando ArgoCD..."
    kubectl apply -n "$NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    echo_info "Aguardando pods ficarem prontos..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-dex-server -n "$NAMESPACE"
    
    echo_success "ArgoCD instalado!"
}

# Iniciar port-forward
start_port_forward() {
    if port_forward_active; then
        echo_warn "Port-forward já está ativo"
        return 0
    fi
    
    echo_info "Iniciando port-forward..."
    kubectl port-forward svc/argocd-server -n "$NAMESPACE" "$PORT_FORWARD_PORT:443" >/dev/null 2>&1 &
    sleep 3
    
    if port_forward_active; then
        echo_success "Port-forward ativo na porta $PORT_FORWARD_PORT"
    else
        echo_error "Falha ao iniciar port-forward"
        return 1
    fi
}

# Parar port-forward
stop_port_forward() {
    echo_info "Parando port-forward..."
    pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null || true
    echo_success "Port-forward parado"
}

# Subir ArgoCD completo
start_argocd() {
    echo_title "INICIANDO ARGOCD"
    
    check_prerequisites
    
    local status=$(get_argocd_status)
    
    case $status in
        "CLUSTER_DOWN")
            create_cluster
            install_argocd
            start_port_forward
            ;;
        "NOT_INSTALLED")
            install_argocd
            start_port_forward
            ;;
        "PODS_DOWN")
            echo_info "Reiniciando pods do ArgoCD..."
            kubectl rollout restart deployment -n "$NAMESPACE"
            kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$NAMESPACE"
            start_port_forward
            ;;
        "NO_ACCESS")
            start_port_forward
            ;;
        "RUNNING")
            echo_success "ArgoCD já está rodando!"
            ;;
    esac
    
    # Obter credenciais
    local password=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo_success "ArgoCD está pronto!"
    echo_info "URL: https://localhost:$PORT_FORWARD_PORT"
    echo_info "Usuário: admin"
    echo_info "Senha: $password"
    
    # Login automático no CLI
    echo_info "Fazendo login no ArgoCD CLI..."
    echo "$password" | argocd login "localhost:$PORT_FORWARD_PORT" --username admin --password-stdin --insecure 2>/dev/null || true
}

# Parar ArgoCD (manter cluster)
stop_argocd() {
    echo_title "PARANDO ARGOCD"
    
    stop_port_forward
    
    if argocd_installed; then
        echo_info "Parando pods do ArgoCD..."
        kubectl scale deployment --replicas=0 -n "$NAMESPACE" \
            argocd-server \
            argocd-repo-server \
            argocd-dex-server \
            argocd-redis \
            argocd-notifications-controller \
            argocd-applicationset-controller 2>/dev/null || true
        
        kubectl delete statefulset argocd-application-controller -n "$NAMESPACE" 2>/dev/null || true
    fi
    
    echo_success "ArgoCD parado (cluster mantido)"
}

# Limpar tudo
clean_all() {
    echo_title "LIMPANDO TUDO"
    
    stop_port_forward
    
    if cluster_exists; then
        echo_info "Deletando cluster kind..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    # Limpar arquivos temporários
    rm -f /tmp/kind-config.yaml
    rm -rf "$CONFIG_DIR" 2>/dev/null || true
    
    echo_success "Tudo limpo!"
}

# Reiniciar ArgoCD
restart_argocd() {
    echo_title "REINICIANDO ARGOCD"
    stop_argocd
    sleep 2
    start_argocd
}

# Backup configurações
backup_config() {
    echo_title "FAZENDO BACKUP"
    
    if ! argocd_installed; then
        echo_error "ArgoCD não está instalado"
        return 1
    fi
    
    local backup_dir="$CONFIG_DIR/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    echo_info "Salvando configurações em $backup_dir"
    
    # Backup applications
    kubectl get applications -n "$NAMESPACE" -o yaml > "$backup_dir/applications.yaml" 2>/dev/null || true
    
    # Backup projects
    kubectl get appprojects -n "$NAMESPACE" -o yaml > "$backup_dir/projects.yaml" 2>/dev/null || true
    
    # Backup notifications
    kubectl get configmap argocd-notifications-cm -n "$NAMESPACE" -o yaml > "$backup_dir/notifications-cm.yaml" 2>/dev/null || true
    kubectl get secret argocd-notifications-secret -n "$NAMESPACE" -o yaml > "$backup_dir/notifications-secret.yaml" 2>/dev/null || true
    
    # Backup configurações gerais
    kubectl get configmap argocd-cm -n "$NAMESPACE" -o yaml > "$backup_dir/argocd-cm.yaml" 2>/dev/null || true
    kubectl get configmap argocd-rbac-cm -n "$NAMESPACE" -o yaml > "$backup_dir/argocd-rbac-cm.yaml" 2>/dev/null || true
    
    echo_success "Backup salvo em $backup_dir"
}

# Restaurar configurações
restore_config() {
    local backup_dir="$1"
    
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        echo_error "Diretório de backup não encontrado: $backup_dir"
        echo_info "Backups disponíveis:"
        ls -la "$CONFIG_DIR"/ 2>/dev/null | grep backup || echo "Nenhum backup encontrado"
        return 1
    fi
    
    echo_title "RESTAURANDO BACKUP"
    echo_info "Restaurando de: $backup_dir"
    
    if [ -f "$backup_dir/applications.yaml" ]; then
        kubectl apply -f "$backup_dir/applications.yaml"
    fi
    
    if [ -f "$backup_dir/projects.yaml" ]; then
        kubectl apply -f "$backup_dir/projects.yaml"
    fi
    
    if [ -f "$backup_dir/notifications-cm.yaml" ]; then
        kubectl apply -f "$backup_dir/notifications-cm.yaml"
    fi
    
    if [ -f "$backup_dir/notifications-secret.yaml" ]; then
        kubectl apply -f "$backup_dir/notifications-secret.yaml"
    fi
    
    echo_success "Configurações restauradas!"
}

# Logs em tempo real
show_logs() {
    if ! argocd_installed; then
        echo_error "ArgoCD não está instalado"
        return 1
    fi
    
    echo_title "LOGS DO ARGOCD"
    echo_info "Pressione Ctrl+C para sair"
    echo
    
    kubectl logs -f deployment/argocd-server -n "$NAMESPACE" --tail=50
}

# Aplicar configuração de notifications
setup_notifications() {
    echo_title "CONFIGURANDO NOTIFICATIONS"
    
    if ! argocd_installed; then
        echo_error "ArgoCD não está instalado"
        return 1
    fi
    
    read -p "GitHub Token: " -s GITHUB_TOKEN
    echo
    read -p "GitHub Owner (usuário/org): " GITHUB_OWNER
    read -p "GitHub Repository (app repo): " GITHUB_REPO
    
    # Criar secret
    kubectl create secret generic argocd-notifications-secret \
        --from-literal=github-token="$GITHUB_TOKEN" \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Criar configmap básico
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
            "environment": "{{.app.metadata.labels.env | default \"production\"}}",
            "description": "🚀 {{.app.metadata.name}} deployed via ArgoCD",
            "payload": {
              "application": "{{.app.metadata.name}}",
              "revision": "{{.app.status.sync.revision}}",
              "syncStatus": "{{.app.status.sync.status}}"
            }
          }
  
  trigger.on-deployed: |
    - send: [github-deployment]
      when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
  
  subscriptions: |
    - recipients: [github:$GITHUB_OWNER/$GITHUB_REPO]
      triggers: [on-deployed]
EOF
    
    echo_success "Notifications configuradas!"
}

# Menu interativo
show_menu() {
    echo_title "ARGOCD MANAGER"
    echo "1. 🚀 Iniciar ArgoCD"
    echo "2. ⏹️  Parar ArgoCD"
    echo "3. 🔄 Reiniciar ArgoCD"
    echo "4. 🧹 Limpar tudo"
    echo "5. 📊 Status"
    echo "6. 📋 Logs"
    echo "7. 💾 Backup configurações"
    echo "8. 📥 Restaurar configurações"
    echo "9. 🔔 Configurar notifications"
    echo "0. ❌ Sair"
    echo
}

# Função principal
main() {
    if [ $# -eq 0 ]; then
        # Menu interativo
        while true; do
            show_menu
            read -p "Escolha uma opção: " choice
            echo
            
            case $choice in
                1) start_argocd ;;
                2) stop_argocd ;;
                3) restart_argocd ;;
                4) clean_all ;;
                5) show_status ;;
                6) show_logs ;;
                7) backup_config ;;
                8) 
                    echo "Backups disponíveis:"
                    ls -la "$CONFIG_DIR"/ 2>/dev/null | grep backup || echo "Nenhum backup encontrado"
                    read -p "Digite o nome do diretório do backup: " backup_name
                    restore_config "$CONFIG_DIR/$backup_name"
                    ;;
                9) setup_notifications ;;
                0) echo_info "Tchau! 👋"; exit 0 ;;
                *) echo_error "Opção inválida" ;;
            esac
            
            echo
            read -p "Pressione Enter para continuar..."
            clear
        done
    else
        # Modo command line
        case "$1" in
            "start"|"up") start_argocd ;;
            "stop"|"down") stop_argocd ;;
            "restart") restart_argocd ;;
            "clean") clean_all ;;
            "status") show_status ;;
            "logs") show_logs ;;
            "backup") backup_config ;;
            "restore") restore_config "$2" ;;
            "notifications") setup_notifications ;;
            "help"|"--help"|"-h")
                echo "Uso: $0 [comando]"
                echo
                echo "Comandos:"
                echo "  start/up      - Iniciar ArgoCD"
                echo "  stop/down     - Parar ArgoCD"
                echo "  restart       - Reiniciar ArgoCD"
                echo "  clean         - Limpar tudo"
                echo "  status        - Mostrar status"
                echo "  logs          - Mostrar logs"
                echo "  backup        - Backup configurações"
                echo "  restore DIR   - Restaurar backup"
                echo "  notifications - Configurar notifications"
                echo
                echo "Sem argumentos: modo interativo"
                ;;
            *) 
                echo_error "Comando inválido: $1"
                echo_info "Use '$0 help' para ver comandos disponíveis"
                exit 1
                ;;
        esac
    fi
}

# Executar
main "$@"
