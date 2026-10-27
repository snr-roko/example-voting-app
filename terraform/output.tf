output "cluster_endpoint" {
  description = "Cluster endpoint URL"
  value = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "vpc_id" {
  description = "ID of the VPC containing the cluster"
  value       = aws_vpc.main.id
}

output "node_group_name" {
  description = "Name of the EKS node group"
  value       = aws_eks_node_group.default.node_group_name
}

output "connection_info" {
  description = "Grouped connection information for the cluster"
  value = {
    cluster_endpoint = aws_eks_cluster.main.endpoint
    cluster_name     = aws_eks_cluster.main.name
    region           = "us-east-1"
    vpc_id           = aws_vpc.main.id
    node_group       = aws_eks_node_group.default.node_group_name
  }
}