# Terraform Web Application Deployment

A simple, working example of deploying a web application to AWS using Terraform. Creates a public-facing Node.js web server on EC2 with a VPC, internet gateway, and public subnet—everything needed to serve a website to the internet.

## What This Does

This project demonstrates **complete end-to-end infrastructure deployment**. You run one command, and 5 minutes later you have a live web server accessible from anywhere on the internet.

**Resources created:**
- 1 VPC with a public subnet
- 1 Internet Gateway (connection to the internet)
- 1 Route Table (directs traffic to/from the internet)
- 1 Security Group (allows HTTP, HTTPS, SSH)
- 1 EC2 instance (runs the Node.js app)

## Quick Start

### Prerequisites
- AWS account with CLI configured
- Terraform installed

### Deploy
```bash
git clone <this-repo>
cd terraform-web-app
terraform init
terraform apply
```

Type `yes` when prompted.

### Access the App
After apply completes, you'll see a web_server_url 

Open that URL in your browser. You should see the "Terraform Web App is Running!" page.

**Note:** If the page doesn't load immediately, wait 60 seconds. The EC2 instance needs time to boot and run the Node.js script.

### Destroy
```bash
terraform destroy
```

Type `yes`. Everything deleted in ~2 minutes.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    The Internet (0.0.0.0/0)              │
│                          ↓                               │
│                   Internet Gateway                       │
│                          ↓                               │
│              AWS VPC (10.0.0.0/16)                       │
│  ┌───────────────────────────────────────────────────┐  │
│  │                                                   │  │
│  │  Public Subnet (10.0.1.0/24)                      │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │                                             │  │  │
│  │  │  EC2 Instance (t2.micro)                    │  │  │
│  │  │  ┌─────────────────────────────────────┐   │  │  │
│  │  │  │ Node.js Web Server                  │   │  │  │
│  │  │  │ Port 80 (HTTP)                      │   │  │  │
│  │  │  │ http://54.123.45.67                 │   │  │  │
│  │  │  └─────────────────────────────────────┘   │  │  │
│  │  │                                             │  │  │
│  │  │  Security Group: web-sg                     │  │  │
│  │  │  - Ingress: 80 (HTTP) from 0.0.0.0/0       │  │  │
│  │  │  - Ingress: 443 (HTTPS) from 0.0.0.0/0     │  │  │
│  │  │  - Ingress: 22 (SSH) from 0.0.0.0/0        │  │  │
│  │  │  - Egress: All traffic outbound             │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  │                                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### How It Works

1. **Internet Gateway**: Connects your VPC to the public internet. Without it, no outside traffic can reach your instances.

2. **Public Subnet**: Has `map_public_ip_on_launch = true`, so EC2 instances automatically get public IPs.

3. **Route Table**: Contains a rule that says "route all traffic to 0.0.0.0/0 (the entire internet) through the internet gateway."

4. **Security Group**: Allows:
   - Port 80 (HTTP) — so you can visit the website
   - Port 443 (HTTPS) — for encrypted connections
   - Port 22 (SSH) — so you can debug if needed
   - All outbound traffic — so the app can download packages

5. **User Data Script**: When the EC2 instance starts:
   - Installs Node.js
   - Creates a simple HTTP server
   - Starts listening on port 80
   - Serves HTML to anyone who visits

## Key Concepts

### Public vs. Private Subnets

This subnet is **public** because:
- It has a route to the internet gateway
- Instances get public IP addresses
- The route table directs `0.0.0.0/0` to the IGW

A **private** subnet (for future learning):
- No route to the internet gateway
- Instances have no public IPs
- Accessed only from within the VPC
- Perfect for databases, internal services

### Security Group Permissions

The security group allows:
```
Ingress (inbound):
  - Port 80 from anywhere (0.0.0.0/0)
  - Port 443 from anywhere (0.0.0.0/0)
  - Port 22 from anywhere (0.0.0.0/0)

Egress (outbound):
  - All protocols to anywhere (0.0.0.0/0)
```

This is why the app can:
- Receive web traffic (port 80)
- Download Node.js packages (outbound)
- Be accessed via SSH (port 22)

### User Data (Bootstrap)

The `user_data` script runs once when the instance boots:
```bash
#!/bin/bash
yum update -y              # Update OS packages
yum install -y nodejs      # Install Node.js
# Create and start a web server
```

This is how you automate server setup. No manual SSH-ing to install packages. Terraform handles it.

## File Structure

```
terraform-web-app/
├── main.tf              # All resource definitions + app code
└── README.md            # This file
```

### main.tf Breakdown

- **data "aws_ami"**: Finds the latest Amazon Linux 2 AMI
- **aws_vpc**: Creates isolated network
- **aws_internet_gateway**: Connects VPC to internet
- **aws_subnet**: Public subnet for web server
- **aws_route_table**: Routing rules
- **aws_route_table_association**: Links route table to subnet
- **aws_security_group**: Network firewall rules
- **locals**: Stores the Node.js app code
- **aws_instance**: EC2 server running the app
- **output**: Displays the web server URL after deployment


## Troubleshooting

### "Connection refused" or page won't load

The EC2 instance needs 60+ seconds to boot and run the user data script. Wait and refresh.

Check progress:
```bash
aws ec2 describe-instances --region us-east-1 \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,StatusChecksFailed]'
```

When `StatusChecksFailed` shows `0`, the instance is ready.

### Page loads but shows error/blank

SSH into the instance and check logs:
```bash
ssh -i ~/.aws/your-key.pem ec2-user@<IP_ADDRESS>
tail -50 /var/log/cloud-init-output.log
ps aux | grep node
```

### Security group allows traffic but can't connect

Wait 3 minutes after `terraform apply`. Security group rules take time to propagate.

### "Error: creating security group... Already exists"

Someone else created a security group with the same name in your AWS account. Change the name:
```hcl
resource "aws_security_group" "web" {
  name   = "web-sg-${random_id.suffix.hex}"  # Add random suffix
  ...
}

resource "random_id" "suffix" {
  byte_length = 4
}
```

### "InvalidAMIID.NotFound"

The `data "aws_ami"` block searches for AMIs. If search returns nothing, the region might not have that image. Verify your `provider` region matches:
```hcl
provider "aws" {
  region = "us-east-1"  # Try us-west-2 if us-east-1 fails
}
```

## What You Just Learned

### 1. Public vs. Private Infrastructure
You created a **public** web server. In real applications:
- Web servers and load balancers: public subnets
- Databases and background jobs: private subnets
- Everything in VPC: private networks, no direct internet access

### 2. Security Groups Are Firewalls
The security group is the only thing preventing strangers from SSH-ing into your instance. Good security means:
- Close everything by default
- Open only what you need
- Use CIDR blocks or other security groups to limit access

### 3. User Data Automates Setup
Instead of SSH-ing and running commands, `user_data` bootstraps the instance. This is how:
- Auto-scaling works (new instances spin up pre-configured)
- Infrastructure reproducibility works (exact same setup every time)
- You avoid manual configuration drift

### 4. Internet Gateway Is Essential
Without the IGW, your VPC is isolated. With it, you're connected to the world. Most applications need at least one IGW in the VPC (even if not all instances use it).

### 5. Route Tables Direct Traffic
Route tables answer: "When I want to send traffic to X, what do I do?" 
- Traffic to 10.0.0.0/16 → stay in the VPC (local route, automatic)
- Traffic to 0.0.0.0/0 (everything else) → send to the internet gateway
