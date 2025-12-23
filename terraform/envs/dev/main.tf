provider "aws" {
  region = "us-east-1" # غيرها حسب منطقتك
}

module "vpc" {
  source     = "../../modules/vpc"
  cidr_block = "10.0.0.0/16"
  vpc_name   = "mern-app-vpc"
}

module "public_subnet" {
  source                 = "../../modules/subnet"
  vpc_id                 = module.vpc.vpc_id
  cidr_block             = "10.0.1.0/24"
  availability_zone      = "us-east-1a"
  map_public_ip_on_launch = true
  subnet_name            = "public-subnet"
}

module "private_subnet" {
  source                 = "../../modules/subnet"
  vpc_id                 = module.vpc.vpc_id
  cidr_block             = "10.0.2.0/24"
  availability_zone      = "us-east-1a"
  map_public_ip_on_launch = false
  subnet_name            = "private-subnet"
}

module "internet_gateway" {
  source   = "../../modules/internet_gateway"
  vpc_id   = module.vpc.vpc_id
  igw_name = "mern-app-igw"
}

module "public_route_table" {
  source           = "../../modules/route_table"
  vpc_id           = module.vpc.vpc_id
  subnet_id        = module.public_subnet.subnet_id
  gateway_id       = module.internet_gateway.igw_id
  route_table_name = "public-route-table"
}

resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow MongoDB access from web server"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "webserver" {
  source           = "../../modules/ec2"
  ami              = "ami-0c02fb55956c7d316" # Ubuntu 20.04 - غيرها حسب منطقتك
  instance_type    = "t3.micro"
  subnet_id        = module.public_subnet.subnet_id
  key_name         = "my-key"  # اسم key pair بتاعك في AWS
  security_group_id = aws_security_group.web_sg.id
  instance_name    = "web-server"
}

module "dbserver" {
  source           = "../../modules/ec2"
  ami              = "ami-0c02fb55956c7d316"
  instance_type    = "t3.micro"
  subnet_id        = module.private_subnet.subnet_id
  key_name         = "my-key"
  security_group_id = aws_security_group.db_sg.id
  instance_name    = "db-server"
}
