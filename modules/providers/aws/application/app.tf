# TAGS
variable application_dns  { default = "www.example.com" }  # ex. "www.example.com"
variable application      { default = "www"             }  # ex. "www" - short name used in object naming
variable environment      { default = "f5env"           }  # ex. dev/staging/prod
variable owner            { default = "f5owner"         }  
variable group            { default = "f5group"         }
variable costcenter       { default = "f5costcenter"    }  
variable purpose          { default = "public"          }  

# PLACEMENT
variable region                 { default = "us-west-2" }
variable vpc_id                 {}
variable availability_zones     { default = "us-west-2a,us-west-2b"}
variable subnet_ids             {}
variable restricted_src_address { default = "0.0.0.0/0" }

# APPLICATION
variable docker_image   { default = "f5devcentral/f5-demo-app:AWS" }
variable instance_type  { default = "t2.small" }
variable amis {     
    type = "map" 
    default = {
        "ap-northeast-1" = "ami-c9e3c0ae"
        "ap-northeast-2" = "ami-3cda0852"
        "ap-southeast-1" = "ami-6e74ca0d"
        "ap-southeast-2" = "ami-92e8e6f1"
        "eu-central-1" = "ami-1b4d9e74"
        "eu-west-1" = "ami-b5a893d3"
        "sa-east-1" = "ami-36187a5a"
        "us-east-1" = "ami-e4139df2"
        "us-east-2" = "ami-33ab8f56"
        "us-west-1" = "ami-30476250"
        "us-west-2" = "ami-17ba2a77"
    }
}

variable ssh_key_name        {}  # example "my-terraform-key"
# NOTE certs not used below but keeping as optional input in case need to extend
variable site_ssl_cert  { default = "not-required-if-terminated-on-lb" }
variable site_ssl_key   { default = "not-required-if-terminated-on-lb" }

# AUTO SCALE
variable scale_min      { default = 1 }
variable scale_max      { default = 3 }
variable scale_desired  { default = 1 }


### RESOURCES ###

resource "aws_security_group" "sg" {
  name        = "${var.application}-app-sg"
  description = "${var.application}-app-ports"
  vpc_id      = "${var.vpc_id}"

  # ssh access from anywhere
  ingress {
    from_port   = 22 
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.restricted_src_address}"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ping access from anywhere
  ingress {
    from_port   = 8 
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
      Name           = "${var.environment}-${var.application}-app-sg"
      application    = "${var.application}"
      environment    = "${var.environment}"
      owner          = "${var.owner}"
      group          = "${var.group}"
      costcenter     = "${var.costcenter}"

  }
}


data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.tpl")}"

  vars {
    docker_image        = "${var.docker_image}"
  }
}

resource "aws_launch_configuration" "as_conf" {
  name_prefix         = "${var.application}_app_lc_"
  key_name            = "${var.ssh_key_name}"
  image_id            = "${lookup(var.amis, var.region)}"
  instance_type       = "${var.instance_type}"
  security_groups     = ["${aws_security_group.sg.id}"]
  user_data           = "${data.template_file.user_data.rendered}"
  associate_public_ip_address = true
  lifecycle {
    create_before_destroy = true
  }
}

# NOTE App Pool Name Hardcoded
resource "aws_autoscaling_group" "asg" {
  name                      = "${var.environment}-${var.application} - ${aws_launch_configuration.as_conf.name}"
  vpc_zone_identifier       = ["${split(",", var.subnet_ids)}"] 
  availability_zones        = ["${split(",", var.availability_zones)}"]
  min_size                  = "${var.scale_min}"
  max_size                  = "${var.scale_max}"
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.as_conf.name}"
  lifecycle {
    create_before_destroy = true
  }
  provisioner "local-exec" {
    command = "sleep 120"
  }  
  tag {
    key = "Name"
    value = "${var.environment}-${var.application}-instance"
    propagate_at_launch = true
  }

  tag {
    key = "application"
    value = "${var.application}"
    propagate_at_launch = true
  }

  tag {
    key = "environment"
    value = "${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key = "owner"
    value = "${var.owner}"
    propagate_at_launch = true
  }

  tag {
    key = "group"
    value = "${var.group}"
    propagate_at_launch = true
  }

  tag {
    key = "costcenter"
    value = "${var.costcenter}"
    propagate_at_launch = true
  }


}

resource "aws_autoscaling_policy" "asg_policy" {
  name                   = "${var.application}-app-asg-policy"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.asg.name}"
}



### OUTPUTS ###


output "sg_id" { value = "${aws_security_group.sg.id}" }
output "sg_name" { value = "${aws_security_group.sg.name}" }

output "asg_id" { value = "${aws_autoscaling_group.asg.id}" }
output "asg_name" { value = "${aws_autoscaling_group.asg.name}" }

