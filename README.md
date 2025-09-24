# are49ersinjured.com - a minimal static website on AWS
The repo contains a minimal example for deploying a static HTML web page (index.html) to AWS using S3 to store pages, CloudFront as the CDN, and ACM to generate certificates

## Hosting your own static website
1) Fork the repo
2) Modify `index.html` to your website
3) Update `terraform.tfvars` variables for your use case
4) Own the domain name in your AWS account (or point domain to NS)

## Deploying Website
*Note: must have permissions in AWS for S3, CloudFront, & ACM*

1) Connect terminal to AWS account:
```zsh
aws configure
```
2) Apply state using terraform:
```zsh
terraform init && \
terraform plan && \
terraform apply
```
