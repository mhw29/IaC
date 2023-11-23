provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "existing_vpc" {
  id = var.vpc_id
}

resource "aws_subnet" "subnet_public_1a" {
    id = var.subnet_public_1a
}

# Create ecs cluster from cluster.tf module
module "ecs_cluster" {
  source = "./modules/cluster"
  vpc_id = data.aws_vpc.existing_vpc.id
  subnet_public_1a = aws_subnet.subnet_public_1a.id
}



