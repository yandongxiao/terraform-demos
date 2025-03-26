# the configuration for the aws provider
# this "aws" it the Local Name for the provider.
provider "aws" {
  # There is a "meta-arguments" that are defined by Terraform itself and available for all provider blocks: alias.
  # If alias is not set, It is the default provider configuration; resources that begin with `aws_` will use it as
  # the default, and it can be referenced as `aws`.
  #
  # Other parameters are defined by the aws provider.
  # You can use expressions in these values, but you can only reference values that are known at the time the provider
  # is configured.
  # Some providers can use environment variables as the value of some configuration parameters; we recommend using this
  # method as much as possible to avoid storing credentials in the Terraform code.

  # we use localstack for testing, so we don't need to set the access_key and secret_key
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_use_path_style           = false
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # we use localstack for testing, so we need to set the endpoints
  endpoints {
    apigateway     = "http://localhost:4566"
    apigatewayv2   = "http://localhost:4566"
    cloudformation = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    ec2            = "http://localhost:4566"
    es             = "http://localhost:4566"
    elasticache    = "http://localhost:4566"
    firehose       = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kinesis        = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    rds            = "http://localhost:4566"
    redshift       = "http://localhost:4566"
    route53        = "http://localhost:4566"
    s3             = "http://s3.localhost.localstack.cloud:4566"
    secretsmanager = "http://localhost:4566"
    ses            = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sqs            = "http://localhost:4566"
    ssm            = "http://localhost:4566"
    stepfunctions  = "http://localhost:4566"
    sts            = "http://localhost:4566"
  }
}
