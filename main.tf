
# Improvements:
# - alb flow logs
# - logging and metrics for ec2 instances
# - dedicated key for mgmt->app ssh access
# - ALB needs two subnets
# - subnets private vs public?
# - links to modules 'n stuff
# - inject https server
# - deploy CIS hardened ami
# - https for apache server
# - drop private key in mgmt server
# - us alb module instead of resources

# The next few blocks generate a local keypair and upload it to aws
# https://github.com/btkrausen/hashicorp/blob/master/terraform/Hands-On%20Labs/Section%2004%20-%20Understand%20Terraform%20Basics/15%20-%20Terraform_TLS_Provider.md
# Generate  Keypair

locals {
  global_tags = {
    Project = "coalfirepoc"
  }
}

# Create a private key to inject into EC2 instances

resource "tls_private_key" "operator_key" {
  algorithm = "RSA"
}

# Save private file in secrets directory (ensure "secrets/*" is included in .gitignore)
resource "local_file" "operator_private_key_pem" {
  content  = tls_private_key.operator_key.private_key_pem
  filename = "secrets/operator_key.pem"
}

# Create keypair in aws
resource "aws_key_pair" "operator_key" {
  key_name   = "operator_key"
  public_key = tls_private_key.operator_key.public_key_openssh
}

# Look up current avaialbility zones

data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

# look up latest ubuntu version for EC2 instances
# Took this from, https://github.com/btkrausen/hashicorp/blob/master/terraform/Hands-On%20Labs/Section%2004%20-%20Understand%20Terraform%20Basics/08%20-%20Intro_to_the_Terraform_Data_Block.md#step-511

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical’s official AWS account ID
}

# https://github.com/Coalfire-CF/terraform-aws-securitygroup
#Security Group 1:  allows SSH from management ec2, allows web traffic from the Application Load Balancer. No
#external traffic


module "app_sg" {
  source         = "github.com/Coalfire-CF/terraform-aws-securitygroup"
  tags           = local.global_tags
  vpc_id         = module.coalfire_vpc.vpc_id
  sg_name_prefix = "${var.aws_region}-"
  name           = "app-sg"

  ingress_rules = { # Ingress rules allowing inbound HTTPS and SSH traffic
    "allow_http1" = {
      ip_protocol = "tcp"
      from_port   = "80"
      to_port     = "80"
      cidr_ipv4   = var.public_alb_subnet1
    }
    "allow_http2" = {
      ip_protocol = "tcp"
      from_port   = "80"
      to_port     = "80"
      cidr_ipv4   = var.public_alb_subnet2
    }
    "allow_ssh" = {
      ip_protocol = "tcp"
      from_port   = "22"
      to_port     = "22"
      cidr_ipv4   = var.public_mgmt_subnet
    }
  }

  egress_rules = {
    "allow_all" = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

# Security Group 2:  allows SSH from a single specific IP or network space only
# Can SSH from this instance to the ASG

module "mgmt_sg" {
  source         = "github.com/Coalfire-CF/terraform-aws-securitygroup" # Path to security group module
  sg_name_prefix = "${var.aws_region}-"
  name           = "mgmg_sg"
  tags           = local.global_tags
  vpc_id         = module.coalfire_vpc.vpc_id

  ingress_rules = { # Ingress rules allowing inbound HTTPS and SSH traffic
    "allow_ssh" = {
      ip_protocol = "tcp"
      from_port   = "22"
      to_port     = "22"
      cidr_ipv4   = var.source_ip
    }
  }
  egress_rules = {
    "allow_all" = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

module "alb_sg" {
  source         = "github.com/Coalfire-CF/terraform-aws-securitygroup"
  sg_name_prefix = "${var.aws_region}-"
  name           = "alb_sg"
  tags           = local.global_tags
  vpc_id         = module.coalfire_vpc.vpc_id

  ingress_rules = { # Ingress rules allowing inbound HTTPS and SSH traffic
    "allow_https" = {
      ip_protocol = "tcp"
      from_port   = "80"
      to_port     = "80"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  egress_rules = {
    "allow_all" = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

}

# I chose to use the terraform vpc provider because the coalfire provider does not provide assigned subnets in its outputs
# This makes it cumbersome to work with subnets in other blocks because they cannot be referenced as variables.
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest

module "coalfire_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.3.0"

  name = "main-vpc"
  cidr = var.vpc_cidr

  azs = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  # Create five subnets, not three as instructed.    I didn't want to put the alb in the same subnet as the management server 
  # and the ALB module requires at least two subnets for HA
  public_subnets  = [var.public_mgmt_subnet, var.public_alb_subnet1, var.public_alb_subnet2]
  private_subnets = [var.private_app_subnet, var.private_backend_subnet]

  enable_nat_gateway = true
  single_nat_gateway = false

  tags = local.global_tags
}

# https://github.com/Coalfire-CF/terraform-aws-ec2
module "mgmt_server" {
  source = "github.com/Coalfire-CF/terraform-aws-ec2"

  name = var.instance_name

  ami                        = data.aws_ami.ubuntu.id
  ec2_instance_type          = var.instance_size
  vpc_id                     = module.coalfire_vpc.vpc_id
  subnet_ids                 = [module.coalfire_vpc.public_subnets[0]]
  associate_public_ip        = true
  ec2_key_pair               = aws_key_pair.operator_key.key_name
  additional_security_groups = [module.mgmt_sg.id]
  ebs_kms_key_arn            = "alias/aws/ebs"
  ebs_optimized              = false

  # Storage
  root_volume_size = var.instance_volume_size

  # Tagging
  global_tags = {}
}

# Defining the Auto Scale Group as a resource because coalfires EC2 module is incompatible with current verions of the ASG module (locked to >= 5.15.0, < 6.0.0)
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group

resource "aws_launch_template" "asg_launch_template" {
  name_prefix            = "${var.aws_region}-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_size
  key_name               = "operator_key"
  vpc_security_group_ids = [module.alb_sg.id]
  user_data = base64encode(<<-EOF
  #!/bin/bash
  sudo apt update -y
  sudo apt install apache2 -y
  sudo systemctl start apache2
  sudo systemctl enable apache2
  echo "hello coalfire" | sudo tee /var/www/html/index.html
  sudo chown www-data:www-data /var/www/html/index.html
  EOF
  )
}

resource "aws_autoscaling_group" "asg" {


  name                      = "application ASG"
  max_size                  = 6
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  vpc_zone_identifier       = [module.coalfire_vpc.private_subnets[0]]

  launch_template {
    id      = aws_launch_template.asg_launch_template.id
    version = "$Latest"
  }
}

# Create ALB

resource "aws_lb" "alb" {
  name                       = "application-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [module.alb_sg.id]
  subnets                    = [module.coalfire_vpc.public_subnets[1], module.coalfire_vpc.public_subnets[2]]
  enable_deletion_protection = false

}

# Create ALB target group

resource "aws_lb_target_group" "alb_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.coalfire_vpc.vpc_id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

resource "aws_autoscaling_attachment" "asg_tg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.asg.name
  lb_target_group_arn    = aws_lb_target_group.alb_tg.arn
}
