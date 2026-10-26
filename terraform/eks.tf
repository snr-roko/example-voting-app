# Role for EKS Control Plane
resource "aws_iam_role" "eks_cluster" {
  name = "example-voting-app-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Role for EKS Worker Nodes
resource "aws_iam_role" "eks_node" {
  name = "example-voting-app-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Attaching Policies to the EKS Node Role
resource "aws_iam_role_policy_attachment" "eks_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "example-voting-app"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
]

  tags = {
    Name = "example-voting-app-eks"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "example-voting-app-node-group"
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    min_size  = 1
    max_size  = 3
    desired_size = 2
  }

  node_role_arn = aws_iam_role.eks_node.arn

  ami_type = "AL2_x86_64"

  labels = {
    "app" = "example-voting-app"
  }

  tags = {
    "Name" = "example-voting-app-node-group"
  }
}