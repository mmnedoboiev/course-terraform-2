resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

data "aws_iam_policy_document" "s3_read_policy" {
  count = length(var.allowed_read_arns) > 0 ? 1 : 0

  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]
  }
}

resource "aws_iam_policy" "s3_read" {
  count       = length(var.allowed_read_arns) > 0 ? 1 : 0
  name        = "${aws_s3_bucket.this.id}-s3-read-policy"
  description = "Allows reading from S3 bucket ${aws_s3_bucket.this.id}"
  policy      = data.aws_iam_policy_document.s3_read_policy[0].json
  tags        = var.tags
}