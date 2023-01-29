output "instance_id" {
  description = "ID of the EC2 instance"
  value = aws_instance.openapi_node.*.id
}

output "node_id" {
  value = aws_instance.openapi_node.*.tags.NodeID
}

output "instance_public_ip" {
  value = aws_instance.openapi_node.*.public_ip
}

output "instance_private_ips" {
  value = aws_instance.openapi_node[*].private_ip
}
