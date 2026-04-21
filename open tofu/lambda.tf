data "archive_file" "lambda_dir" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/output/function.zip"
}

########################################
# IAM Role for Lambda
########################################
resource "aws_iam_role" "lambda_role" {
  name = "postagram-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_rekognition_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess"
}

resource "aws_lambda_function" "lambda_function" {
  filename         = data.archive_file.lambda_dir.output_path
  function_name    = "postagram-label-detector"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_dir.output_base64sha256
  memory_size      = 512
  timeout          = 30
  runtime          = "python3.13"

  environment {
    variables = {
      DYNAMO_TABLE = aws_dynamodb_table.basic-dynamodb-table.name
    }
  }
}

resource "aws_lambda_permission" "allow_from_S3" {
  action         = "lambda:InvokeFunction"
  statement_id   = "AllowExecutionFromS3Bucket"
  function_name  = aws_lambda_function.lambda_function.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.bucket.arn
  source_account = data.aws_caller_identity.current.account_id
  depends_on     = [aws_lambda_function.lambda_function, aws_s3_bucket.bucket]
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_function.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_from_S3]
}