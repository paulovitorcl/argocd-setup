# ArgoCD Manager

Gerencie o ArgoCD localmente de forma simples - subir, parar e configurar com um comando.

## 🚀 Quick Start

```bash
# 1. Baixar e dar permissão
chmod +x argocd-manager.sh

# 2. Subir ArgoCD
./argocd-manager.sh start

# 3. Acessar
# URL: https://localhost:8080
# User: admin
# Pass: (será exibida no terminal)
```

## 📋 Comandos Principais

```bash
./argocd-manager.sh start     # ⬆️  Subir ArgoCD
./argocd-manager.sh stop      # ⏹️  Parar ArgoCD  
./argocd-manager.sh restart   # 🔄 Reiniciar
./argocd-manager.sh clean     # 🧹 Limpar tudo
./argocd-manager.sh status    # 📊 Ver status
```

## 🎯 Comandos Rápidos (Opcional)

```bash
# Carregar aliases
source quick-argocd.sh

# Usar comandos curtos
argo-up          # Subir
argo-down        # Parar
argo-status      # Status
argo-clean       # Limpar
```

## 🔔 GitHub Notifications

```bash
# Configurar notifications automáticas
./argocd-manager.sh notifications

# Vai pedir:
# - GitHub Token (com permissões repo + deployments)
# - Owner do repositório (seu usuário/org)
# - Nome do repositório da aplicação
```

## 📱 Criando Aplicações

No ArgoCD UI ou via CLI:

```bash
# Via CLI (após argo-up)
argocd app create my-app \
  --repo https://github.com/user/config-repo \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

# Sincronizar
argocd app sync my-app
```

## 🔧 Troubleshooting

```bash
# Ver logs
./argocd-manager.sh logs

# Status detalhado
./argocd-manager.sh status

# Reset completo se algo der errado
./argocd-manager.sh clean
./argocd-manager.sh start
```

## 📁 Estrutura dos Repositórios

**Repositório de Config (sincronizado com ArgoCD):**
```
config-repo/
├── values.yaml          # Configurações da app
├── deployment.yaml      # Manifests K8s
└── service.yaml
```

**Repositório da App (recebe notifications):**
```
app-repo/
├── src/                 # Código fonte
├── Dockerfile
└── README.md
```

## ⚡ Workflow Diário

```bash
# Manhã
argo-up

# Trabalho
argocd app sync my-app
argocd app list

# Fim do dia
argo-down
```

## 🆘 Problemas Comuns

**ArgoCD não sobe:**
```bash
./argocd-manager.sh clean
./argocd-manager.sh start
```

**Senha não funciona:**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Port 8080 ocupado:**
- Mude a variável `PORT_FORWARD_PORT` no script

## 📦 Requisitos

- Docker
- kubectl  
- kind
- argocd CLI

```bash
# macOS
brew install kubectl kind argocd
```

---

**Tudo pronto!** Execute `./argocd-manager.sh start` e acesse https://localhost:8080
