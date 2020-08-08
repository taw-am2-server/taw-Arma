resource "aws_security_group" "http-egress" {
  name                   = "http_egress"
  description            = "Allow egress on HTTP port (80)"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP Egress"
  }
}

resource "aws_security_group" "https-egress" {
  name                   = "https_egress"
  description            = "Allow egress to HTTPS port (443)"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTPS Egress"
  }
}

resource "aws_security_group" "http-ingress" {
  name                   = "http_ingress"
  description            = "Allow ingress on HTTP port (80)"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP Ingress"
  }
}

resource "aws_security_group" "https-ingress" {
  name                   = "https_ingress"
  description            = "Allow ingress on HTTPS port (443)"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTPS Ingress"
  }
}

resource "aws_security_group" "ssh-ingress" {
  name                   = "ssh_ingress"
  description            = "Allow ingress on SSH port (22)"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  // Allow ingress on port 22 (SSH)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Can connect on SSH from anywhere
  }

  tags = {
    Name = "SSH Ingress"
  }
}

resource "aws_security_group" "rdp-ingress" {
  name                   = "rdp_ingress"
  description            = "Allow ingress on RDP port (3389)"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  // Allow ingress on port 3389 (RDP)
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDP Ingress"
  }
}

resource "aws_security_group" "arma-server" {
  name                   = "arma_server"
  description            = "Allow all ingress/egress for an ARMA server"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = true

  // Allow ping
  ingress {
    description = "Allow echo-reply (ping)"
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "icmp"
    from_port   = 0
    to_port     = -1
  }

  // Configure ingress ports for 10 game servers
  dynamic "ingress" {
    for_each = range(10)
    content {
      description = "ARMA game server ${ingress.value}"
      from_port   = 2302 + (ingress.value * 10)
      to_port     = 2306 + (ingress.value * 10)
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  // ARMA Web console
  ingress {
    description = "Allow accessing ARMA web console"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Allow all egress
  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  tags = {
    Name = "ARMA Server"
  }
}
