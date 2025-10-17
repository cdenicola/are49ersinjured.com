terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  all_aliases             = distinct(concat([var.domain_name], var.additional_aliases))
  tags                    = merge({ Project = var.domain_name }, var.tags)
  // REDIRECT VARS
  redirect_domains = distinct([
    for domain in [for d in var.redirect_domains : trimspace(d)] : domain if domain != ""
  ])
  redirect_enabled        = length(local.redirect_domains) > 0
  redirect_primary_domain = local.redirect_enabled ? local.redirect_domains[0] : ""
  redirect_alt_domains    = local.redirect_enabled ? slice(local.redirect_domains, 1, length(local.redirect_domains)) : []
  redirect_function_name  = local.redirect_enabled ? replace(local.redirect_primary_domain, ".", "-") : ""
  redirect_tags           = merge(var.tags, { Project = local.redirect_enabled ? local.redirect_primary_domain : var.domain_name })
}

# resources aws region
provider "aws" {
  region = var.aws_region
}
# aws region for acm (must be us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_route53_zone" "domain" {
  name         = "${var.domain_name}."
  private_zone = false
}

data "aws_route53_zone" "redirect" {
  for_each     = { for domain in local.redirect_domains : domain => domain }
  name         = "${each.value}."
  private_zone = false
}

#####################
# AWS ACM Certificate
#####################
resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = var.additional_aliases
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.domain.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "site" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

################
# S3 site bucket
################
resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }
}

resource "aws_s3_object" "site_files" {
  bucket = aws_s3_bucket.site.id

  # webfiles/ is the Directory contains files to be uploaded to S3
  for_each = fileset("${var.site_files}/", "**/*.*")

  key          = each.value
  source       = "${var.site_files}/${each.value}"
  content_type = each.value
}

################
# CloudFront CDN
################
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "cf-${var.domain_name}-oac"
  description                       = "Origin access control for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = var.price_class
  aliases             = local.all_aliases
  default_root_object = var.index_document

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site.id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" // Managed-CachingOptimized
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.site.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.tags

  depends_on = [aws_acm_certificate_validation.site]
}

# allows cloudfront to access s3 bucket
data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
}

resource "aws_route53_record" "aliases" {
  for_each = toset(local.all_aliases)

  zone_id = data.aws_route53_zone.domain.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

#########################
# Redirect Distribution
#########################
resource "aws_acm_certificate" "redirect" {
  count    = local.redirect_enabled ? 1 : 0
  provider = aws.us_east_1

  domain_name               = local.redirect_primary_domain
  subject_alternative_names = local.redirect_alt_domains
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.redirect_tags
}

resource "aws_route53_record" "redirect_certificate_validation" {
  for_each = local.redirect_enabled ? {
    for dvo in aws_acm_certificate.redirect[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  zone_id = data.aws_route53_zone.redirect[each.key].zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "redirect" {
  count    = local.redirect_enabled ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.redirect[0].arn
  validation_record_fqdns = [for record in aws_route53_record.redirect_certificate_validation : record.fqdn]
}

resource "aws_cloudfront_function" "redirect" {
  count   = local.redirect_enabled ? 1 : 0
  name    = "redirect-${local.redirect_function_name}"
  runtime = "cloudfront-js-1.0"
  comment = "Redirect ${local.redirect_primary_domain} to ${var.domain_name}"
  publish = true

  code = <<-EOF
function handler(event) {
  var request = event.request;
  var host = "${var.domain_name}";
  var location = "https://" + host + request.uri;
  var query = [];
  var qs = request.querystring;

  for (var key in qs) {
    if (Object.prototype.hasOwnProperty.call(qs, key)) {
      var entry = qs[key];
      if (entry.multiValue) {
        for (var i = 0; i < entry.multiValue.length; i++) {
          query.push(key + "=" + entry.multiValue[i].value);
        }
      } else if (entry.value) {
        query.push(key + "=" + entry.value);
      }
    }
  }

  if (query.length > 0) {
    location += "?" + query.join("&");
  }

  return {
    statusCode: 301,
    statusDescription: "Moved Permanently",
    headers: {
      location: { value: location },
      "cache-control": { value: "max-age=86400" } // 1 day
    }
  };
}
EOF
}

resource "aws_cloudfront_distribution" "redirect" {
  count = local.redirect_enabled ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  price_class     = var.price_class
  comment         = "Redirect ${join(", ", local.redirect_domains)} to ${var.domain_name}"
  aliases         = local.redirect_domains

  origin {
    domain_name = var.domain_name
    origin_id   = "redirect-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "redirect-origin"

    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" // Managed-CachingOptimized

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect[0].arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.redirect[0].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.redirect_tags

  depends_on = [aws_acm_certificate_validation.redirect]
}

resource "aws_route53_record" "redirect_alias" {
  for_each = { for domain in local.redirect_domains : domain => domain }

  zone_id = data.aws_route53_zone.redirect[each.key].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.redirect[0].domain_name
    zone_id                = aws_cloudfront_distribution.redirect[0].hosted_zone_id
    evaluate_target_health = false
  }
}
