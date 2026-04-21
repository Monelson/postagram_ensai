variable "git_repo" {
  type    = string
  default = "https://github.com/Monelson/postagram_ensai.git"
}

########################################
# Security group rule to allow traffic on port 8080 (webservice)
########################################
resource "aws_security_group_rule" "allow_8080" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web_sg.id
}

########################################
# IAM Role + Instance Profile for EC2
########################################
resource "aws_iam_role" "ec2_role" {
  name = "postagram-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_dynamodb_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_rekognition_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "postagram-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

########################################
# Launch Template
########################################
resource "aws_launch_template" "ubuntu_template" {
  name_prefix   = "postagram-"
  image_id      = "ami-084568db4383264d4"
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    git_repo     = var.git_repo
    dynamo_table = aws_dynamodb_table.basic-dynamodb-table.name
    bucket       = aws_s3_bucket.bucket.bucket
  }))

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 8
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "postagram-instance"
    }
  }

  tags = {
    Name = "postagram"
  }
}

########################################
# Auto Scaling Group
########################################
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity    = 1
  max_size            = 4
  min_size            = 1
  vpc_zone_identifier = data.aws_subnets.default.ids
  health_check_type   = "EC2"
  target_group_arns   = [aws_lb_target_group.web_tg.arn]

  launch_template {
    id      = aws_launch_template.ubuntu_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "postagram-asg-instance"
    propagate_at_launch = true
  }
}

########################################
# Load Balancer (ALB)
########################################
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = {
    Name = "web-alb"
  }
}

########################################
# Target Group (pour le Load Balancer)
########################################
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/docs"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
  }

  tags = {
    Name = "web-tg"
  }
}

########################################
# Listener pour le Load Balancer
########################################
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

########################################
# Outputs
########################################
output "load_balancer_dns_name" {
  description = "Nom DNS du load balancer"
  value       = aws_lb.web_alb.dns_name
}