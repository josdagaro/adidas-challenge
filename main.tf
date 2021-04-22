locals {
  app_name = "api-sample-java"
}

module "lambda_function_api_sample_java" {
  source = "terraform-aws-modules/lambda/aws"

  providers = {
    aws = aws.virginia
  }

  create         = var.create
  create_package = false
  function_name  = local.app_name
  description    = "apiSampleJava"
  package_type   = "Image"
  publish        = false
  image_uri      = "public.ecr.aws/lambda/nodejs:12"

  tags = {
    Environment = var.env
  }

  allowed_triggers = {
    APIGatewayAny = {
      service    = "apigateway"
      source_arn = "${element(concat(aws_api_gateway_rest_api.this.*.execution_arn, [""]), 0)}/*/*/*"
    }
  }
}

resource "aws_ecr_repository" "this" {
  count    = var.create ? 1 : 0
  provider = aws.virginia
  name     = local.app_name
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  count    = var.create ? 1 : 0
  provider = aws.virginia
  name     = "/aws/apigateway/${local.app_name}"

  tags = {
    Environment = var.env
    Application = local.app_name
  }
}

data "template_file" "oas" {
  count    = var.create ? 1 : 0
  template = file("${path.module}/OAS.json")

  vars = {
    lambda_uri = module.lambda_function_api_sample_java.this_lambda_function_invoke_arn
  }
}

resource "aws_api_gateway_rest_api" "this" {
  count    = var.create ? 1 : 0
  provider = aws.virginia
  body     = element(concat(data.template_file.oas.*.rendered, [""]), 0)
  name     = "challenge"

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_deployment" "this" {
  count       = var.create ? 1 : 0
  provider    = aws.virginia
  rest_api_id = element(concat(aws_api_gateway_rest_api.this.*.id, [""]), 0)

  triggers = {
    redeployment = sha1(jsonencode(element(concat(aws_api_gateway_rest_api.this.*.body, [""]), 0)))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  count         = var.create ? 1 : 0
  provider      = aws.virginia
  deployment_id = element(concat(aws_api_gateway_deployment.this.*.id, [""]), 0)
  rest_api_id   = element(concat(aws_api_gateway_rest_api.this.*.id, [""]), 0)
  stage_name    = "default"
}

resource "aws_api_gateway_usage_plan" "this" {
  count    = var.create ? 1 : 0
  provider = aws.virginia
  name     = "challenge"

  api_stages {
    api_id = element(concat(aws_api_gateway_rest_api.this.*.id, [""]), 0)
    stage  = element(concat(aws_api_gateway_stage.this.*.stage_name, [""]), 0)
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
  count    = var.create ? 1 : 0
  provider = aws.virginia
  name     = "key"
}

resource "aws_api_gateway_usage_plan_key" "main" {
  count         = var.create ? 1 : 0
  provider      = aws.virginia
  key_id        = element(concat(aws_api_gateway_api_key.this.*.id, [""]), 0)
  key_type      = "API_KEY"
  usage_plan_id = element(concat(aws_api_gateway_usage_plan.this.*.id, [""]), 0)
}

resource "aws_wafregional_geo_match_set" "geo_match_set" {
  count    = var.create ? 1 : 0
  provider = aws.virginia
  name     = "geo_match_set"

  geo_match_constraint {
    type  = "Country"
    value = "CO"
  }
}

resource "aws_wafregional_rule" "wafrule" {
  count       = var.create ? 1 : 0
  provider    = aws.virginia
  depends_on  = [aws_wafregional_geo_match_set.geo_match_set]
  name        = "tfWAFRule"
  metric_name = "tfWAFRule"

  predicate {
    data_id = element(concat(aws_wafregional_geo_match_set.geo_match_set.*.id, [""]), 0)
    negated = false
    type    = "GeoMatch"
  }
}

resource "aws_wafregional_web_acl" "waf_acl" {
  count    = var.create ? 1 : 0
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
    rule_id  = element(concat(aws_wafregional_rule.wafrule.*.id, [""]), 0)
    type     = "REGULAR"
  }
}

resource "aws_wafregional_web_acl_association" "this" {
  count        = var.create ? 1 : 0
  provider     = aws.virginia
  resource_arn = element(concat(aws_api_gateway_stage.this.*.arn, [""]), 0)
  web_acl_id   = element(concat(aws_wafregional_web_acl.waf_acl.*.id, [""]), 0)
}
