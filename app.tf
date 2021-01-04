variable "domain_name" {
  description = "The AWS Route53 domain to use."
}

locals {
  redirect_data = yamldecode(file("./domains.yml"))
  redirect_names = local.redirect_data.domains
}

data "aws_route53_zone" "zone_to_use" {
  name = var.domain_name
  private_zone = false
}

resource "aws_cloudfront_origin_access_identity" "website" {
  count = length(local.redirect_names)
  comment = "HTTPS fronting for ${element(keys(local.redirect_names), count.index)}.${var.domain_name}"
}

resource "aws_s3_bucket" "redirect_bucket" {
  count = length(local.redirect_names)
  bucket = "${element(keys(local.redirect_names), count.index)}.${var.domain_name}"
  acl = "public-read"
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
  tags = {
    "Managed-By": "https://github.com/carlosonunez/redirects"
  }
}

data "aws_iam_policy_document" "s3_policy" {
  count = length(local.redirect_names)
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.redirect_bucket[count.index].arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.website[count.index].iam_arn]
    }
  }
}


resource "aws_s3_bucket_policy" "example" {
  count = length(local.redirect_names)
  bucket = aws_s3_bucket.redirect_bucket[count.index].id
  policy = data.aws_iam_policy_document.s3_policy[count.index].json
}

resource "aws_s3_bucket_object" "redirect_index_html" {
  depends_on = [
    aws_s3_bucket.redirect_bucket
  ]
  count = length(local.redirect_names)
  bucket = "${element(keys(local.redirect_names), count.index)}.${var.domain_name}"
  acl = "public-read"
  key = "index.html"
  content_type = "text/html; charset=UTF-8"
  content = <<-HTML
  <html>
  <head>
    <meta http-equiv="refresh" content="0; url='${lookup(local.redirect_names,element(keys(local.redirect_names), count.index))}'" />
  </head>
  Click <a href="${lookup(local.redirect_names, element(keys(local.redirect_names), count.index))}">here</a> if you are not redirected.
  Have a great day!
  </html>
  HTML
  cache_control = "Cache-Control:max-age=0"
}

resource "aws_route53_record" "redirect_record" {
  depends_on = [
    aws_s3_bucket.redirect_bucket,
    aws_cloudfront_distribution.website
  ]
  count = length(local.redirect_names)
  zone_id = data.aws_route53_zone.zone_to_use.zone_id
  name = element(keys(local.redirect_names), count.index)
  type = "A"
  alias {
    name = aws_cloudfront_distribution.website[count.index].domain_name
    zone_id = aws_cloudfront_distribution.website[count.index].hosted_zone_id
    evaluate_target_health = true
  }
}

provider "aws" {
  alias = "acm"
  region = "us-east-1"
}

resource "aws_acm_certificate" "aws_managed_https_certificate" {
  depends_on = [
    aws_s3_bucket.redirect_bucket
  ]
  count = length(local.redirect_names)
  provider = aws.acm
  domain_name = "${element(keys(local.redirect_names), count.index)}.${var.domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "aws_managed_https_certificate_validation_record" {
  depends_on = [
    aws_s3_bucket.redirect_bucket
  ]
  count = length(local.redirect_names)
  name    = tolist(aws_acm_certificate.aws_managed_https_certificate[count.index].domain_validation_options).0.resource_record_name
  type    = tolist(aws_acm_certificate.aws_managed_https_certificate[count.index].domain_validation_options).0.resource_record_type
  zone_id = data.aws_route53_zone.zone_to_use.id
  records = [tolist(aws_acm_certificate.aws_managed_https_certificate[count.index].domain_validation_options).0.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "aws_managed_https_certificate" {
  count = length(local.redirect_names)
  provider = aws.acm
  certificate_arn         = aws_acm_certificate.aws_managed_https_certificate[count.index].arn
  validation_record_fqdns = [aws_route53_record.aws_managed_https_certificate_validation_record[count.index].fqdn]
  timeouts {
    create = "5m"
  }
}


resource "aws_cloudfront_distribution" "website" {
  count = length(local.redirect_names)
  provider = aws.acm
  aliases = [ "${element(keys(local.redirect_names), count.index)}.${var.domain_name}" ]
  tags = {
    "Managed-By": "https://github.com/carlosonunez/redirects"
  }
  origin {
    domain_name = aws_s3_bucket.redirect_bucket[count.index].bucket_regional_domain_name
    origin_id = "${element(keys(local.redirect_names), count.index)}.${var.domain_name}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.website[count.index].cloudfront_access_identity_path
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
    target_origin_id = "${element(keys(local.redirect_names), count.index)}.${var.domain_name}"
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
    acm_certificate_arn = aws_acm_certificate_validation.aws_managed_https_certificate[count.index].certificate_arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}
