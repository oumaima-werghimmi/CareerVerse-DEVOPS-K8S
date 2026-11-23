
# Usage (depuis la racine du projet) :
# .\deploy\scripts\deploy-minikube.ps1

$ErrorActionPreference = "Stop"
$ctx = "minikube"

# --------------------------------------------------
# 1/6 - Demarrage de Minikube
# --------------------------------------------------

Write-Host "1/6 Minikube (4 CPU / 5 Go) ..." -ForegroundColor Cyan

$status = minikube status -p minikube -f '{{.Host}}' 2>$null

if ($status -ne "Running") {
    minikube start -p minikube --cpus=4 --memory=5120 --driver=docker

    if ($LASTEXITCODE -ne 0) {
        throw "Erreur : impossible de demarrer Minikube."
    }
}

kubectl config use-context $ctx

# --------------------------------------------------
# 2/6 - Build des images dans Minikube
# --------------------------------------------------

Write-Host "2/6 Build des images DANS Minikube ..." -ForegroundColor Cyan

Write-Host "Build backend..."
minikube image build -p minikube -t careerverse-backend:local .\backend

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors du build de l'image backend."
}

Write-Host "Build frontend..."
minikube image build -p minikube -t careerverse-frontend:local .\frontend

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors du build de l'image frontend."
}

Write-Host "Images construites avec succes." -ForegroundColor Green

# --------------------------------------------------
# 3/6 - Stack Prometheus + Grafana
# --------------------------------------------------

Write-Host "3/6 Stack Prometheus + Grafana ..." -ForegroundColor Cyan

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

if ($LASTEXITCODE -ne 0) {
    Write-Host "Le depot Helm existe peut-etre deja."
}

helm repo update

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors de la mise a jour des depots Helm."
}

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack `
    -n monitoring `
    --create-namespace `
    -f .\deploy\monitoring\kube-prometheus-stack-values.yaml `
    --wait `
    --timeout 10m

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors du deploiement Prometheus/Grafana."
}

# --------------------------------------------------
# 4/6 - Application CareerVerse
# --------------------------------------------------

Write-Host "4/6 Application ..." -ForegroundColor Cyan

kubectl --context=$ctx delete job backend-migrate `
    -n careerverse --ignore-not-found

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors de la suppression de l'ancien job."
}

kubectl --context=$ctx apply -f .\deploy\k8s\00-app.yaml

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors de l'application des manifests Kubernetes."
}

kubectl --context=$ctx rollout restart deploy/backend deploy/frontend -n careerverse

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors du redemarrage des deployments."
}

# --------------------------------------------------
# 5/6 - Monitoring : alertes et dashboard
# --------------------------------------------------

Write-Host "5/6 ServiceMonitor + alertes + dashboard ..." -ForegroundColor Cyan

kubectl --context=$ctx apply -f .\deploy\k8s\10-monitoring-rules.yaml

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors du deploiement des regles de monitoring."
}

kubectl --context=$ctx apply -f .\deploy\k8s\20-grafana-dashboard.yaml

if ($LASTEXITCODE -ne 0) {
    throw "Erreur lors du deploiement du dashboard Grafana."
}

# --------------------------------------------------
# 6/6 - Attente des pods
# --------------------------------------------------

Write-Host "6/6 Attente des pods ..." -ForegroundColor Cyan

kubectl --context=$ctx rollout status deploy/backend `
    -n careerverse --timeout=300s

if ($LASTEXITCODE -ne 0) {
    throw "Le backend n'est pas pret."
}

kubectl --context=$ctx rollout status deploy/frontend `
    -n careerverse --timeout=300s

if ($LASTEXITCODE -ne 0) {
    throw "Le frontend n'est pas pret."
}

kubectl --context=$ctx rollout status deploy/monitoring-grafana `
    -n monitoring --timeout=300s

if ($LASTEXITCODE -ne 0) {
    throw "Grafana n'est pas pret."
}

# --------------------------------------------------
# Verification finale
# --------------------------------------------------

Write-Host "`nEtat des pods CareerVerse :" -ForegroundColor Cyan

kubectl --context=$ctx get pods -n careerverse

Write-Host "`nEtat des pods Monitoring :" -ForegroundColor Cyan

kubectl --context=$ctx get pods -n monitoring

# --------------------------------------------------
# Acces aux services
# --------------------------------------------------

Write-Host @"

==================================================
       DEPLOIEMENT CAREERVERSE TERMINE
==================================================

Ouvre 3 terminaux PowerShell :

1. FRONTEND :
kubectl port-forward svc/frontend -n careerverse 8080:80

http://localhost:8080

2. GRAFANA :
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

http://localhost:3000

Identifiants : admin / admin

3. PROMETHEUS :
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090

http://localhost:9090/targets

==================================================

"@ -ForegroundColor Green
