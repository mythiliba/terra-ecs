# Define AWS provider
provider "aws" {
  region = "ap-northeast-3"  
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "my-vpc"
  }
}

# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "ap-northeast-3a"  
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}
# Create security group for ecs
resource "aws_security_group" "ecs" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-security-group"
  }
}

#create security group for alb
resource "aws_security_group" "elb" {
  vpc_id = aws_vpc.my_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "alb-security-group"
  }
}

#create a loadbalancer
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = [aws_subnet.public_subnet.id]

  tags = {
    Name = "my-alb"
  }
}

resource "aws_lb_target_group" "my_target_group" {
  name     = "my-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-299"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

resource "aws_internet_gateway" "my_internet_gateway" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "my-internet-gateway"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_internet_gateway.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}


# Create the ECS cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-ecs-cluster"  
}

# Create a task definition for your container
resource "aws_ecs_task_definition" "my_task_definition" {
  family                   = "my-task-def" 
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  # Container definition
  container_definitions = <<EOF
  [
    {
      "name": "helloworld-container",
      "image": "514026916061.dkr.ecr.ap-northeast-3.amazonaws.com/helloworld-ecs",
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000,
          "protocol": "tcp"
        }
      ]

    }
  ]
  EOF
}

# Create an IAM role for ECS task execution
resource "aws_iam_role" "task_execution_role" {
  name = "ecs-task-execution-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "my_task_role" {
  name = "my-task-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}


# Attach the necessary policies to the task execution role
resource "aws_iam_role_policy_attachment" "task_execution_role_attachment" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Create an ECS service using Fargate launch type
resource "aws_ecs_service" "my_service" {
  name            = "my-ecs-service"  
  cluster         = aws_ecs_cluster.my_cluster.arn
  task_definition = aws_ecs_task_definition.my_task_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.public_subnet.id]  
    security_groups = [aws_security_group.ecs.id]  
    assign_public_ip = true
 }


 load_balancer {
    target_group_arn = aws_lb_target_group.my_target_group.arn
    container_name   = "helloworld-container"
    container_port   = 3000
  }
}

# Export necessary values as outputs
output "alb_dns_name" {
  value       = aws_lb.my_alb.dns_name
  description = "ALB DNS Name"
}

output "target_group_arn" {
  value       = aws_lb_target_group.my_target_group.arn
  description = "Target Group ARN"
}

output "subnet_ids" {
  value       = [aws_subnet.public_subnet.id]
  description = "Public Subnet IDs"
}


