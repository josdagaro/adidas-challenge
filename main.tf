locals {
  app_name = "api-sample-java"
}

module "lambda_function_api_sample_java" {
  source = "terraform-aws-modules/lambda/aws"

  providers = {
    aws = aws.virginia
  }

  function_name = local.app_name
  description   = "apiSampleJava"

  # This configuration is for allowing the creation of this lambda function, 
  # don't take care about the parameters below.
  handler     = "index.lambda_handler"
  runtime     = "python3.8"
  source_path = "dummy.txt"
  publish     = true

  tags = {
    Environment = var.env
  }

  allowed_triggers = {
    APIGatewayAny = {
      service    = "apigateway"
      source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*/*"
    }
  }
}

resource "aws_ecr_repository" "this" {
  provider = aws.virginia
  name     = local.app_name
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  provider = aws.virginia
  name     = "/aws/apigateway/${local.app_name}"

  tags = {
    Environment = var.env
    Application = local.app_name
  }
}

data "template_file" "oas" {
  template = file("${path.module}/OAS.json")

  vars = {
    lambda_uri = module.lambda_function_api_sample_java.this_lambda_function_invoke_arn
  }
}

resource "aws_api_gateway_rest_api" "this" {
  provider = aws.virginia
  body     = data.template_file.oas.rendered
  name     = "challenge"

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_deployment" "this" {
  provider    = aws.virginia
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.this.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  provider      = aws.virginia
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = "default"
}

resource "aws_api_gateway_usage_plan" "this" {
  provider = aws.virginia
  name     = "challenge"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  quota_settings {
    limit  = 20
    offset = 2
    period = "WEEK"
  }

  throttle_settings {
    burst_limit = 5
    rate_limit  = 10
  }
}

resource "aws_api_gateway_api_key" "this" {
  provider = aws.virginia
  name     = "key"
}

resource "aws_api_gateway_usage_plan_key" "main" {
  provider      = aws.virginia
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this.id
}

resource "aws_wafregional_geo_match_set" "geo_match_set" {
  provider = aws.virginia
  name     = "geo_match_set"

  geo_match_constraint {
    type  = "Country"
    value = "CO"
  }
}

resource "aws_wafregional_rule" "wafrule" {
  provider    = aws.virginia
  depends_on  = [aws_wafregional_geo_match_set.geo_match_set]
  name        = "tfWAFRule"
  metric_name = "tfWAFRule"

  predicate {
    data_id = aws_wafregional_geo_match_set.geo_match_set.id
    negated = false
    type    = "GeoMatch"
  }
}

resource "aws_wafregional_web_acl" "waf_acl" {
  provider = aws.virginia

  depends_on = [
    aws_wafregional_geo_match_set.geo_match_set,
    aws_wafregional_rule.wafrule,
  ]

  name        = "tfWebACL"
  metric_name = "tfWebACL"

  default_action {
    type = "BLOCK"
  }

  rule {
    action {
      type = "ALLOW"
    }

    priority = 1
    rule_id  = aws_wafregional_rule.wafrule.id
    type     = "REGULAR"
  }
}

resource "aws_wafregional_web_acl_association" "this" {
  provider     = aws.virginia
  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_id   = aws_wafregional_web_acl.waf_acl.id
}
