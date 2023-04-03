provider "aws" {
  region= "us-east-1"
}

// resource "<PROVIDER>_<TYPE>" "<NAME>" {
//   <CONFIG> = <VALUE>
// }
// Provider: aws
// Type: instance
// Name: web
// Config: ami consists of one or more values
data "aws_ami" "amazon_linux"{
 most_recent = true

 filter{
  name = "name"
  values = ["amzn2-ami-hvm-*-x86_64-gp2"]
 }

 filter{
  name = "virtualization-type"
  values = ["hvm"]
 }

 filter{
  name = "root-device-type"
  values = ["ebs"]
 }
 

 owners = ["amazon"]
}

resource "aws_instance" "example" {
  ami =  data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"

  tags = {
    Name = "terraform-example"
  }
}