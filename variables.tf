variable "domain_name" {
  description = "Primary apex domain name for the static site."
  type        = string
  default     = "are49ersinjured.com"
}

variable "additional_aliases" {
  description = "Additional domain aliases that should route to the CloudFront distribution."
  type        = list(string)
  default     = ["www.are49ersinjured.com"]
}

variable "bucket_name" {
  description = "Name of the S3 bucket that stores the site assets."
  type        = string
  default     = "are49ersinjured.com"
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

variable "index_source" {
  description = "Local path to the HTML file to upload; defaults to a file with the same name as index_document in this directory."
  type        = string
  default     = ""
}

variable "index_content_type" {
  description = "Content type metadata applied to the uploaded index document."
  type        = string
  default     = "text/html"
}

variable "price_class" {
  description = "CloudFront price class to control edge location coverage."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Additional tags to attach to created resources."
  type        = map(string)
  default     = {}
}
