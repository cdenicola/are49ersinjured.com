variable "domain_name" {
  description = "Primary apex domain name for the static site."
  type        = string
}

variable "additional_aliases" {
  description = "Additional domain aliases that should route to the CloudFront distribution."
  type        = list(string)
}

variable "bucket_name" {
  description = "Name of the S3 bucket that stores the site assets."
  type        = string
}

variable "aws_region" {
  description = "AWS region for S3 and Route53 API operations."
  type        = string
  default     = "us-west-2"
}

variable "index_document" {
  description = "S3 object key that acts as the root document for the site."
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "S3 object key that acts as the error document for the site."
  type        = string
  default     = "error.html"
}

variable "site_files" {
  description = "Local path to folder of site files to upload."
  type        = string
  default     = ""
}

variable "price_class" {
  description = "CloudFront price class to control edge location coverage."
  type        = string
  default     = "PriceClass_100" # cheapest offering
}

variable "tags" {
  description = "Additional tags to attach to created resources."
  type        = map(string)
  default     = {}
}
