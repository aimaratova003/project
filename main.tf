resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  count                  = 3
  vpc_id                 = aws_vpc.main.id
  cidr_block             = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count                  = 3
  vpc_id                 = aws_vpc.main.id
  cidr_block             = "10.0.${count.index + 3}.0/24"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_nat_gateway" "nat" {
  count             = 3
  subnet_id         = aws_subnet.public[count.index].id
  allocation_id     = aws_eip.nat[count.index].id
}

resource "aws_eip" "nat" {
  count = 3
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}



resource "aws_route_table" "private" {
  count = 3
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat[count.index].id
  }

}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}" 
  route_table_id = aws_route_table.private[count.index].id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

provider "aws" {
  region = "us-east-2"
}

resource "aws_security_group" "web_sg" {
  name        = "wordpress"
  description = "wordpress"
  vpc_id      = aws_vpc.main.id  
} 

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access from anywhere"
  }



  resource "aws_security_group" "db-sg" {
  vpc_id = aws_vpc.main.id
  name   = "db-sg"
  description = "Allow access to our DB from anywhere"

  ingress {
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 63306
    # security_groups = [aws_security_group.allow_tls.id]  # Replace <instance> with the actual identifier of your instance's security group
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "db-sg"
  }
}

#ALB
resource "aws_lb" "app_lb" {
  name               = "my-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "my-app-lb"
  }
}
resource "aws_security_group" "public_sg" {
  description = "public_sg"
  name = "public_sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow traffic from anywhere
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]  # Allow traffic to anywhere
  }
} 

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "OK"
      status_code  = 200
    }
}
}

resource "aws_lb_target_group" "app_target_group" {
  name     = "my-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb_listener_rule" "app_listener_rule" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
  condition {
    host_header {
      values = ["wordpress.pauldchang.com"]  # Replace with your domain name
    }
  }
}

# RDS cluster
resource "aws_rds_cluster" "rds-cluster" {
  cluster_identifier        = "rds-cluster"
  availability_zones = ["us-east-2a", "us-east-2b"] #Update the AZs accordingly
  engine                    = "aurora-mysql"
  engine_version            = "5.7.mysql_aurora.2.12.1"
  database_name             = var.db_name
  master_username           = var.db_username
  master_password           = var.db_password
  skip_final_snapshot       = true
}

resource "aws_rds_cluster_instance" "writer" {
  apply_immediately  = true
  cluster_identifier = aws_rds_cluster.rds-cluster.id
  identifier         = "writer"
  instance_class     = "db.t2.small"
  engine             = aws_rds_cluster.rds-cluster.engine
  engine_version     = aws_rds_cluster.rds-cluster.engine_version
}

resource "aws_rds_cluster_instance" "rds-reader1" {
  apply_immediately  = true
  cluster_identifier = aws_rds_cluster.rds-cluster.id
  identifier         = "reader1"
  instance_class     = "db.t2.small"
  engine             = aws_rds_cluster.rds-cluster.engine
  engine_version     = aws_rds_cluster.rds-cluster.engine_version
}

resource "aws_rds_cluster_instance" "rds-reader2" {
  apply_immediately  = true
  cluster_identifier = aws_rds_cluster.rds-cluster.id
  identifier         = "reader2"
  instance_class     = "db.t2.small"
  engine             = aws_rds_cluster.rds-cluster.engine
  engine_version     = aws_rds_cluster.rds-cluster.engine_version
}

resource "aws_rds_cluster_endpoint" "eligible" {
  cluster_identifier          = aws_rds_cluster.rds-cluster.id
  cluster_endpoint_identifier = "reader"
  custom_endpoint_type        = "READER"

  excluded_members = [
    aws_rds_cluster_instance.writer.id,
    aws_rds_cluster_instance.rds-reader1.id,
  ]
}

resource "aws_rds_cluster_endpoint" "static" {
  cluster_identifier          = aws_rds_cluster.rds-cluster.id
  cluster_endpoint_identifier = "static"
  custom_endpoint_type        = "READER"

  static_members = [
    aws_rds_cluster_instance.writer.id,
    aws_rds_cluster_instance.rds-reader2.id,
  ]
}
resource "aws_rds_cluster" "rds-cluster" {
  cluster_identifier        = "rds-cluster"
  availability_zones = ["us-east-2a", "us-east-2b"] #Update the AZs accordingly
  engine                    = "aurora-mysql"
  engine_version            = "5.7.mysql_aurora.2.12.1"
  database_name             = var.db_name
  master_username           = var.db_username
  master_password           = var.db_password
  skip_final_snapshot       = true
}

resource "aws_rds_cluster_instance" "writer" {
  apply_immediately  = true
  cluster_identifier = aws_rds_cluster.rds-cluster.id
  identifier         = "writer"
  instance_class     = "db.t2.small"
  engine             = aws_rds_cluster.rds-cluster.engine
  engine_version     = aws_rds_cluster.rds-cluster.engine_version
}
resource "aws_rds_cluster_instance" "rds-reader1" {
  apply_immediately  = true
  cluster_identifier = aws_rds_cluster.rds-cluster.id
  identifier         = "reader1"
  instance_class     = "db.t2.small"
  engine             = aws_rds_cluster.rds-cluster.engine
  engine_version     = aws_rds_cluster.rds-cluster.engine_version
}

resource "aws_rds_cluster_instance" "rds-reader2" {
  apply_immediately  = true
  cluster_identifier = aws_rds_cluster.rds-cluster.id
  identifier         = "reader2"
  instance_class     = "db.t2.small"
  engine             = aws_rds_cluster.rds-cluster.engine
  engine_version     = aws_rds_cluster.rds-cluster.engine_version
}

resource "aws_rds_cluster_endpoint" "eligible" {
  cluster_identifier          = aws_rds_cluster.rds-cluster.id
  cluster_endpoint_identifier = "reader"
  custom_endpoint_type        = "READER"

  excluded_members = [
    aws_rds_cluster_instance.writer.id,
    aws_rds_cluster_instance.rds-reader1.id,
  ]
}

resource "aws_rds_cluster_endpoint" "static" {
  cluster_identifier          = aws_rds_cluster.rds-cluster.id
  cluster_endpoint_identifier = "static"
  custom_endpoint_type        = "READER"

  static_members = [
    aws_rds_cluster_instance.writer.id,
    aws_rds_cluster_instance.rds-reader2.id,
  ]
}
variable "db_name" {
  description = "Name of the Database."
  type        = string
  default = "wordpressdb"
}

variable "db_username" {
  description = "Master user name"
  type        = string
  default = "wordpress"
}

variable "db_password" {
  description = "Master password"
  type        = string
  default = "password"
}
