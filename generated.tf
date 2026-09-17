
resource "aws_s3_bucket" "bucket_create_manual" {
  bucket              = "s3-manual-create"
  bucket_namespace    = "global"
  force_destroy       = false
  object_lock_enabled = false
  region              = "eu-central-1"
  tags                = {}
  tags_all            = {}
}
