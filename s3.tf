terraform {
  backend "s3" {
    bucket         = "devopsprojects3gigi"
    key            = "terraform.tfstate"
    region         = "us-east-1"
  }
}
