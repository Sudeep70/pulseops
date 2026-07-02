resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for PulseOps EC2 instances"
  vpc_id      = aws_vpc.main.id

  # Allow inbound HTTP requests to Flask application on port 5000 from the internet
  # This enables external users and our health poller Lambda to reach the app.
  ingress {
    description      = "Flask Application Port"
    from_port        = 5000
    to_port          = 5000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Allow all outbound traffic so instances can pull ECR images, 
  # update packages, and communicate with SSM endpoints.
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}
