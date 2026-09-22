data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_iam_policy_document" "ci_server_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "ci_server_eks_access" {
  statement {
    effect = "Allow"

    actions = [
      "eks:DescribeCluster",
      "eks:DescribeNodegroup",
      "eks:ListClusters",
      "eks:ListNodegroups"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "ci_server" {
  name               = "${var.project_name}-ci-server"
  assume_role_policy = data.aws_iam_policy_document.ci_server_assume_role.json

  tags = {
    Name        = "${var.project_name}-ci-server"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "ci_server_eks_access" {
  name   = "${var.project_name}-ci-server-eks-access"
  role   = aws_iam_role.ci_server.id
  policy = data.aws_iam_policy_document.ci_server_eks_access.json
}

resource "aws_iam_instance_profile" "ci_server" {
  name = "${var.project_name}-ci-server"
  role = aws_iam_role.ci_server.name

  tags = {
    Name        = "${var.project_name}-ci-server"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_instance" "ci_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public[var.ec2_subnet_az].id
  vpc_security_group_ids      = [aws_security_group.ci_server.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ci_server.name
  user_data                   = file("${path.module}/../skills/install_tools.sh")

  root_block_device {
    volume_size = var.ec2_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name        = "${var.project_name}-ci-server"
    Project     = var.project_name
    Environment = var.environment
  }
}
