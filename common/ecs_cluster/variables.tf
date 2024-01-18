variable "cluster_name" {
    description = "Name of the ECS cluster"
    type        = string
}

variable "instance_type" {
    description = "EC2 instance type for ECS cluster instances"
    type        = string

    validation {
        condition     = var.instance_type == "t2.micro" || var.instance_type == "t2.medium"
        error_message = "You must use t2.micro or t2.medium."
    }
}

variable "desired_capacity" {
    description = "Desired number of instances in the ECS cluster"
    type        = number
}