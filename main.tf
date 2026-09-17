terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "workshop-dev"
    workspaces {
      tags = ["workshop"]
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "current" {}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

#частина 1.13 1.14 1.15
# Блоки moved для рефакторингу без перевидалення бакета
moved {
  from = random_id.bucket_suffix
  to   = module.app_bucket.random_id.bucket_suffix
}

moved {
  from = aws_s3_bucket.buckets3
  to   = module.app_bucket.aws_s3_bucket.this
}

moved {
  from = aws_s3_bucket_versioning.buckets3
  to   = module.app_bucket.aws_s3_bucket_versioning.this
}

#1Основний бакет додатку з версіонуванням та доступом для EC2
module "app_bucket" {
  source            = "./modules"
  bucket_prefix     = "random-prefix"
  enable_versioning = true
  allowed_read_arns = [aws_iam_role.ec2_role.arn]

  tags = {
    Environment = "workshop"
  }
}

#2Другий бакет для логів
module "log_bucket" {
  source            = "./modules"
  bucket_prefix     = "app-logs-prefix"
  enable_versioning = false
  allowed_read_arns = []

  tags = {
    Environment = "workshop"
    Purpose     = "logs"
  }
}

# ЧАСТИНА 1.6 — SSH KEY PAIR
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "generated-ec2-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

output "private_key_pem" {
  description = "Приватний ключ"
  value       = tls_private_key.ssh_key.private_key_pem
  sensitive   = true
}


# ЧАСТИНА 1.7
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

output "default_vpc_id" {
  description = "aws_vpc.default.id"
  value       = data.aws_vpc.default.id
}

output "default_subnet_ids" {
  description = "aws_subnets.default.ids"
  value       = data.aws_subnets.default.ids
}


## Частина 1.8
# data "http" "my_ip" {
#   url = "https://ifconfig.me/"
#   request_headers = {
#     Accept     = "text/plain"
#     User-Agent = "curl/7.68.0"
#   }
# }
# locals {
#   extracted_ip = regex("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}", data.http.my_ip.response_body)
#   my_cidr      = "${local.extracted_ip}/32"
# }

locals {
  my_cidr = "${var.my_ip}/32"
}
output "my_ip" {
  description = "my ip"
  value       = local.my_cidr
}

# ЧАСТИНА 2.9 — IAM ROLE & POLICY ATTACHMENT
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "ec2_s3_read_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Прив'язуємо ARN політики, яку згенерував модуль першого бакета
resource "aws_iam_role_policy_attachment" "attach_s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = module.app_bucket.policy_arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_s3_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# ЧАСТИНА 2.10
variable "ingress_ports" {
  type        = list(number)
  default     = [80, 443, 22]
  description = "Список портів для вхідного трафіку"
}

data "aws_vpc" "selected" {
  default = true
}

resource "aws_security_group" "web_sg" {
  name        = "dynamic-ports-sg"
  description = "Security Group z dynamic ingress ports"
  vpc_id      = data.aws_vpc.selected.id

  dynamic "ingress" {
    for_each = var.ingress_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [local.my_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ЧАСТИНА 2.11
data "aws_subnet" "selected" {
  vpc_id            = data.aws_vpc.selected.id
  default_for_az    = true
  availability_zone = "eu-central-1a"
}

# Використовуємо name бакета з виходу модуля app_bucket
resource "aws_s3_object" "text_file" {
  bucket  = module.app_bucket.bucket_name
  key     = "info.txt"
  content = "Hello from S3 object!"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = templatefile("${path.module}/userdata.tftpl", {
    bucket_name = module.app_bucket.bucket_name
  })

  tags = {
    Name = "WebServer-t3.micro"
  }
}


#частина 4.17
# Генерація випадкового пароля для БД
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Отримання списку підмереж default VPC для Subnet Group
data "aws_subnets" "all_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "postgres-subnet-group"
  subnet_ids = data.aws_subnets.all_default.ids

  tags = {
    Name = "Postgres DB Subnet Group"
  }
}

# Security Group для БД
resource "aws_security_group" "db_sg" {
  name        = "postgres-db-sg"
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id] # Посилання на SG сервера
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS PostgreSQL Інстанс
resource "aws_db_instance" "postgres" {
  identifier             = "workshop-postgres-db"
  allocated_storage      = 20
  max_allocated_storage  = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t4g.micro"
  db_name                = "appdb"
  username               = "dbuser"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}


#частина 4.18
resource "local_file" "lambda_code" {
  filename = "${path.module}/lambda/index.py"
  content  = <<EOF
import boto3
import os

s3 = boto3.client('s3')

def handler(event, context):
    bucket_name = os.environ['BUCKET_NAME']
    file_key = 'info.txt'
    
    try:
        response = s3.get_object(Bucket=bucket_name, Key=file_key)
        content = response['Body'].read().decode('utf-8')
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'text/plain; charset=utf-8'},
            'body': content
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': f"Error reading file from S3: {str(e)}"
        }
EOF
}

# Архівування коду прямо з Terraform
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda/lambda_function.zip"
}

# IAM Роль для виконання Lambda
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "s3_reader_lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Політика читання з бакету
data "aws_iam_policy_document" "lambda_s3_read" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      module.app_bucket.bucket_arn,
      "${module.app_bucket.bucket_arn}/*"
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name   = "lambda_s3_read_policy"
  policy = data.aws_iam_policy_document.lambda_s3_read.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# Створення Lambda функції
resource "aws_lambda_function" "s3_reader" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-file-reader-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = module.app_bucket.bucket_name
    }
  }
}

# Створення публічної адреси 
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.s3_reader.function_name
  authorization_type = "NONE"
}


#частина 4.19 для перевірки
output "db_endpoint" {
  description = "Адреса бази даних"
  value       = aws_db_instance.postgres.endpoint
}

output "db_password" {
  description = "Пароль користувача БД"
  value       = random_password.db_password.result
  sensitive   = true
}

output "lambda_function_url" {
  description = "Публічна url lambda"
  value       = aws_lambda_function_url.lambda_url.function_url
}

#частина 4.21
# terraform plan -generate-config-out=generated.tf
import {
  to = aws_s3_bucket.bucket_create_manual
  id = "s3-manual-create"
}

#4.23 скріни з app teraform io
#4.24
resource "aws_ssm_parameter" "course_d24" {
  name  = "course_d24"
  type  = "SecureString"
  value = "course_d24course_d24course_d24"
}

data "aws_ssm_parameter" "example" {
  name = aws_ssm_parameter.course_d24.name 
}

output "param_value" {
  value     = data.aws_ssm_parameter.example.value
  sensitive = true
}