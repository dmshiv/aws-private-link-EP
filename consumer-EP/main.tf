provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "21.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "consumer-vpc"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "consumer-public-${var.azs[count.index]}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + length(var.azs))
  availability_zone = var.azs[count.index]
  tags = {
    Name = "consumer-private-${var.azs[count.index]}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "consumer-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "consumer-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}



resource "aws_security_group" "private" {
  name        = "consumer-private-sg"
  description = "Allow outbound to VPC Endpoint and SSH inbound"
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

resource "aws_security_group" "endpoint" {
  name        = "consumer-endpoint-sg"
  description = "Allow HTTP to endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]

    // allow ssh so that consumer private ec2 can communicate with provider private ec2






  }
}

resource "aws_security_group" "bastion" {
  name        = "consumer-bastion-sg"
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

resource "aws_instance" "private_ec2" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "my-ec2-key" # Replace with your key pair name
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.private.id]


  tags = {
    Name = "consumer-private-ec2"
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = "my-ec2-key" # Replace with your key pair name
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]


  tags = {
    Name = "consumer-bastion-ec2"
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

//getting vpc end point services link here via ts state file  ****
data "terraform_remote_state" "provider" {
  backend = "local"
  config = {
    path = "../provider-EPS/terraform.tfstate"
  }
}


resource "aws_vpc_endpoint" "this" {
  vpc_id = aws_vpc.main.id
  // getting service name from provider state file
  service_name        = data.terraform_remote_state.provider.outputs.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false
}

output "endpoint_dns" {
  value = aws_vpc_endpoint.this.dns_entry[0].dns_name
}







