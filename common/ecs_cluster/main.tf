resource "aws_ecs_cluster" "ecs_cluster" {
    name = var.cluster_name
}

resource "aws_autoscaling_group" "ecs_cluster_asg" {
    name                 = "${var.cluster_name}-asg"
    desired_capacity     = var.desired_capacity
    min_size             = 1
    max_size             = 10
    launch_configuration = aws_launch_configuration.ecs_cluster_lc.name

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_launch_configuration" "ecs_cluster_lc" {
    name_prefix   = "${var.cluster_name}-lc"
    image_id      = "ami-12345678" // Replace with your desired AMI ID
    instance_type = var.instance_type
}

output "ecs_cluster_name" {
    value = aws_ecs_cluster.ecs_cluster.name
}
