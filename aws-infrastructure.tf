# Configuração do Provedor AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Região padrão da AWS (N. Virginia)
}

# 1. Criação da Rede Segura (VPC)
resource "aws_vpc" "devops_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "devops-challenge-vpc"
  }
}

# Subnet Pública para receber o tráfego da internet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.devops_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

# Gateway de Internet para conectar a rede à web
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.devops_vpc.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.devops_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.rt.id
}

# 2. Grupo de Segurança (Firewall liberando a porta 8080)
resource "aws_security_group" "ecs_sg" {
  name        = "devops-challenge-sg"
  description = "Liberar porta 8080 para o desafio"
  vpc_id      = aws_vpc.devops_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Cluster ECS (Onde o container vai rodar)
resource "aws_ecs_cluster" "devops_cluster" {
  name = "devops-challenge-cluster"
}

# Definição da Tarefa (Configuração do Container e da Secret do Desafio)
resource "aws_ecs_task_definition" "app_task" {
  family                   = "devops-challenge-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "devops-container"
    image     = "nginx:alpine"
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]
    environment = [
      { name = "MY_SECRET", value = "On3H1torL3sS" } # Secret exigida injetada no ambiente
    ]
  }])
}

# Serviço que mantém o container rodando na AWS
resource "aws_ecs_service" "app_service" {
  name            = "devops-challenge-service"
  cluster         = aws_ecs_cluster.devops_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_subnet.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}
