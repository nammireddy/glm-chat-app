output "s3_endpoint_id" {
  description = "ID of the S3 Gateway VPC endpoint."
  value       = aws_vpc_endpoint.s3.id
}

output "ecr_api_endpoint_id" {
  description = "ID of the ECR API interface VPC endpoint."
  value       = aws_vpc_endpoint.ecr_api.id
}

output "ecr_dkr_endpoint_id" {
  description = "ID of the ECR DKR interface VPC endpoint."
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "logs_endpoint_id" {
  description = "ID of the CloudWatch Logs interface VPC endpoint."
  value       = aws_vpc_endpoint.logs.id
}

output "sts_endpoint_id" {
  description = "ID of the STS interface VPC endpoint."
  value       = aws_vpc_endpoint.sts.id
}

output "endpoints_security_group_id" {
  description = "ID of the security group attached to all interface VPC endpoints."
  value       = aws_security_group.endpoints.id
}
