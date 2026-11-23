# Deploiement CareerVerse : Minikube + Prometheus/Grafana, puis AWS (Terraform)

## A. Local (Minikube)
```powershell
.\deploy\scripts\deploy-minikube.ps1
```
Puis 3 port-forward (affiches a la fin du script). Grafana : http://localhost:3000 (admin/admin),
dashboard **CareerVerse - Overview**. Prometheus : http://localhost:9090/targets -> `careerverse-backend` doit etre UP.

Generer du trafic pour voir les courbes :
```powershell
1..300 | % { curl.exe -s -o NUL http://localhost:8080/api/careers/ ; curl.exe -s -o NUL http://localhost:8080/api/inexistant }
```

## B. AWS
```bash
cd deploy/terraform
terraform init && terraform apply
$(terraform output -raw kubeconfig_cmd)
# build + push des images vers ECR (URLs dans les outputs), remplacer image: dans k8s/00-app.yaml,
# retirer le Deployment/PVC "database" et mettre DATABASE_URL depuis Secrets Manager (RDS).
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  -f ../monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f ../k8s/10-monitoring-rules.yaml -f ../k8s/20-grafana-dashboard.yaml
terraform destroy   # IMPORTANT apres la demo : EKS + NAT coutent ~ 5 $/jour
```
