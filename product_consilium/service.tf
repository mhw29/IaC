resource "aws_ecs_service" "django_service" {
  name            = "product_consilium-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.product_consilium_task_def.arn
  launch_type     = "EC2"

  desired_count = 1

  network_configuration {
    subnets = [aws_subnet.example_subnet.id]
    security_groups = [aws_security_group.ecs_sg.id]
  }
}
