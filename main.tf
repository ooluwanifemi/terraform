#Declaring the Cloud Provider to use
provider "aws" {
  region = "us-east-1"
}


#Declaring variables that will be needed for future use in the this file
locals {
  vpc_cidr = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
}



#Creating a VPC called main-vpc

resource "aws_vpc" "main" {
  cidr_block = local.vpc_cidr

  tags = {
    Name = "main-vpc"
  }
}




#Creating subnets for the VPC

resource "aws_subnet" "public" {
  count = length(local.public_subnet_cidrs)

  cidr_block = local.public_subnet_cidrs[count.index]
  vpc_id      = aws_vpc.main.id
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}


#Creating an internet gateway

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw" 
  }
}


#Creating a route table

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}


#Creating route table association

resource "aws_route_table_association" "public" {
  count = length(local.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}



#Creating security group

resource "aws_security_group" "public" {
  name        = "public-sg"
  description = "Allow inbound and outbound traffic for public subnets"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "public_inbound" {
  security_group_id = aws_security_group.public.id

  type        = "ingress"
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "public_outbound" {
  security_group_id = aws_security_group.public.id

  type        = "egress"
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}


#creating the ec2 instance 

resource "aws_instance" "public" {
  count = 2 * length(local.public_subnet_cidrs)

  ami           = "ami-042e8287309f5df03" # Ubuntu 20.04 AMI ID for us-east-1 region
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[count.index % length(local.public_subnet_cidrs)].id
  key_name      = "Staging Key" # Replace with your key pair name

  vpc_security_group_ids = [aws_security_group.public.id]

  user_data = <<-EOF
#!/bin/bash
apt update
wget https://opendatasciencelabsaslicense.s3.amazonaws.com/bash.sh
chmod 777 ./bash.sh
bash ./bash.sh
./bash.sh
                 EOF

  tags = {
    Name = "public-instance-${count.index + 1}"
  }
}



#creating a load balancer
resource "aws_lb" "main" {
  name               = "main-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public.id]
  subnets            = aws_subnet.public.*.id
}

resource "aws_lb_target_group" "main" {
  name     = "main-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

resource "aws_lb_target_group_attachment" "main" {
  count = 2 * length(local.public_subnet_cidrs)

  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.public[count.index].id
  port             = 80
}
