provider "aws" {
        region = "us-east-1"
}

resource "aws_s3_bucket" "pipeline_artifacts" {
    bucket = "example-pipeline-artifacts"
}

resource "aws_s3_bucket_acl" "pipeline_artifacts_acl" {
    bucket = aws_s3_bucket.pipeline_artifacts.id
    acl    = "private"
}

resource "aws_iam_role" "pipeline_role" {
  name = "example-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy_attachment" "pipeline_cloudwatch_logs" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "pipeline_s3_access" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/S3FullAccess"
}

resource "aws_codepipeline" "example" {
  name     = "example-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name            = "SourceAction"
      category        = "Source"
      owner           = "AWS"
      provider        = "CodeCommit"
      version         = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = "example-repo"
        BranchName     = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "BuildAction"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = "example-build-project"
      }
    }
  }

  stage {
    name = "Test"

    action {
      name            = "TestAction"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        ProjectName = "example-test-project"
      }
    }
  }

  stage {
    name = "Staging"

    action {
      name            = "DeployToStagingAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CloudFormation"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        StackName = "staging-stack"
      }
    }
  }

  stage {
    name = "Production"

    action {
      name            = "DeployToProductionAction"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CloudFormation"
      version         = "1"
      input_artifacts = ["build_output"]

      configuration = {
        StackName = "production-stack"
      }
    }
  }
}

