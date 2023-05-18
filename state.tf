terraform {
  backend "s3" {
    # Replace this with your bucket name!
    bucket         = "myapp-terraform-statefiles"
    key            = "global/s3/terraform.tfstate"
    region         = "ap-northeast-3"

    # Replace this with your DynamoDB table name!
    dynamodb_table = "myapp-terraform-statefiles-locks"
    encrypt        = true
  }
}