# Provider configuration with version constraint
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# VPC Network
resource "google_compute_network" "wildlife_safari_vpc" {
  name                            = "wildlife-safari-vpc"
  auto_create_subnetworks        = false
  routing_mode                   = "REGIONAL"
  delete_default_routes_on_create = true
  description                    = "VPC network for Wildlife Safari backup and analytics infrastructure"
  project                        = var.project_id
}

# Subnet for backup storage services
resource "google_compute_subnetwork" "backup_subnet" {
  name                     = "backup-subnet"
  ip_cidr_range           = "10.0.1.0/24"
  region                  = var.region
  network                 = google_compute_network.wildlife_safari_vpc.id
  private_ip_google_access = true
  project                 = var.project_id

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  secondary_ip_range {
    range_name    = "backup-pods"
    ip_cidr_range = "10.1.0.0/16"
  }
}

# Subnet for analytics services
resource "google_compute_subnetwork" "analytics_subnet" {
  name                     = "analytics-subnet"
  ip_cidr_range           = "10.0.2.0/24"
  region                  = var.region
  network                 = google_compute_network.wildlife_safari_vpc.id
  private_ip_google_access = true
  project                 = var.project_id

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  secondary_ip_range {
    range_name    = "analytics-pods"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Firewall rule for internal network communication
resource "google_compute_firewall" "allow_internal" {
  name        = "allow-internal"
  network     = google_compute_network.wildlife_safari_vpc.id
  direction   = "INGRESS"
  project     = var.project_id
  description = "Allow internal network communication"

  source_ranges = ["10.0.0.0/8"]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  target_tags = ["internal"]
}

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_checks" {
  name        = "allow-health-checks"
  network     = google_compute_network.wildlife_safari_vpc.id
  direction   = "INGRESS"
  project     = var.project_id
  description = "Allow Google Cloud health check probes"

  source_ranges = [
    "35.191.0.0/16",  # GCP Health Checking Service
    "130.211.0.0/22"  # GCP Load Balancer Service
  ]

  allow {
    protocol = "tcp"
  }

  target_tags = ["load-balanced-backend"]
}

# Cloud NAT for private instances to access internet
resource "google_compute_router" "router" {
  name    = "wildlife-safari-router"
  region  = var.region
  network = google_compute_network.wildlife_safari_vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "wildlife-safari-nat"
  router                            = google_compute_router.router.name
  region                            = var.region
  project                           = var.project_id
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Default route for internet access
resource "google_compute_route" "internet_route" {
  name             = "internet-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.wildlife_safari_vpc.id
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  project          = var.project_id
}

# VPC peering connection for cross-region communication
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.wildlife_safari_vpc.id
  project       = var.project_id
}

# VPC Service Controls for enhanced security
resource "google_compute_security_policy" "policy" {
  name        = "wildlife-safari-security-policy"
  description = "Security policy for Wildlife Safari VPC"
  project     = var.project_id

  rule {
    action   = "deny(403)"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny rule"
  }

  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["10.0.0.0/8"]
      }
    }
    description = "Allow internal traffic"
  }
}