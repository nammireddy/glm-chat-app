output "file_system_id" {
  description = "ID of the EFS file system."
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system."
  value       = aws_efs_file_system.this.arn
}

output "access_point_id" {
  description = "ID of the EFS access point for the inference service."
  value       = aws_efs_access_point.inference.id
}

output "access_point_arn" {
  description = "ARN of the EFS access point for the inference service."
  value       = aws_efs_access_point.inference.arn
}

output "mount_target_ids" {
  description = "IDs of the EFS mount targets (one per private subnet)."
  value       = aws_efs_mount_target.this[*].id
}

output "efs_security_group_id" {
  description = "ID of the security group attached to EFS mount targets."
  value       = aws_security_group.efs.id
}
