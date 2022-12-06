resource "aws_vpc" "vpc_demo" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "vpc_demo"
  }
}

resource "aws_subnet" "public_subnets" {
 count             = length(var.public_subnet_cidrs)
 vpc_id            = aws_vpc.vpc_demo.id
 cidr_block        = element(var.public_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 map_public_ip_on_launch = true
 tags = {
   Name = "Public Subnet ${count.index + 1}"
 }
}
 
resource "aws_subnet" "private_subnets" {
 count             = length(var.private_subnet_cidrs)
 vpc_id            = aws_vpc.vpc_demo.id
 cidr_block        = element(var.private_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 
 tags = {
   Name = "Private Subnet ${count.index + 1}"
 }
}

resource "aws_launch_template" "webserver_lt" {
  name_prefix   = "webserver"
  image_id      = var.image_id
  instance_type = "t2.micro"
  #subnet_id     = aws_subnet.webserver_subnet.id
  vpc_security_group_ids = ["${aws_security_group.allow_http.id}"]
  #vpc_security_group_ids = ["${aws_security_group.allow_http.id}","${aws_security_group.allow_ssh.id}"]

  user_data     = "${base64encode(templatefile("user_data.tftpl",{}))}"
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.vpc_demo.id

  ingress {
    description      = "HTTP from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [aws_vpc.vpc_demo.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.vpc_demo.id

  ingress {
    description      = "HTTP from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group" "allow_http_alb" {
  name        = "allow_http_alb"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.vpc_demo.id

  ingress {
    description      = "HTTP from Internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_alb"
  }
}

resource "aws_internet_gateway" "gw" {
 vpc_id = aws_vpc.vpc_demo.id
 
 tags = {
   Name = "VPC IG"
 }
}

resource "aws_route_table" "internet_rt" {
 vpc_id = aws_vpc.vpc_demo.id
 
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 
 tags = {
   Name = "Internet Route Table"
 }
}

resource "aws_route_table_association" "public_subnet_asso" {
 count = length(var.public_subnet_cidrs)
 subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
 route_table_id = aws_route_table.internet_rt.id
}

resource "aws_lb" "webserver_alb" {
  name               = "webserver-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http_alb.id]
  subnets            = [for subnet in aws_subnet.public_subnets : subnet.id]
  enable_deletion_protection = false # PoC option!!
  tags = {
    Environment = "production"
  }
}
  # Define a listener
resource "aws_alb_listener" "webserver_alb_listener" {
  load_balancer_arn = "${aws_lb.webserver_alb.arn}"
  port              = "80"
  protocol          = "HTTP"
default_action {
    target_group_arn = "${aws_alb_target_group.webtg.arn}"
    type             = "forward"
  }
}
# Connect ASG up to the Application Load Balancer
resource "aws_alb_target_group" "webtg" {
  name     = "webtg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc_demo.id}"
}


resource "aws_autoscaling_group" "webserver_autoscaler" {
  desired_capacity   = 0
  max_size           = 2
  min_size           = 0
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  launch_template {
    id      = aws_launch_template.webserver_lt.id
    version = aws_launch_template.webserver_lt.latest_version
  }
  target_group_arns = [
"${aws_alb_target_group.webtg.arn}"
  ]
}