# Security Groups
resource "aws_security_group" "nodes" {
  name = "example-voting-app-nodes-sg"
  description = "Allow traffic to Kubernetes worker nodes"
  vpc_id = aws_vpc.main.id

  # Allowing SSH
  ingress {
    description = "SSH from anywhere"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Http
  ingress {
    description = "Allow Http from anywhere"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    description = "Allow HTTPS from anywhere"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
