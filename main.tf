provider "aws" {
  region = "us-east-1"
}

// resource "<PROVIDER>_<TYPE>" "<NAME>" {
//   <CONFIG> = <VALUE>
// }
// Provider: aws
// Type: instance
// Name: web
// Config: ami consists of one or more values
data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }


  owners = ["amazon"]
}

# One particularly useful type of expression is a reference, which allows you to access
# values from other parts of your code. To access the ID of the security group resource,
# you are going to need to use a resource attribute reference, which uses the following
# syntax:
# <PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>
# where PROVIDER is the name of the provider (e.g., aws), TYPE is the type of resource
# (e.g., security_group), NAME is the name of that resource (e.g., the security group is
# named "instance"), and ATTRIBUTE is either one of the arguments of that resource
# (e.g., name) or one of the attributes exported by the resource (you can find the list
# of available attributes in the documentation for each resource). The security group
# exports an attribute called id, so the expression to reference it will look like this:
# aws_security_group.instance.id
# You can use this security group ID in the vpc_security_group_ids argument of the
# aws_instance as follows:
#     data.aws_ami.amazon_linux.id
resource "aws_instance" "example" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  # tell the EC2 instance to use the security group we created below
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF

  # when you change the user_data parameter and run apply, Terraform will terminate the
  # original instance and launch a totally new one. Terraform’s default behavior is to
  # update the original instance in place, but since User Data runs only on the very
  # first boot, and your original instance already went through that boot process, you
  # need to force the creation of a new instance to ensure your new User Data script
  # actually gets executed.
  user_data_replace_on_change = true

  tags = {
    Name = "terraform-example"
  }
}

# To allow the EC2 instance to receive traffic on port 8080, we need to create a security 
# group and add an ingress rule to allow traffic on port 8080.
resource "aws_security_group" "instance" {
  name        = "terraform-example-instance"
  description = "Allow HTTP traffic"

  ingress {
    description = "TLS from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    # CIDR blocks are a concise way to specify a range of IP addresses. The /0 at the end 
    # means that the range is from the first IP address to the last IP address. So this 
    # security group allows incoming traffic on port 8080 from any IP address.
    cidr_blocks = ["0.0.0.0/0"]
  }
}

 output "public_ip" {
    value = aws_instance.example.public_ip
    description = "Public IP of the instance"
  }
