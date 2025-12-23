resource "aws_route_table" "this" {
  vpc_id = var.vpc_id

  tags = {
    Name = var.route_table_name
  }
}

resource "aws_route_table_association" "this" {
  subnet_id      = var.subnet_id
  route_table_id = aws_route_table.this.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.this.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = var.gateway_id
  depends_on             = [aws_internet_gateway.this]
}
