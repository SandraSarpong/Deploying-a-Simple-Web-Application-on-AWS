terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

# Internet Gateway (makes the VPC reachable from the internet)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Public Subnet (instances here can reach the internet)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

# Route Table (tells traffic where to go)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group (allow HTTP + HTTPS + SSH)
resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH (for debugging)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# User Data Script (runs when EC2 starts)
locals {
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y nodejs

    # Create a simple web app
    mkdir -p /var/www/app
    cd /var/www/app

    cat > app.js << 'APPEOF'
    const http = require('http');
    const hostname = '0.0.0.0';
    const port = 80;

    const server = http.createServer((req, res) => {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/html');
      
      const html = `
        <!DOCTYPE html>
        <html>
        <head>
          <title>Terraform Web App</title>
          <style>
            body { font-family: Arial; margin: 50px; }
            .container { max-width: 600px; }
            h1 { color: #ff9900; }
            .info { background: #f0f0f0; padding: 20px; border-radius: 5px; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>🎉 Terraform Web App is Running!</h1>
            <div class="info">
              <p><strong>Hostname:</strong> $${hostname}</p>
              <p><strong>Server Time:</strong> $${new Date().toISOString()}</p>
              <p>This page is served by an EC2 instance launched with Terraform.</p>
              <p>Infrastructure as code works. ✅</p>
            </div>
          </div>
        </body>
        </html>
      `;
      
      res.end(html);
    });

    server.listen(port, hostname, () => {
      console.log(`Server running at http://$${hostname}:$${port}/`);
    });
    APPEOF

    # Run the app
    node app.js &
  EOF
}

# EC2 Instance (runs the web app)
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = base64encode(local.user_data)

  tags = {
    Name = "terraform-web-app"
  }
}

# Outputs
output "web_server_url" {
  description = "URL to access the web application"
  value       = "http://${aws_instance.web.public_ip}"
}

output "web_server_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "web_server_dns" {
  description = "Public DNS name of the web server"
  value       = aws_instance.web.public_dns
}