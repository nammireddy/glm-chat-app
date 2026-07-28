locals {
  common_tags = merge(
    {
      Project   = var.project
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

# -----------------------------------------------------------------------------
# Route53 Zone Data Source
# -----------------------------------------------------------------------------

data "aws_route53_zone" "this" {
  name         = var.route53_zone_name
  private_zone = false
}

# -----------------------------------------------------------------------------
# ACM Certificate — DNS Validation
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Route53 DNS Validation Records
# -----------------------------------------------------------------------------

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

# -----------------------------------------------------------------------------
# Certificate Validation — waits until the certificate is issued
# -----------------------------------------------------------------------------

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
