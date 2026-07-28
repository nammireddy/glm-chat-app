output "bucket_id" {
  description = "Name (ID) of the model weights S3 bucket."
  value       = aws_s3_bucket.model_weights.id
}

output "bucket_arn" {
  description = "ARN of the model weights S3 bucket."
  value       = aws_s3_bucket.model_weights.arn
}

output "bucket_domain_name" {
  description = "Regional domain name of the model weights S3 bucket."
  value       = aws_s3_bucket.model_weights.bucket_regional_domain_name
}
