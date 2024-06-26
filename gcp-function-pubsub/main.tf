terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}
data "archive_file" "source" {
  output_path = "${path.module}/${var.function_name}.zip"
  type        = "zip"
  source_dir = var.function_path
}

resource "google_storage_bucket" "function_bucket" {
  project  = var.project_id
  location = var.region
  name = "${var.project_id}-${var.function_name}"
}

resource "google_storage_bucket_object" "zip" {
  name = "${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.source.output_path
}

resource "google_service_account" "sa" {
  account_id = "${var.function_name}-sa"
}

resource "google_project_iam_member" "sa-roles" {
  project = var.project_id
  for_each = toset(var.roles)
  role = each.key
  member = "serviceAccount:${google_service_account.sa.email}"
}

resource "google_cloudfunctions2_function" "function" {
  name = var.function_name
  location = var.region

  build_config {
    runtime = var.runtime
    entry_point = var.entry_point
    environment_variables = var.build_environment_variables

    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.zip.name
      }
    }
  }

  service_config {
    min_instance_count = var.min_instance_count
    max_instance_count = var.max_instance_count
    timeout_seconds = var.timeout_seconds
    available_memory = var.available_memory
    available_cpu = var.available_cpu
    all_traffic_on_latest_revision = var.all_traffic_on_latest_revision
    environment_variables = var.environment_variables
    ingress_settings = var.ingress_settings
    vpc_connector = var.vpc_connector
    vpc_connector_egress_settings = var.vpc_connector_egress_settings
    service_account_email = google_service_account.sa.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = "projects/${var.project_id}/topics/${var.pubsub_topic}"
    retry_policy   = var.retry_policy
  }
}