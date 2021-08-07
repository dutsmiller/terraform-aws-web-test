variable "email" {
  description = "email value for tagging"
  type        = string
}

variable "purpose" {
  description = "purpose value for tagging"
  type        = string
}

locals {
  tags = {
    owner_email   = var.email
    support_email = var.email
    purpose       = var.purpose
  }

  user_data = <<-EOT
    #!/bin/bash
    yum update -y
    amazon-linux-extras install nginx1 -y
    systemctl enable nginx
    cat <<EOF > /usr/share/nginx/html/index.html
    <html>
    <body>
    <div style="font-size: 5em;color: blue;text-align:center;font-weight:bold;">
    Hello World!
    </div>
    <div style="font-size: 2em;color: blue;text-align:center;font-weight:bold;">
    Welcome to AWS
    </div>
    </body>
    </html>
    EOF
    systemctl start nginx
  EOT
}

provider "aws" {
  region = "us-east-1"
}

data "http" "my_ip" {
  url = "https://ifconfig.me"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "amazon_linux_arm64" {
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  owners = ["137112412989"]
}

resource "random_string" "random" {
  length  = 8
  number  = false
  special = false
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_private_key" {
  filename = "${path.module}/web.pem"
  content  = tls_private_key.ssh.private_key_pem

  file_permission = "0600"
}

resource "aws_key_pair" "kp" {
  key_name   = random_string.random.result
  public_key = tls_private_key.ssh.public_key_openssh
  tags       = local.tags
}

resource "aws_security_group" "sg" {
  name        = random_string.random.result
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  tags = merge({ name = "${random_string.random.result} - ${local.tags.purpose}" }, local.tags)

  ingress {
    description = "SSH from TF IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.http.my_ip.body}/32"]
  }

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux_arm64.id
  instance_type = "t4g.micro"
  key_name      = aws_key_pair.kp.key_name

  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg.id]

  user_data_base64 = base64encode(local.user_data)

  tags = merge({ name = "${random_string.random.result} - ${local.tags.purpose}" }, local.tags)
}

output "instance_id" {
  value = aws_instance.web.id
}

output "instance_name" {
  value = "${random_string.random.result} - ${local.tags.purpose}"
}

output "ssh_command" {
  value = "ssh -i web.pem ec2-user@${aws_instance.web.public_ip}"
}

output "http_url" {
  value = "http://${aws_instance.web.public_ip}"
}
