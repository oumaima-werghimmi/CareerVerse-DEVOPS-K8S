output "ecr_backend"  { value = aws_ecr_repository.repo["careerverse-backend"].repository_url }
output "ecr_frontend" { value = aws_ecr_repository.repo["careerverse-frontend"].repository_url }
output "eks_cluster"  { value = module.eks.cluster_name }
output "rds_endpoint" { value = aws_db_instance.postgres.address }
output "kubeconfig_cmd" { value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}" }
