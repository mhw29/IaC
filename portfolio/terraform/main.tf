provider "aws" {
  region = "us-east-1"
}

# Create an IAM role for the EKS cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "portfolio-eks-cluster-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
    ],
  })
}

# Attach the necessary policies to the EKS cluster role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "describe_subnets" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "route53" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
  role       = aws_iam_role.eks_cluster_role.name
}

# Create the EKS cluster
resource "aws_eks_cluster" "cluster" {
  name     = "portfolio-cluster-${var.environment}"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = var.subnet_ids
  }
}

# Create an IAM role for the EKS node group
resource "aws_iam_role" "eks_node_group_role" {
  name = "portfolio-eks-node-group-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
    ],
  })
}

# Attach necessary policies to the EKS node group role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_read" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_describe_subnets" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_route53" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
  role       = aws_iam_role.eks_node_group_role.name
}

# Create an EKS node group
resource "aws_eks_node_group" "portfolio_node_group" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "portfolio-node-group-${var.environment}"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]  # Set the instance size to t3.micro

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_read
  ]
}

resource "aws_ecr_repository" "portfolio" {
    name = "portfolio"
}

resource "aws_codebuild_project" "portfolio_project" {
    name          = "portfolio"
    description   = "Build images for portfolio project"
    build_timeout = 60

    source {
        type            = "GITHUB"
        location        = "https://github.com/mhw29/portfolio"
        git_clone_depth = 1
        buildspec       = "buildspec.yml"
    }

    environment {
        compute_type = "BUILD_GENERAL1_SMALL"
        image        = "aws/codebuild/standard:4.0"
        type         = "LINUX_CONTAINER"
        
        environment_variable {
            name  = "AWS_ACCOUNT_ID"
            value = var.account_id
        }
        
        environment_variable {
            name  = "IMAGE_TAG"
            value = var.image_tag
        }

        environment_variable {
            name  = "IMAGE_REPO_NAME"
            value = var.image_repo
        }

        environment_variable {
            name  = "AWS_DEFAULT_REGION"
            value = var.region
        }
    }

    artifacts {
        type = "NO_ARTIFACTS"
    }

    service_role = aws_iam_role.portfolio_project_role.arn
}

resource "aws_iam_role" "portfolio_project_role" {
    name = "portfolio_project_role"

    assume_role_policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "codebuild.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    })
}

resource "aws_iam_role" "portfolio_pipeline_role" {
  name = "portfolio_pipeline_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "portfolio_pipeline_attachment" {
    role       = aws_iam_role.portfolio_pipeline_role.name
    policy_arn = aws_iam_policy.pipeline_role_policy.arn
}

resource "aws_iam_role_policy_attachment" "portfolio_project_attachment" {
    role       = aws_iam_role.portfolio_project_role.name
    policy_arn = aws_iam_policy.pipeline_role_policy.arn
}

resource "aws_iam_policy" "ecr_push_policy" {
    name        = "ecr-push-policy"
    description = "ECR push policy"

    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:GetRepositoryPolicy",
                    "ecr:DescribeRepositories",
                    "ecr:ListImages",
                    "ecr:DescribeImages",
                    "ecr:BatchGetImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                    "ecr:PutImage"
                ],
                "Resource": "*"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "ecr_push_attachment" {
    role       = aws_iam_role.portfolio_project_role.name
    policy_arn = aws_iam_policy.ecr_push_policy.arn
}

resource "aws_iam_role_policy_attachment" "portfolio_project_cloudwatch_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccessV2"
  role       = aws_iam_role.portfolio_project_role.name
}

resource "aws_iam_role_policy_attachment" "portfolio_project_secrets_manager_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.portfolio_project_role.name
}

resource "aws_iam_role_policy_attachment" "portfolio_project_s3_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.portfolio_project_role.name
}

resource "aws_iam_role_policy_attachment" "portfolio_project_codestar_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeStarFullAccess"
  role       = aws_iam_role.portfolio_project_role.name
}

# AWS CodePipeline
resource "aws_codepipeline" "portfolio_pipeline" {
  name     = "portfolio-pipeline"
  role_arn = aws_iam_role.portfolio_pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifact_store.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      
      configuration = {
        ConnectionArn    = "arn:aws:codestar-connections:us-east-1:943337485558:connection/53e3ac89-0880-451d-9245-ddc5068ede47"
        FullRepositoryId = "mhw29/portfolio"
        BranchName       = "main" # Specify the branch name
        DetectChanges    = "false" # Set to false to use webhook filters
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      version          = "1"
      run_order        = 1

      configuration = {
        ProjectName = aws_codebuild_project.portfolio_project.name
      }
    }
  }
  # Add additional stages as needed (e.g., Deploy)
}

# Webhook Filter for CodePipeline to trigger on specific Git tags
resource "aws_codepipeline_webhook" "portfolio_webhook" {
  name            = "portfolio-webhook"
  authentication  = "UNAUTHENTICATED"  # No HMAC authentication needed with CodeStar Connections
  target_action   = "GitHub_Source"
  target_pipeline = aws_codepipeline.portfolio_pipeline.name

  filter {
    json_path    = "$.ref"
    match_equals = "refs/tags/v{[0-9]+.[0-9]+.[0-9]+}"
  }

  # Exclude tags containing 'alpha'
  filter {
    json_path    = "$.ref"
    match_equals = "!refs/tags/*alpha*"
  }
}

# S3 Bucket for Pipeline Artifacts
resource "aws_s3_bucket" "pipeline_artifact_store" {
  bucket = "portfolio-pipeline-artifacts"
  acl    = "private"
}

# Codepipeline role policy
resource "aws_iam_policy" "pipeline_role_policy" {
  name = "pipeline-role-policy"
  policy = jsonencode({
    "Version": "2012-10-17",
      "Statement": [
          {
              "Action": [
                  "iam:PassRole"
              ],
              "Resource": "*",
              "Effect": "Allow",
              "Condition": {
                  "StringEqualsIfExists": {
                      "iam:PassedToService": [
                          "cloudformation.amazonaws.com",
                          "elasticbeanstalk.amazonaws.com",
                          "ec2.amazonaws.com",
                          "ecs-tasks.amazonaws.com"
                      ]
                  }
              }
          },
          {
              "Action": [
                  "codecommit:CancelUploadArchive",
                  "codecommit:GetBranch",
                  "codecommit:GetCommit",
                  "codecommit:GetRepository",
                  "codecommit:GetUploadArchiveStatus",
                  "codecommit:UploadArchive"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "codedeploy:CreateDeployment",
                  "codedeploy:GetApplication",
                  "codedeploy:GetApplicationRevision",
                  "codedeploy:GetDeployment",
                  "codedeploy:GetDeploymentConfig",
                  "codedeploy:RegisterApplicationRevision"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "codestar-connections:UseConnection"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "elasticbeanstalk:*",
                  "ec2:*",
                  "elasticloadbalancing:*",
                  "autoscaling:*",
                  "cloudwatch:*",
                  "s3:*",
                  "sns:*",
                  "cloudformation:*",
                  "rds:*",
                  "sqs:*",
                  "ecs:*"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "lambda:InvokeFunction",
                  "lambda:ListFunctions"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "opsworks:CreateDeployment",
                  "opsworks:DescribeApps",
                  "opsworks:DescribeCommands",
                  "opsworks:DescribeDeployments",
                  "opsworks:DescribeInstances",
                  "opsworks:DescribeStacks",
                  "opsworks:UpdateApp",
                  "opsworks:UpdateStack"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "cloudformation:CreateStack",
                  "cloudformation:DeleteStack",
                  "cloudformation:DescribeStacks",
                  "cloudformation:UpdateStack",
                  "cloudformation:CreateChangeSet",
                  "cloudformation:DeleteChangeSet",
                  "cloudformation:DescribeChangeSet",
                  "cloudformation:ExecuteChangeSet",
                  "cloudformation:SetStackPolicy",
                  "cloudformation:ValidateTemplate"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Action": [
                  "codebuild:BatchGetBuilds",
                  "codebuild:StartBuild",
                  "codebuild:BatchGetBuildBatches",
                  "codebuild:StartBuildBatch"
              ],
              "Resource": "*",
              "Effect": "Allow"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "devicefarm:ListProjects",
                  "devicefarm:ListDevicePools",
                  "devicefarm:GetRun",
                  "devicefarm:GetUpload",
                  "devicefarm:CreateUpload",
                  "devicefarm:ScheduleRun"
              ],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "servicecatalog:ListProvisioningArtifacts",
                  "servicecatalog:CreateProvisioningArtifact",
                  "servicecatalog:DescribeProvisioningArtifact",
                  "servicecatalog:DeleteProvisioningArtifact",
                  "servicecatalog:UpdateProduct"
              ],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "cloudformation:ValidateTemplate"
              ],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "ecr:DescribeImages"
              ],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "states:DescribeExecution",
                  "states:DescribeStateMachine",
                  "states:StartExecution"
              ],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "appconfig:StartDeployment",
                  "appconfig:StopDeployment",
                  "appconfig:GetDeployment"
              ],
              "Resource": "*"
          }
      ],
      "Version": "2012-10-17"
  })
}

# IAM Role for CodePipeline
# resource "aws_iam_role" "portfolio_pipeline_role" {
#   name = "portfolio-pipeline-role"

#   assume_role_policy = jsonencode({
      
# }

#Attach necessary policies to the pipeline role
resource "aws_iam_role_policy_attachment" "pipeline_basic_execution" {
  role       = aws_iam_role.portfolio_pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

