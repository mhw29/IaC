provider "aws" {
    region = "us-east-1"
}

module "ecs_cluster" {
    source = "../ecs_cluster"
    cluster_name="test-cluster"
    instance_type="t2.medium"
    desired_capacity=2
}