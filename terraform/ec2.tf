// A key pair for Dystroxic to use
resource "aws_key_pair" "dystroxic" {
  key_name   = "dystroxic-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDzod++8ckd99EwmS0fvUHtjL0IVng6kSRXM08Nhd1ayz9a/YBcO6vna1FCPjK10tNiZtYWyZJWXk6v2k6xk/wtRM4Gr3FBTj48LjaGjFwlCA+rt6UDTKlLdEVnUwzk9+PJnYZr2lG3HAE+8nGHu9epnU4FEFF6/9apShIW7EqcRoFmNeH5Gq8YIVFP/RCFW6DFebhfFaw0T4BQkrPbWqmZl4vkecK4fAjgfZufnLdGaxtI9wrfBk41w2WiQWcVhc1WRXmqBEGKQYWRvQWsQjsF/Qo1QpHSmMZ5UvesfuTwFlCNu2/+5jtnn1mcOP/cXFKSB3VLyX5dJlhrbcxnGWZEbpJuqiyht4KrufeTND2hYLS1uVMUkuv5yWHWNfUkOQTohLtLjbbHTdKaJl9hFFSf/B8ACUFDV76Lmyibf8CO2urwJnzeDnFN4GSfOoHxKTi3Ds5OohVRhfodNRQ/Ut/iE8hWPdNTUCLavsnwG31vJpg9xfFtbsBfA3s1mSy4cpRe5PF0yaZKuKI7ur9KDVRmG6V6t/PcDqdMqngorePsEBvbl0jeuO2L0qbdBCgknniKxzOPyQZxIb9hQnaGWv3m7HIaTLVoUrv9exF/rzEC8phZ6c++cDFFjADj7yULvBWl7ZPrf5xBCG1O8KWoSJYANaVpAqlhCUYXdn9eJDksw== KotowickKey"
}

data "aws_ami" "ubuntu-20-04" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}
// Create an EC2 instance to use as an ARMA server
resource "aws_instance" "arma_server_linux" {
  ami           = data.aws_ami.ubuntu-20-04.id
  instance_type = local.instance_size_small
  key_name      = aws_key_pair.dystroxic.id
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [
    aws_security_group.ssh-ingress.id,
    aws_security_group.https-egress.id,
    aws_security_group.http-egress.id,
    aws_security_group.http-ingress.id,
    aws_security_group.https-ingress.id,
    aws_security_group.arma-server.id
  ]
  root_block_device {
    volume_type           = "gp2"
    volume_size           = local.instance_ssd_size
    delete_on_termination = false
  }
  tags = {
    Name = "ARMA Server - Ubuntu 20.04"
  }
  // Don't destroy the server if the AMI has been updated
  lifecycle {
    ignore_changes = [
      ami,
      ebs_optimized,
      key_name
    ]
  }
}
// Associate an Elastic IP with the instance so we can easily access it
resource "aws_eip" "arma_linux" {
  vpc      = true
  instance = aws_instance.arma_server_linux.id
}
output "arma-server-linux-ip" {
  value = aws_eip.arma_linux.public_ip
}
