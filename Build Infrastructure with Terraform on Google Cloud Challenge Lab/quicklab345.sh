#!/bin/bash
set -e

# Given by you
PROJECT_ID="qwiklabs-gcp-00-82abc45374f5"
BUCKET_NAME="tf-bucket-976669"
INSTANCE_NAME="tf-instance-908251"
VPC_NAME="tf-vpc-678689"

# Lab defaults (change if your lab says otherwise)
REGION="us-central1"
ZONE="us-central1-c"

echo "Project: $PROJECT_ID"
echo "Region:  $REGION"
echo "Zone:    $ZONE"
echo "Bucket:  $BUCKET_NAME"
echo "VPC:     $VPC_NAME"
echo "New VM:   $INSTANCE_NAME"

# Grab the existing 2 instance names so we can import properly
# (Usually they are tf-instance-1 and tf-instance-2)
EXISTING_NAMES=($(gcloud compute instances list --project "$PROJECT_ID" --format="value(name)" | head -n 2))

if [ "${#EXISTING_NAMES[@]}" -lt 2 ]; then
  echo "ERROR: Could not find 2 existing instances to import."
  gcloud compute instances list --project "$PROJECT_ID"
  exit 1
fi

EXISTING_1="${EXISTING_NAMES[0]}"
EXISTING_2="${EXISTING_NAMES[1]}"

echo "Existing instances detected: $EXISTING_1, $EXISTING_2"

cd ~
rm -rf modules
mkdir -p modules/instances modules/storage

# -------------------------
# Root variables.tf
# -------------------------
cat > ~/variables.tf <<EOF
variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "project_id" {
  type    = string
  default = "$PROJECT_ID"
}

variable "bucket_name" {
  type    = string
  default = "$BUCKET_NAME"
}

variable "vpc_name" {
  type    = string
  default = "$VPC_NAME"
}

variable "instance_name" {
  type    = string
  default = "$INSTANCE_NAME"
}
EOF

# -------------------------
# Root main.tf
# -------------------------
cat > ~/main.tf <<EOF
terraform {
  backend "gcs" {
    bucket = "tf-bucket-976669"
    prefix = "terraform/state"
  }
}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.53.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 6.0.0"

  project_id   = var.project_id
  network_name = var.vpc_name
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = var.region
    },
    {
      subnet_name           = "subnet-02"
      subnet_ip             = "10.10.20.0/24"
      subnet_region         = var.region
      subnet_private_access = true
      subnet_flow_logs      = true
      description           = "Private subnet"
    }
  ]
}

module "instances" {
  source = "./modules/instances"

  project_id     = var.project_id
  region         = var.region
  zone           = var.zone

  network_self_link = module.vpc.network_self_link
  subnet_01_name    = module.vpc.subnets_names[0]
  subnet_02_name    = module.vpc.subnets_names[1]

  existing_1_name = "$EXISTING_1"
  existing_2_name = "$EXISTING_2"
  new_name        = var.instance_name
}

module "storage" {
  source = "./modules/storage"

  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  bucket_name  = var.bucket_name
}

resource "google_compute_firewall" "tf_firewall" {
  name    = "tf-firewall"
  network = module.vpc.network_self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}
EOF

# -------------------------
# modules/instances/variables.tf
# (Lab requirement: add region/zone/project_id here too)
# -------------------------
cat > ~/modules/instances/variables.tf <<EOF
variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "project_id" {
  type = string
}

variable "network_self_link" {
  type = string
}

variable "subnet_01_name" {
  type = string
}

variable "subnet_02_name" {
  type = string
}

variable "existing_1_name" {
  type = string
}

variable "existing_2_name" {
  type = string
}

variable "new_name" {
  type = string
}
EOF

# -------------------------
# modules/instances/instances.tf
# - Manage 2 existing instances (for import) + 1 new instance
# - Use var.zone (fixes your zone error)
# - Attach to correct subnet names
# -------------------------
cat > ~/modules/instances/instances.tf <<EOF
resource "google_compute_instance" "tf-instance-1" {
  name         = var.existing_1_name
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnet_01_name
  }

  tags = ["web"]
  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf-instance-2" {
  name         = var.existing_2_name
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnet_02_name
  }

  tags = ["web"]
  allow_stopping_for_update = true
}

resource "google_compute_instance" "new_instance" {
  name         = var.new_name
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnet_01_name
  }

  tags = ["web"]
  allow_stopping_for_update = true
}
EOF

# -------------------------
# modules/storage/variables.tf
# (Lab requirement: add region/zone/project_id here too)
# -------------------------
cat > ~/modules/storage/variables.tf <<EOF
variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "project_id" {
  type = string
}

variable "bucket_name" {
  type = string
}
EOF

# -------------------------
# modules/storage/storage.tf
# -------------------------
cat > ~/modules/storage/storage.tf <<EOF
resource "google_storage_bucket" "storage_bucket" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true
  uniform_bucket_level_access = true
}
EOF

# -------------------------
# Terraform init + imports + apply
# -------------------------
cd ~
terraform init

# Import the two existing instances using full resource path (most reliable)
terraform import "module.instances.google_compute_instance.tf-instance-1" "projects/$PROJECT_ID/zones/$ZONE/instances/$EXISTING_1"
terraform import "module.instances.google_compute_instance.tf-instance-2" "projects/$PROJECT_ID/zones/$ZONE/instances/$EXISTING_2"

terraform plan
terraform apply --auto-approve

echo "DONE ✅"
