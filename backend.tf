terraform {
  backend "s3" {
    bucket = "opendatasciencebucket"
    key = "main"
    region = "us-east-1"
    dynamodb_table = "terraformtable"
  }
}
