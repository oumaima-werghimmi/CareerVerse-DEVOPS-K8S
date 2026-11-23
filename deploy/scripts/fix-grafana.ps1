# Diagnostic "connection refused" sur Grafana
kubectl --context=minikube get pods -n monitoring
Write-Host "`n--- Etat du conteneur grafana (Restart / OOMKilled ?) ---"
kubectl --context=minikube describe pod -n monitoring -l app.kubernetes.io/name=grafana | Select-String -Pattern "State:|Reason:|Restart Count|Exit Code|OOMKilled|Warning"
Write-Host "`n--- Logs grafana (derniere execution plantee) ---"
kubectl --context=minikube logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana --previous --tail=40 2>$null
kubectl --context=minikube logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana --tail=40
Write-Host "`n--- Ressources du noeud ---"
kubectl --context=minikube top node 2>$null
