#############################
# 1. Configuración principal
#############################
packer {
  required_version = ">= 1.8.0"
  required_plugins {
    amazon        = { source = "github.com/hashicorp/amazon",        version = ">= 1.0.0" }
    googlecompute = { source = "github.com/hashicorp/googlecompute", version = ">= 1.0.0" }
  }
}

#############################
# 2. AWS – source (builder)
#############################
source "amazon-ebs" "aws_ubuntu_node" {
  profile            = "packer"
  region             = var.aws_region
  source_ami         = var.aws_source_ami
  instance_type      = var.aws_instance_type
  subnet_id          = var.subnet_aws
  security_group_id  = var.sg_aws
  ssh_keypair_name        = var.keypair_aws
  ssh_private_key_file     = "/home/kevin/Documents/packer/maestria/MiKeyPair.pem"
  ssh_username       = "ubuntu"

  ami_name                   = "node-nginx-ami-{{timestamp}}"
  ami_description            = "Ubuntu 20.04 LTS con Node.js y Nginx"
  associate_public_ip_address = true

  tags = {
    CreatedBy     = "Packer"
    Stack         = "Node-Nginx"
    Base_Ami_Name = "{{ .SourceAMIName }}"
  }
}

#############################
# 3. GCP – source (builder)  (opcional)
#############################
source "googlecompute" "gcp_ubuntu_node" {
  credentials_file          = "./sa-packer.json"
  project_id                = var.gcp_project_id
  zone                      = var.gcp_zone
  machine_type              = "e2-micro"
  disk_size                 = 10
  ssh_username              = "packer"

  # Deben ser listas de strings:
  source_image_family       = "ubuntu-2004-lts"
  source_image_project_id   = ["ubuntu-os-cloud"]

  image_name                = var.gcp_image_name
  image_family              = "node-nginx-family"
}

################################
# 4. Build AWS (+ auto-deploy)
################################

build {
  name    = "build_aws_and_launch"
  sources = ["source.amazon-ebs.aws_ubuntu_node"]

  provisioner "shell" {
    script           = "install-aws.sh"
    environment_vars = ["NODE_VERSION=${var.node_version}"]
  }

  # First, save the AMI information to a manifest file
  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
    custom_data = {
      region = "${var.aws_region}"
      instance_type = "${var.aws_instance_type}"
      key_name = "${var.keypair_aws}"
      security_group_id = "${var.sg_aws}"
      subnet_id = "${var.subnet_aws}"
    }
  }

  # Then, use the manifest to launch an EC2 instance
  post-processor "shell-local" {
    inline = [
      "echo '→ Lanzando EC2 con la AMI recién creada…'",
      "AMI_ID=$(jq -r '.builds[-1].artifact_id' manifest.json | cut -d':' -f2)",
      "aws ec2 run-instances \\",
      "  --profile packer \\",
      "  --region ${var.aws_region} \\",
      "  --image-id $AMI_ID \\",
      "  --instance-type ${var.aws_instance_type} \\",
      "  --count 1 \\",
      "  --key-name ${var.keypair_aws} \\",
      "  --security-group-ids ${var.sg_aws} \\",
      "  --subnet-id ${var.subnet_aws} \\",
      "  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=PackerDemo}]' \\",
      "  --associate-public-ip-address"
    ]
  }

}


################################
# 5. Build GCP (+ auto-deploy)
################################
build {
  name    = "build_gcp_and_launch"
  sources = ["source.googlecompute.gcp_ubuntu_node"]

  provisioner "shell" {
    script           = "install.sh"
    environment_vars = ["NODE_VERSION=${var.node_version}"]
  }

  post-processor "shell-local" {
    inline = [
      "echo '→ Creando VM en GCP con la imagen…'",
      "gcloud compute instances create packer-demo-instance \\",
      "  --project=${var.gcp_project_id} \\",
      "  --zone=${var.gcp_zone} \\",
      "  --image=${var.gcp_image_name} \\",
      "  --machine-type=e2-micro \\",
      "  --tags=http-server"
    ]
  }
}
