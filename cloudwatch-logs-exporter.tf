data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "random_string" "random" {
  length  = 8
  special = false
  upper   = false
  numeric = false
}

resource "aws_iam_role" "log_exporter" {
  name = "log-exporter-${random_string.random.result}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "log_exporter" {
  name = "log-exporter-${random_string.random.result}"
  role = aws_iam_role.log_exporter.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateExportTask",
        "logs:Describe*",
        "logs:ListTagsLogGroup"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "ssm:DescribeParameters",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
        "ssm:PutParameter"
      ],
      "Resource": "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/log-exporter*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/log-exporter-*",
      "Effect": "Allow"
    },
    {
        "Sid": "AllowCrossAccountObjectAcc",
        "Effect": "Allow",
        "Action": [
            "s3:PutObject",
            "s3:PutObjectACL"
        ],
        "Resource": "arn:aws:s3:::${var.cloudwatch_logs_export_bucket}/*"
    },
    {
        "Sid": "AllowCrossAccountBucketAcc",
        "Effect": "Allow",
        "Action": [
            "s3:PutBucketAcl",
            "s3:GetBucketAcl"
        ],
        "Resource": "arn:aws:s3:::${var.cloudwatch_logs_export_bucket}"
    },
    {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
            "sqs:*"
        ],
        "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:DeleteRetentionPolicy",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutRetentionPolicy"
      ],
        "Resource": [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*:log-stream:"
      ]
    }  
  ]
}
EOF
}

resource "aws_cloudwatch_event_rule" "log_exporter" {
  name                = "log-exporter-${random_string.random.result}"
  description         = "Fires periodically to export logs to S3"
  schedule_expression = "rate(4 hours)"
}

resource "aws_cloudwatch_event_target" "log_exporter" {
  rule      = aws_cloudwatch_event_rule.log_exporter.name
  target_id = "log-exporter-${random_string.random.result}"
  arn       = aws_lambda_function.log_exporter.arn
}

resource "aws_lambda_permission" "log_exporter" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_exporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_exporter.arn
}


resource "aws_s3_bucket_policy" "allow_access_to_write_logs" {
  bucket = var.cloudwatch_logs_export_bucket
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "s3:GetBucketAcl",
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${var.cloudwatch_logs_export_bucket}",
      "Principal": { "Service": "logs.${data.aws_region.current.name}.amazonaws.com" },
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": [
            "${data.aws_caller_identity.current.account_id}"
          ]
        },
        "ArnLike": {
          "aws:SourceArn": [
            "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          ]
        }
      }
    },
    {
      "Action": "s3:PutObject" ,
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${var.cloudwatch_logs_export_bucket}/*",
      "Principal": { "Service": "logs.${data.aws_region.current.name}.amazonaws.com" },
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "aws:SourceAccount": [
            "${data.aws_caller_identity.current.account_id}"
          ]
        },
        "ArnLike": {
          "aws:SourceArn": [
            "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
          ]
        }
      }
    }
  ]
}
EOF

}
