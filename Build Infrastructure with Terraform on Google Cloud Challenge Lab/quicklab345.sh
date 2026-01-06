#!/bin/bash
set -euo pipefail

# ----------------------------
# Fixed lab values (yours)
# ----------------------------
PROJECT_ID="qwiklabs-gcp-00-82abc45374f5"
REGION="us-central1"
ZONE="us-central1-c"
BUCKET_NAME="tf-bucket-976669"
VPC_NAME="tf-vpc-678689"

# If your lab provides a required new instance name, set it here (optional)
# INSTANCE_NAME="tf-instance-908251"
INSTANCE_NAME="${INSTANCE_NAME:-tf-instance-new}"

export PROJECT_ID REGION ZONE BUCKET_NAME VPC_NAME INSTANCE_NAME

gcloud auth list

# ----------------------------
# Create folders/files
# ----------------------------
mkdir -p ~/tf-lab/modules/instances ~/tf-lab/modules/storage
cd ~/tf-lab

touch main.tf variables.tf
touch modules/instances/instances.tf modules/instances/outputs.tf modules/instances/variables.tf
touch modules/storage/storage.tf modules/storage/outputs.tf modules/storage/variables.tf

# ----------------------------
# Root variables.tf
# ----------------------------
cat > variables.tf <<EOF
variable "region" {
  default = "$REGION"
}

variable "zone" {
  default = "$ZONE"
}

variable "project_id" {
  default = "$PROJECT_ID"
}
EOF

# ----------------------------
# Root main.tf (providers + modules + backend)
# Backend config passed via terraform init -backend-config
# ----------------------------
cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.53.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "instances" {
  source = "./modules/instances"
}

module "storage" {
  source = "./modules/storage"
}
EOF

# ----------------------------
# Instances module
# ----------------------------
cat > modules/instances/instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
EOT

  allow_stopping_for_update = true

  # IMPORTANT: these are imported, so don't try to "fix" them
  lifecycle {
    ignore_changes = all
  }
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
EOT

  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = all
  }
}

# Optional: create a new instance (if your lab needs it)
resource "google_compute_instance" "new_instance" {
  name         = "$INSTANCE_NAME"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = <<-EOT
#!/bin/bash
EOT

  allow_stopping_for_update = true
}
EOF

# ----------------------------
# Storage module
# ----------------------------
cat > modules/storage/storage.tf <<EOF
resource "google_storage_bucket" "storage-bucket" {
  name          = "$BUCKET_NAME"
  location      = "US"
  force_destroy = true
  uniform_bucket_level_access = true
}
EOF

# ----------------------------
# Terraform init (backend config here)
# ----------------------------
terraform fmt -recursive

terraform init -reconfigure \
  -backend-config="bucket=$BUCKET_NAME" \
  -backend-config="prefix=terraform/state"

terraform validate

# ----------------------------
# Import existing instances (correct import IDs)
# ----------------------------
terraform import "module.instances.google_compute_instance.tf-instance-1" "$PROJECT_ID/$ZONE/tf-instance-1"
terraform import "module.instances.google_compute_instance.tf-instance-2" "$PROJECT_ID/$ZONE/tf-instance-2"

# ----------------------------
# Plan + Apply
# ----------------------------
terraform plan
terraform apply --auto-approve

echo
echo "DONE ✅"
echo "Imported: tf-instance-1, tf-instance-2"
echo "Backend bucket: $BUCKET_NAME"
echo "VPC name (not used in this script): $VPC_NAME"
echo "New instance (if created): $INSTANCE_NAME"
