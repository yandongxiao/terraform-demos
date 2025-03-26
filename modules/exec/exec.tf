variable "a" {
  type    = any
  default = 10
}

resource "aws_instance" "exec" {
  ami           = "xxx"
  instance_type = "t3.micro"

  # provisioner is a meta-argument(元参数) that configures additional actions to take on the resource as it's being created.
  provisioner "local-exec" {
    command = "echo hello ${var.a}"
  }
}
