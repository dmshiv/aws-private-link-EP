provider "aws" {
  region = "eu-central-1"
}



data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"] # Amazon's official AMIs

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"] # Adjust the filter to match your requirements
  }
  filter {
    name   = "architecture"
    values = ["x86_64"] # Adjust if you need a different architecture
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"] # Ensure the AMI is HVM type
  }
  filter {
    name   = "state"
    values = ["available"] # Ensure the AMI is available
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"] # Ensure the AMI uses EBS as the root device
  }
  filter {
    name   = "image-type"
    values = ["machine"] # Ensure the AMI is a machine image
  }
  filter {
    name   = "owner-alias"
    values = ["amazon"] # Ensure the AMI is owned by Amazon
  }
  filter {
    name   = "platform-details"
    values = ["Linux/UNIX"] # Ensure the AMI is for Linux/UNIX
  }

}


resource "aws_vpc" "main" {
  cidr_block           = "31.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "provider-vpc"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "provider-public-${var.azs[count.index]}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + length(var.azs))
  availability_zone = var.azs[count.index]
  tags = {
    Name = "provider-private-${var.azs[count.index]}"
  }
}


resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "provider-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "provider-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


// setting SG for private EC2 instances
// --- IGNORE ---

resource "aws_security_group" "private" {
  name        = "provider-private-sg"
  description = "Allow HTTP from VPC Endpoint and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["21.0.0.0/16"] # Consumer VPC CIDR
    description = "Allow HTTP from consumer VPC"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["31.0.0.0/16"]
    description = "Allow HTTP from provider VPC"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_instance" "private_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  key_name               = "my-ec2-key" # Replace with your key pair name
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.private.id]

  user_data = file("${path.module}/user-data.sh")

  tags = {
    Name = "provider-private-ec2"
  }

}



resource "aws_lb" "nlb" {
  name               = "provider-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
}

resource "aws_lb_target_group" "web" {
  name     = "web-target"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id



  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = "80"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    matcher             = "200-399" # Accept any 2xx/3xx status
  }
}




resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

// getting our private ec2 in target grp

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.private_ec2.id
  port             = 80
}

resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]
  tags = {
    Name = "web-service"
  }
}

output "endpoint_service_name" {
  value = aws_vpc_endpoint_service.this.service_name
}

resource "aws_security_group" "bastion" {
  name        = "provider-bastion-sg"
  description = "Allow SSH from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  key_name                    = "my-ec2-key" # Replace with your key pair name
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]


  tags = {
    Name = "provider-bastion-ec2"
  }
}

/// nat gateway

resource "aws_eip" "nat" {

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.gw]
  tags = {
    Name = "provider-nat-gw"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "provider-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


