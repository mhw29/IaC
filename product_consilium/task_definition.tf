resource "aws_ecs_task_definition" "product_consilium_task_def" {
  family                   = "product_consilium"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name  = "django",
    image = "your-django-app-image:latest",
    ports = [{
      containerPort = 3000
      hostPort      = 3000
    }]
  }])
}
