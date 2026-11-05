###############################################################################
# Security Groups Module
#
# Creates:
#   • sg_k3s_server   – inbound: operator-restricted HTTP/API ports, cluster ports,
#                       Flannel VXLAN (8472), plus all cluster-internal traffic
#   • sg_agent        – inbound: HTTP (8000) from within VPC only
#   • sg_alb          – inbound: 80 / 443 from Internet (for future ALB)
###############################################################################

###############################################################################
# k3s Server / Node Security Group
###############################################################################

resource "aws_security_group" "k3s_server" {
  name        = "${var.project}-${var.environment}-k3s-server"
  description = "k3s server node - API server + cluster traffic"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k3s-server-sg"
  })
}

# SSH – restrict to your management CIDR in production
resource "aws_security_group_rule" "k3s_ssh_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "SSH from management CIDR"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
}

# k3s API server
resource "aws_security_group_rule" "k3s_api_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "k3s Kubernetes API server"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = concat(var.ssh_allowed_cidrs, [var.vpc_cidr])
}

# RCA Agent API NodePort
resource "aws_security_group_rule" "rca_agent_nodeport_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "RCA Agent API from management CIDRs"
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
}

# ArgoCD is exposed through this NodePort by scripts/install-argocd.sh.
resource "aws_security_group_rule" "argocd_nodeport_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "ArgoCD from management CIDRs"
  from_port         = 30443
  to_port           = 30443
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
}

# Flannel VXLAN (UDP 8472) – intra-cluster overlay
resource "aws_security_group_rule" "k3s_flannel_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "Flannel VXLAN overlay"
  from_port         = 8472
  to_port           = 8472
  protocol          = "udp"
  self              = true
}

# Kubelet metrics / health
resource "aws_security_group_rule" "k3s_kubelet_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "Kubelet metrics and health"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  self              = true
}

# HTTP ingress via Traefik, restricted to operator CIDRs.
resource "aws_security_group_rule" "k3s_http_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "HTTP traffic"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
}

# HTTPS ingress, restricted to operator CIDRs.
resource "aws_security_group_rule" "k3s_https_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "HTTPS traffic"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
}

# SRE-agent FastAPI port (direct access during dev)
resource "aws_security_group_rule" "k3s_agent_api_in" {
  type              = "ingress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "SRE-agent FastAPI (dev / NodePort)"
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidrs
}

# All outbound allowed
resource "aws_security_group_rule" "k3s_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.k3s_server.id
  description       = "All outbound"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

###############################################################################
# Application Load Balancer Security Group (for future ALB / Ingress)
###############################################################################

resource "aws_security_group" "alb" {
  name        = "${var.project}-${var.environment}-alb"
  description = "Public ALB - HTTP/HTTPS from Internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb-sg"
  })
}
