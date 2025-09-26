
# Improvements:
# - new cert for mgmt server
# - https webserver
# - https redirection
# - alb flow logs
# - logging and metrics for ec2 instances
# - links to modules 'n stuff
# - deploy CIS hardened ami
# - us alb module instead of resources
# - the management key should be stored in SSM, not locally
# - should update modupe to output/variablize submets
# - Use a standard like <env>-<region>-<resource-type>-<name> everywhere.
# - store state in s3
# - enable logging/metrics
# - add tags throughout


# completed improvements
# - added keys for access
# - added zonal availability

# The next few blocks generate a local keypair and upload it to aws
# https://github.com/btkrausen/hashicorp/blob/master/terraform/Hands-On%20Labs/Section%2004%20-%20Understand%20Terraform%20Basics/15%20-%20Terraform_TLS_Provider.md
# Generate  Keypair

locals {
  global_tags = {
    Project = "coalfirepoc"
  }
}

# Create a private key to access the management server

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

# Create a private key for the management server to access the application servers

resource "tls_private_key" "management_key" {
  algorithm = "RSA"
}

# Save private file in secrets directory (ensure "secrets/*" is included in .gitignore)
resource "local_file" "management_private_key_pem" {
  content  = tls_private_key.management_key.private_key_pem
  filename = "secrets/management_key.pem"
}

# Create keypair in aws
resource "aws_key_pair" "management_key" {
  key_name   = "management_key"
  public_key = tls_private_key.management_key.public_key_openssh
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
      ip_protocol                  = "tcp"
      from_port                    = "80"
      to_port                      = "80"
      referenced_security_group_id = module.alb_sg.id
    }

    "allow_ssh" = {
      ip_protocol                  = "tcp"
      from_port                    = "22"
      to_port                      = "22"
      referenced_security_group_id = module.mgmt_sg.id
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
  name           = "mgmt-sg"
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
  sg_name_prefix = var.aws_region
  name           = "alb-sg"
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
  public_subnets  = [var.public_alb_subnet1, var.public_alb_subnet2, var.public_mgmt_subnet, ]
  private_subnets = [var.private_app_subnet, var.private_app_subnet2, var.private_backend_subnet]

  enable_nat_gateway = true

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

# Copy private key to management server

resource "null_resource" "copy_management_key" {
  depends_on = [module.mgmt_server]

  provisioner "file" {
    content     = tls_private_key.management_key.private_key_pem
    destination = "/home/ubuntu/.ssh/management_key.pem"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.operator_key.private_key_pem
      host        = module.mgmt_server.public_ip[0]
    }
  }
  #apply permissions to local private key
  provisioner "local-exec" {
    command = "chmod 600 ${local_file.operator_private_key_pem.filename}"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/ubuntu/.ssh/management_key.pem",
      "chown ubuntu:ubuntu /home/ubuntu/.ssh/management_key.pem"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.operator_key.private_key_pem
      host        = module.mgmt_server.public_ip[0]
    }
  }
}


# I defined the Auto Scale Group as a resource because coalfires EC2 module is incompatible with current verions of the ASG module (locked to >= 5.15.0, < 6.0.0)
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group

resource "aws_launch_template" "asg_launch_template" {
  name_prefix            = "${var.aws_region}-"
  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_size
  key_name               = "management_key"
  vpc_security_group_ids = [module.app_sg.id]
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
  vpc_zone_identifier       = [module.coalfire_vpc.private_subnets[0], module.coalfire_vpc.private_subnets[2]]

  launch_template {
    id      = aws_launch_template.asg_launch_template.id
    version = "$Latest"
  }
}


module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0" # Or "~> 8.0" if pinned to AWS provider ~>5.0

  name               = "application-lb"
  load_balancer_type = "application"
  vpc_id             = module.coalfire_vpc.vpc_id
  subnets            = [module.coalfire_vpc.public_subnets[1], module.coalfire_vpc.public_subnets[2]]
  security_groups    = [module.alb_sg.id]

  enable_deletion_protection = false

  target_groups = [
    {
      name_prefix      = "app-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      health_check = {
        path                = "/"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
      }
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = local.global_tags
}

# Attachment (update based on your ASG; use one)
resource "aws_autoscaling_attachment" "asg_tg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.asg.name
  lb_target_group_arn    = module.alb.target_group_arns[0]
}
