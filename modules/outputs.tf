output "bucket_name" {
  description = "Ім'я створеного S3 бакета"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN створеного S3 бакета"
  value       = aws_s3_bucket.this.arn
}

output "policy_arn" {
  description = "ARN IAM політики доступу на читання (null якщо не створювалася)"
  value       = length(aws_iam_policy.s3_read) > 0 ? aws_iam_policy.s3_read[0].arn : null
}