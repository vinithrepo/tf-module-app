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

resource "aws_launch_template" "main" {
  name        = "${local.name_prefix}-"
  image_id      = data.aws_ami.ami.id
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.main.id]
  user_data = base64encode(templatefile("${path.module}/userdata.sh",
    {
      component = var.component
  }))

  tag_specifications {
    resource_type = "instance"
    tags        = merge(local.tags, { Name = "${local.name_prefix}-ec2" })
  }
}

#resource "aws_autoscaling_group" "main" {
#  availability_zones = ["us-east-1a"]
#  desired_capacity   = 1
#  max_size           = 1
#  min_size           = 1
#
#  launch_template {
#    id      = aws_launch_template.main.id
#    version = "$Latest"
#  }
#}