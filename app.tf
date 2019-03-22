variable "domain_redirects_map" {
  description = "A map of domain redirect names to the URLs to redirect to."
  type = "map"
}

variable "domain_name" {
  description = "The AWS Route53 domain to use."
}

locals {
  redirect_names = "${keys(var.domain_redirects_map)}"
}

data "aws_route53_zone" "zone_to_use" {
  name = "${var.domain_name}."
  private_zone = false
}

resource "aws_s3_bucket" "redirect_bucket" {
  count = "${length(local.redirect_names)}"
  bucket = "${element(local.redirect_names, count.index)}.${var.domain_name}"
  acl = "public-read"
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
}

resource "aws_s3_bucket_object" "redirect_index_html" {
  depends_on = [
    "aws_s3_bucket.redirect_bucket"
  ]
  count = "${length(local.redirect_names)}"
  bucket = "${element(local.redirect_names, count.index)}.${var.domain_name}"
  acl = "public-read"
  key = "index.html"
  content_type = "text/html; charset=UTF-8"
  content = <<-HTML
  <html>
  <head>
    <meta http-equiv="refresh" content="0; url='${lookup(var.domain_redirects_map,element(local.redirect_names, count.index))}'" />
  </head>
  Click <a href="${lookup(var.domain_redirects_map, element(local.redirect_names, count.index))}">here</a> if you are not redirected.
  Have a great day!
  </html>
  HTML
  cache_control = "Cache-Control:max-age=0"
}

resource "aws_route53_record" "redirect_record" {
  depends_on = [
    "aws_s3_bucket.redirect_bucket"
  ]
  count = "${length(local.redirect_names)}"
  zone_id = "${data.aws_route53_zone.zone_to_use.zone_id}"
  name = "${element(local.redirect_names, count.index)}"
  type = "A"

  alias {
    name = "${element(aws_s3_bucket.redirect_bucket.*.website_domain,count.index)}"
    zone_id = "${element(aws_s3_bucket.redirect_bucket.*.hosted_zone_id,count.index)}"
    evaluate_target_health = true
  }
}
