resource "aws_security_group" "main" {
  name        = "${local.name_prefix}-sg"
  description = "${local.name_prefix}-sg"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name_prefix}-sg" })

  ingress {
    description = "SSH"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = var.shh_ingress_cidr
  }
  ingress {
    description = "APP"
    from_port   = var.port
    protocol    = "tcp"
    to_port     = var.port
    cidr_blocks = var.sg_ingress_cidr
  }
  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_policy" "main" {
  name        = "${local.name_prefix}-policy"
  path        = "/"
  description = "${local.name_prefix}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ],
        "Resource" : local.policy_resources
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : "ssm:DescribeParameters",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role" "main" {
  name = "${local.name_prefix}-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Sid       = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(local.tags, { Name = "${local.name_prefix}-role" })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.main.name
  policy_arn = aws_iam_policy.main.arn
}
resource "aws_iam_instance_profile" "main" {
  name = "${local.name_prefix}-role-profile"
  role = aws_iam_role.main.name
}

resource "aws_launch_template" "main" {
  name                   = local.name_prefix
  image_id               = data.aws_ami.ami.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.main.id]
  iam_instance_profile {
    name = "${local.name_prefix}-role-profile"
  }
  user_data = base64encode(templatefile("${path.module}/userdata.sh",
    {
      component = var.component
      env       = var.env
    }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-ec2" })
  }
}

resource "aws_autoscaling_group" "main" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = var.subnet_ids
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size
  target_group_arns   = [aws_lb_target_group.main.arn]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = local.name_prefix
  }
}
resource "aws_route53_record" "main" {
  zone_id = var.zone_id
  name    = var.component == "frontend" ? var.env : "${var.component}-${var.env}"
  type    = "CNAME"
  ttl     = 30
  records = [var.component == "frontend" ?  var.public_alb_name : var.private_alb_name]
}

resource "aws_lb_target_group" "main" {
  name     = "${local.name_prefix}-tg"
  port     = var.port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = var.private_listener
  priority     = var.lb_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [
        var.component == "frontend" ? "${var.env}.vinithaws.online" : "${var.component}-${var.env}.vinithaws.online"
      ]
    }
  }
}

resource "aws_lb_target_group" "public" {
  count       = var.component == "frontend" ? 1 : 0
  name        = "${local.name_prefix}-public-tg"
  port        = var.port
  target_type = "ip"
  protocol    = "HTTP"
  vpc_id      = var.default_vpc_id
}
resource "aws_lb_target_group_attachment" "public" {
  #  depends_on = [aws_lb_target_group.public]
  count             = var.component == "frontend" ? length(var.subnet_ids ) : 0
  #length(tolist(data.dns_a_record_set.private_alb_records.addrs)) both are 2 AZ's
  target_group_arn  = aws_lb_target_group.public[0].arn
  target_id         = element(tolist(data.dns_a_record_set.private_alb_records.addrs), count.index )
  port              = 80
  availability_zone = "all"
}

resource "aws_lb_listener_rule" "public" {
  #  depends_on = [aws_lb_target_group.public]
  count        = var.component == "frontend" ? 1 : 0
  listener_arn = var.public_listener
  priority     = var.lb_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public[0].arn
  }

  condition {
    host_header {
      values = ["${var.env}.vinithaws.online"]
    }
  }
}


