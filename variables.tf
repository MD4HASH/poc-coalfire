variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_mgmt_subnet" {
  default = "10.0.1.0/24"
}

variable "public_alb_subnet1" {
  default = "10.0.2.0/24"
}

variable "public_alb_subnet2" {
  default = "10.0.3.0/24"
}

variable "private_app_subnet" {
  default = "10.0.4.0/24"
}

variable "private_backend_subnet" {
  default = "10.0.5.0/24"
}

variable "private_backend_subnet2" {
  default = "10.0.6.0/24"
}
variable "instance_size" {
  default = "t2.micro"
}

variable "source_ip" {
  default = "0.0.0.0/0"
}

variable "instance_name" {
  default = "coalfire_poc"

}

variable "instance_volume_size" {
  default = "20"

}
