# Security Groups
resource "aws_security_group" "nodes" {
  name = "example-voting-app-nodes-sg"
  description = "Allow traffic to Kubernetes worker nodes"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "NodePort range from within VPC"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Outgoing traffic
  # Allow All outbound traffic
  egress {
    description = "Allow all outbound"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "example-voting-app-nodes-sg"
  }
}
