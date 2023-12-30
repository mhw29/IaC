
variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = ["subnet-0d0b5b581c5afaca5", "subnet-05b09161909c9336e"]
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "account_id" {
    description = "The AWS account ID"
    type        = string
}

variable "image_tag" {
    description = "The image tag"
    type        = string
}

variable "image_repo" {
    description = "The image repository"
    type        = string
}

variable "region" {
    description = "The AWS region"
    type        = string
}