provider "aws" {
        region = "us-east-1"
}   

resource "aws_vpc" "vpc" {
        cidr_block = "172.32.0.0/16"
        enable_dns_hostnames = true
        tags = {
                Name = "sample-vpc"
        }
}

#Set in az 1a
resource "aws_subnet" "subnet" {
    vpc_id     = aws_vpc.vpc.id
    availability_zone = "us-east-1a" # Set the availability zone to "1a"
    cidr_block = cidrsubnet(aws_vpc.vpc.cidr_block, 8, 1)
    map_public_ip_on_launch = true
    tags = {
        Name = "sample-subnet"
    }
}

resource "aws_subnet" "subnet-2" {
  vpc_id     = aws_vpc.vpc.id
  availability_zone = "us-east-1b" # Set the availability zone to "1b"
  cidr_block = cidrsubnet(aws_vpc.vpc.cidr_block, 8, 2)
  map_public_ip_on_launch = true
  tags = {
    Name = "sample-subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "default" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
}

resource "aws_route_table_association" "a" {
    subnet_id      = aws_subnet.subnet.id
    route_table_id = aws_route_table.default.id
}

resource "aws_route_table_association" "b" {
    subnet_id      = aws_subnet.subnet-2.id
    route_table_id = aws_route_table.default.id
}




resource "aws_service_discovery_private_dns_namespace" "example" {
  name        = "service"
  vpc         = aws_vpc.vpc.id
}

resource "aws_service_discovery_service" "example" {
  name = "sample"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.example.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}


########################Security Group############################################
resource "aws_security_group" "security_group" {
 name   = "ecs-security-group"
 vpc_id = aws_vpc.vpc.id

 ingress {
   from_port   = 0
   to_port     = 0
   protocol    = -1
   self        = "false"
   cidr_blocks = ["0.0.0.0/0"]
   description = "any"
 }

 egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }
}

########################EC2 Instance############################################
resource "aws_launch_template" "ecs_lt" {
 name_prefix   = "ecs-template"
 image_id      = "ami-0230bd60aa48260c6"
 instance_type = "t3.micro"

 key_name               = "ec2ecsglog"
 vpc_security_group_ids = [aws_security_group.security_group.id]
 iam_instance_profile {
   name = "ecsInstanceRole"
 }

 block_device_mappings {
   device_name = "/dev/xvda"
   ebs {
     volume_size = 30
     volume_type = "gp2"
   }
 }

 tag_specifications {
   resource_type = "instance"
   tags = {
     Name = "ecs-instance"
   }
 }

 user_data = filebase64("${path.module}/ecs.sh")
}

resource "aws_autoscaling_group" "ecs_asg" {
 vpc_zone_identifier = [aws_subnet.subnet.id, aws_subnet.subnet-2.id]
 desired_capacity    = 2
 max_size            = 3
 min_size            = 1

 launch_template {
   id      = aws_launch_template.ecs_lt.id
   version = "$Latest"
 }

 tag {
   key                 = "AmazonECSManaged"
   value               = true
   propagate_at_launch = true
 }
}

resource "aws_lb" "ecs_alb" {
 name               = "ecs-alb"
 internal           = false
 load_balancer_type = "application"
 security_groups    = [aws_security_group.security_group.id]
 subnets            = [aws_subnet.subnet.id, aws_subnet.subnet-2.id]

 tags = {
   Name = "ecs-alb"
 }
}

resource "aws_lb_listener" "ecs_alb_listener" {
 load_balancer_arn = aws_lb.ecs_alb.arn
 port              = 80
 protocol          = "HTTP"

 default_action {
   type             = "forward"
   target_group_arn = aws_lb_target_group.ecs_tg.arn
 }
}

resource "aws_lb_target_group" "ecs_tg" {
 name        = "ecs-target-group"
 port        = 80
 protocol    = "HTTP"
 target_type = "ip"
 vpc_id      = aws_vpc.vpc.id

 health_check {
   path = "/"
 }
}