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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
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
              nohup busybox httpd -f -p ${var.server_port} &
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
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    # CIDR blocks are a concise way to specify a range of IP addresses. The /0 at the end 
    # means that the range is from the first IP address to the last IP address. So this 
    # security group allows incoming traffic on port 8080 from any IP address.
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The first step in creating an ASG(AWS Autoscaling Group) is to create a launch configuration, 
# which specifies how to configure each EC2 Instance in the ASG.15 The aws_launch_configuration 
# resource uses almost the same parameters as the aws_instance resource, although it doesn’t support tags
resource "aws_launch_configuration" "example" {
  image_id        = data.aws_ami.amazon_linux.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  # Required when using a launch configuration with an auto scaling group.
  lifecycle {
    create_before_destroy = true
  }
}

# Note that the ASG uses a reference to fill in the launch configuration name. This leads to a problem:
# launch configurations are immutable, so if you change any parameter of your launch
# configuration, Terraform will try to replace it. Normally, when replacing a resource,
# Terraform would delete the old resource first and then creates its replacement, but
# because your ASG now has a reference to the old resource, Terraform won’t be able to
# delete it.
# To solve this problem, you can use a lifecycle setting. Every Terraform resource
# supports several lifecycle settings that configure how that resource is created, upda‐
# ted, and/or deleted. A particularly useful lifecycle setting is create_before_destroy.
# If you set create_before_destroy to true, Terraform will invert the order in which
# it replaces resources, creating the replacement resource first (including updating
# any references that were pointing at the old resource to point to the replacement)
# and then deleting the old resource.

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  max_size = 10
  min_size = 2

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_lb" "example" {
  name               = "terraform-example-lb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
}

# This listener configures the ALB to listen on the default HTTP port, port 80, use
# HTTP as the protocol, and send a simple 404 page as the default response for
# requests that don’t match any listener rules.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = "404"
    }
  }
}

# Note that, by default, all AWS resources, including ALBs, don’t allow any incoming or
# outgoing traffic, so you need to create a new security group specifically for the ALB.
# This security group should allow incoming requests on port 80 so that you can access
# the load balancer over HTTP, and allow outgoing requests on all ports so that the
# load balancer can perform health checks:

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  # Allow inbound HTTP traffic
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Note that, by default, all AWS resources, including ALBs, don’t allow any incoming or
# outgoing traffic, so you need to create a new security group specifically for the ALB.
# This security group should allow incoming requests on port 80 so that you can access
# the load balancer over HTTP, and allow outgoing requests on all ports so that the
# load balancer can perform health checks:
resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Tie all these pieces together by creating listener rules using the aws_lb_listener_rule resource. 
# The below resource code adds a listener rule that sends requests that match any 
# path to the target group that contains your ASG.
resource "aws_lb_listener_rule" "asg"{
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition = {
    path_pattern = {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

variable "server_port" {
  description = "The port the server will listen on for HTTP requests"
  type        = number
  default     = 8080
}

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}
