provider "aws" {
  alias = "acm"
  region = "us-east-1"
}
locals {
  redirect_data = yamldecode(file("./domains.yml"))
  redirect_names = local.redirect_data.domains
  domain_names = {
    for k, v in local.redirect_names: k => "${k}.${var.domain_name}"
  }
}


variable "domain_name" {
  description = "The AWS Route53 domain to use."
  type = string
}

data "aws_caller_identity" "self" {}

data "aws_route53_zone" "zone_to_use" {
  name = var.domain_name
  private_zone = false
}

data "aws_iam_policy_document" "policy" {
  for_each = local.redirect_names
  statement {
    sid = "SvcAccountCanDoAnything"
    actions = ["s3:*"]
    principals {
      type = "AWS"
      identifiers = [ data.aws_caller_identity.self.arn ]
    }
  }
  statement {
    sid = "PublicReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket[each.key].arn}/*"]
    principals {
      type = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_acm_certificate" "aws_managed_https_certificate" {
  for_each = local.redirect_names
  domain_name = aws_s3_bucket.bucket[each.key].bucket
  provider = aws.acm
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "aws_managed_https_certificate_validation_record" {
  for_each = local.redirect_names
  name    = tolist(aws_acm_certificate.aws_managed_https_certificate[each.key].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.aws_managed_https_certificate[each.key].domain_validation_options)[0].resource_record_type
  zone_id = data.aws_route53_zone.zone_to_use.id
  records = [tolist(aws_acm_certificate.aws_managed_https_certificate[each.key].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "aws_managed_https_certificate" {
  for_each = local.redirect_names
  provider = aws.acm
  certificate_arn         = aws_acm_certificate.aws_managed_https_certificate[each.key].arn
  validation_record_fqdns = [aws_route53_record.aws_managed_https_certificate_validation_record[each.key].fqdn]
  timeouts {
    create = "5m"
  }
}

resource "aws_cloudfront_origin_access_identity" "website" {
  for_each = local.redirect_names
  comment = "HTTPS fronting for ${local.domain_names[each.key]}"
}


resource "aws_cloudfront_distribution" "website" {
  for_each = local.redirect_names
  provider = aws.acm
  aliases = [ local.domain_names[each.key] ]
  tags = {
    "Managed-By": "https://github.com/carlosonunez/redirects"
  }
  origin {
    domain_name = aws_s3_bucket.bucket[each.key].bucket_regional_domain_name
    origin_id = local.domain_names[each.key]
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website[each.key].cloudfront_access_identity_path
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  enabled = true
  comment = "Managed by https://github.com/carlosonunez/redirects"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods = [ "GET","POST","PUT","DELETE","PATCH","OPTIONS","HEAD"]
    cached_methods = [ "GET","HEAD" ]
    target_origin_id = local.domain_names[each.key]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }
  price_class = "PriceClass_100"
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.aws_managed_https_certificate[each.key].certificate_arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}

resource "aws_route53_record" "redirect_record" {
  for_each = local.redirect_names
  zone_id = data.aws_route53_zone.zone_to_use.zone_id
  name = aws_s3_bucket.bucket[each.key].bucket
  type = "A"
  alias {
    name = aws_cloudfront_distribution.website[each.key].domain_name
    zone_id = aws_cloudfront_distribution.website[each.key].hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket" "bucket" {
  for_each = local.redirect_names
  bucket = local.domain_names[each.key]
  tags = {
    "Managed-By": "https://github.com/carlosonunez/redirects"
  }
}

resource "aws_s3_bucket_policy" "example" {
  for_each = local.redirect_names
  bucket = aws_s3_bucket.bucket[each.key].bucket
  policy = data.aws_iam_policy_document.policy[each.key].json
}

resource "aws_s3_bucket_ownership_controls" "redirect_bucket" {
  for_each = local.redirect_names
  bucket = aws_s3_bucket.bucket[each.key].bucket
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_website_configuration" "redirect_bucket" {
  for_each = local.redirect_names
  bucket = aws_s3_bucket.bucket[each.key].bucket
  index_document { suffix = "index.html" }
  error_document { key = "error.html" }
}

resource "aws_s3_bucket_public_access_block" "redirect_bucket" {
  for_each = local.redirect_names
  bucket = aws_s3_bucket.bucket[each.key].bucket
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_object" "redirect_index_html" {
  for_each = local.redirect_names
  bucket = aws_s3_bucket.bucket[each.key].bucket
  depends_on = [
    aws_s3_bucket.bucket
  ]
  acl = "public-read"
  key = "index.html"
  content_type = "text/html; charset=UTF-8"
  content = <<-HTML
  <html>
  <head>
    <meta http-equiv="refresh" content="0; url='${each.value}'" />
  </head>
  Click <a href="${each.value}">here</a> if you are not redirected.
  Have a great day!
  </html>
  HTML
  cache_control = "Cache-Control:max-age=0"
}

