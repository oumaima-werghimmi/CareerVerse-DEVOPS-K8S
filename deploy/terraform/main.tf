terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.60" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" { region = var.region }

data "aws_availability_zones" "az" { state = "available" }
locals {
  azs  = slice(data.aws_availability_zones.az.names, 0, 2)
  tags = { Project = "careerverse", ManagedBy = "terraform" }
}

# ---------- Reseau ----------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "careerverse"
  cidr = "10.0.0.0/16"
  azs  = local.azs

  public_subnets   = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # 1 seul NAT = moins cher (projet etudiant)

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
  tags                = local.tags
}

# ---------- Registres d'images ----------
resource "aws_ecr_repository" "repo" {
  for_each             = toset(["careerverse-backend", "careerverse-frontend"])
  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

# ---------- Kubernetes (EKS) ----------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = "careerverse"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
  tags = local.tags
}

# ---------- Base PostgreSQL (RDS) ----------
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_security_group" "rds" {
  name   = "careerverse-rds"
  vpc_id = module.vpc.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  tags = local.tags
}

resource "aws_db_instance" "postgres" {
  identifier              = "careerverse"
  engine                  = "postgres"
  engine_version          = "17"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  db_name                 = "careerverse"
  username                = "careerverse"
  password                = random_password.db.result
  db_subnet_group_name    = module.vpc.database_subnet_group_name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  storage_encrypted       = true
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  tags                    = local.tags
}

# Secret consomme par l'appli (DATABASE_URL) - a lire via External Secrets / kubectl
resource "aws_secretsmanager_secret" "db_url" {
  name                    = "careerverse/database-url"
  recovery_window_in_days = 0
}
resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql://careerverse:${random_password.db.result}@${aws_db_instance.postgres.address}:5432/careerverse"
}
