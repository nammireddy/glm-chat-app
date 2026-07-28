###############################################################################
# S3 Bucket — GLM-4 Model Weights
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project}-model-weights-${data.aws_caller_identity.current.account_id}"

  common_tags = merge(
    {
      Project   = "glm-chat"
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

# --- Bucket -------------------------------------------------------------------

resource "aws_s3_bucket" "model_weights" {
  bucket = local.bucket_name

  tags = local.common_tags
}

# --- Versioning ---------------------------------------------------------------

resource "aws_s3_bucket_versioning" "model_weights" {
  bucket = aws_s3_bucket.model_weights.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Server-Side Encryption (SSE-S3 / AES256) --------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "model_weights" {
  bucket = aws_s3_bucket.model_weights.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# --- Block All Public Access --------------------------------------------------

resource "aws_s3_bucket_public_access_block" "model_weights" {
  bucket = aws_s3_bucket.model_weights.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Lifecycle Rule (cost optimisation for older model versions) ---------------

resource "aws_s3_bucket_lifecycle_configuration" "model_weights" {
  bucket = aws_s3_bucket.model_weights.id

  rule {
    id     = "transition-older-versions"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

# --- Bucket Policy — restrict GetObject to inference IRSA role ----------------
# NOTE: This is applied via the root module after the IRSA role exists.
# See infra/terraform/main.tf for the aws_s3_bucket_policy resource.
