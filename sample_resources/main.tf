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
 image_id      = "ami-0b74aeb97fba885ea"
 instance_type = "t3.micro"

 key_name               = "dell_machine"
 vpc_security_group_ids = [aws_security_group.security_group.id]
 iam_instance_profile {
   name ="ecsInstanceRole"
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
 desired_capacity    = 1
 max_size            = 1
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

########################ECS Cluster############################################
resource "aws_ecs_cluster" "ecs_cluster" {
 name = "my-ecs-cluster"
}

resource "aws_ecs_capacity_provider" "ecs_capacity_provider" {
 name = "test1"

 auto_scaling_group_provider {
   auto_scaling_group_arn = aws_autoscaling_group.ecs_asg.arn

   managed_scaling {
     maximum_scaling_step_size = 1000
     minimum_scaling_step_size = 1
     status                    = "ENABLED"
     target_capacity           = 2
   }
 }
}

resource "aws_ecs_cluster_capacity_providers" "example" {
 cluster_name = aws_ecs_cluster.ecs_cluster.name

 capacity_providers = [aws_ecs_capacity_provider.ecs_capacity_provider.name]

 default_capacity_provider_strategy {
   base              = 1
   weight            = 100
   capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
 }
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_cloudwatch_logs" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}


resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/my-ecs-log-group" // Replace with your desired log group name

  retention_in_days = 30 // Optional: Configure log retention period (in days)

  tags = {
    Name = "ECS Log Group"
  }
}


resource "aws_ecs_task_definition" "ecs_task_definition" {
 family             = "my-ecs-task"
 network_mode       = "awsvpc"
 execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
 cpu                = 256
 runtime_platform {
   operating_system_family = "LINUX"
   cpu_architecture        = "X86_64"
 }
 container_definitions = jsonencode([
   {
     name      = "dockergs"
     image     = "nginx:latest"
     cpu       = 256
     memory    = 512
     essential = true
     portMappings = [
       {
         containerPort = 80
         hostPort      = 80
         protocol      = "tcp"
       }
     ]
    logConfiguration = {
        logDriver = "awslogs"
        options = {
            awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
        }
    }
   }
 ])
}

resource "aws_ecs_service" "ecs_service" {
 name            = "my-ecs-service"
 cluster         = aws_ecs_cluster.ecs_cluster.id
 task_definition = aws_ecs_task_definition.ecs_task_definition.arn
 desired_count   = 2

 network_configuration {
   subnets         = [aws_subnet.subnet.id, aws_subnet.subnet-2.id]
   security_groups = [aws_security_group.security_group.id]
 }

 force_new_deployment = true
 placement_constraints {
   type = "distinctInstance"
 }

 capacity_provider_strategy {
   capacity_provider = aws_ecs_capacity_provider.ecs_capacity_provider.name
   weight            = 100
 }

 load_balancer {
   target_group_arn = aws_lb_target_group.ecs_tg.arn
   container_name   = "dockergs"
   container_port   = 80
 }

 depends_on = [aws_autoscaling_group.ecs_asg]
}