# S3 bucket that stores the remote OpenTofu state. Bootstrap once (local state),
# then `tofu init -migrate-state` to move state into it (ADR-010 §5).
resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  tags = merge(var.tags, { Name = var.bucket_name })
}

# Versioning: every state write keeps a prior version → recover from a bad apply.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest (SSE-S3). State can contain sensitive values, so never plaintext.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state must never be internet-reachable.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
