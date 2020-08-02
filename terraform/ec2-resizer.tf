// Create a policy that allows adjusting the size of instances
data "aws_iam_policy_document" "resize-server" {
  statement {
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances"
    ]
    resources = [aws_instance.arma_server_linux.arn]
  }
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:ModifyInstanceAttribute"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "resize-server" {
  policy = data.aws_iam_policy_document.resize-server.json
}

// Create the ZIP file for the Lambda
data "archive_file" "server-resizer" {
  type        = "zip"
  source_dir  = "./lambda/resize-ec2"
  output_path = "./lambda/resize-ec2.zip"
}

// Create the function itself (and all supporting resoruces)
module "server-upsize" {
  source           = "github.com/Imperative-Systems-Inc/terraform-modules/lambda-set"
  name             = "server-upsize"
  edge             = false
  handler          = "main.lambda_handler"
  runtime          = "python3.8"
  memory_size      = 128
  timeout          = 5 * 60
  archive          = data.archive_file.server-resizer
  role_policy_arns = [aws_iam_policy.resize-server.arn]
  environment = {
    INSTANCE_ID   = aws_instance.arma_server_linux.id
    INSTANCE_SIZE = local.instance_size_large
  }
  schedules = local.upsize_schedules
}


// Create the function itself (and all supporting resoruces)
module "server-downsize" {
  source           = "github.com/Imperative-Systems-Inc/terraform-modules/lambda-set"
  name             = "server-downsize"
  edge             = false
  handler          = "main.lambda_handler"
  runtime          = "python3.8"
  memory_size      = 128
  timeout          = 5 * 60
  archive          = data.archive_file.server-resizer
  role_policy_arns = [aws_iam_policy.resize-server.arn]
  environment = {
    INSTANCE_ID   = aws_instance.arma_server_linux.id
    INSTANCE_SIZE = local.instance_size_small
  }
  schedules = local.downsize_schedules
}
