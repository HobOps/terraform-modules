# Uptime checks
resource "google_monitoring_uptime_check_config" "default" {
  for_each = var.monitored_hosts
  display_name = each.key
  timeout = each.value["timeout"]
  period = each.value["period"]

  # http_check GET
  dynamic "http_check" {
    for_each = each.value["check"]["method"] == "GET" ? ["ok"] : []
    content {
      path = each.value["path"]
      port = each.value["port"]
      request_method = "GET"
      use_ssl = each.value["use_ssl"]
      validate_ssl = each.value["validate_ssl"]
    }
  }

  # http_check POST
  dynamic "http_check" {
    for_each = each.value["check"]["method"] == "POST" ? ["ok"] : []
    content {
      path = each.value["path"]
      port = each.value["port"]
      request_method = "POST"
      use_ssl = each.value["use_ssl"]
      validate_ssl = each.value["validate_ssl"]
      content_type = "URL_ENCODED"
      body = each.value["check"]["body_base64"]
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.monitoring_project_id
      host = each.value["host"]
    }
  }

  selected_regions = each.value["selected_regions"]
  content_matchers {
    content = each.value["content"]
    matcher = "CONTAINS_STRING"
  }
}

# Alert Policies
resource "google_monitoring_alert_policy" "default" {
  for_each = var.monitored_hosts
  depends_on = [google_monitoring_uptime_check_config.default]
  display_name = each.key
  enabled = each.value["alerts_enabled"]
  notification_channels = var.notification_channels
  combiner     = "OR"

  # Uptime check
  conditions {
    display_name = "uptime"
    condition_threshold {
      comparison = "COMPARISON_GT"
      duration   = "60s"
      filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" metric.label.\"check_id\"=\"${each.key}\""
      threshold_value = 1
      aggregations {
        alignment_period   = "1200s"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields = [
          "resource.*"
        ]
        per_series_aligner = "ALIGN_NEXT_OLDER"
      }
      trigger {
        count = 1
        percent = 0
      }
    }
  }

  # Request latency
  conditions {
    display_name = "request latency"
    condition_threshold {
      comparison = "COMPARISON_GT"
      duration   = "300s"
      filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/request_latency\" resource.type=\"uptime_url\" metric.label.\"check_id\"=\"${each.key}\""
      threshold_value = each.value["request_latency_threshold"]
      aggregations {
        alignment_period   = "300s"
        group_by_fields = []
        per_series_aligner = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MAX"
      }
      trigger {
        count = 1
        percent = 0
      }
    }
  }

  # Certificate expiration check, only if use_ssl == true
  dynamic "conditions" {
    for_each = each.value["use_ssl"] == true ? ["ok"] : []
    content {
      display_name = "certificate expiration"
      condition_threshold {
        comparison = "COMPARISON_LT"
        duration   = "43200s"
        filter     = "metric.type=\"monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires\" resource.type=\"uptime_url\" metric.label.\"check_id\"=\"${each.key}\""
        threshold_value = 15
        aggregations {
          alignment_period   = "3600s"
          cross_series_reducer = "REDUCE_MIN"
          group_by_fields = []
          per_series_aligner = "ALIGN_MEAN"
        }
        trigger {
          count = 1
          percent = 0
        }
      }
    }
  }

  // TODO: Implement alerts documentation
  //  documentation {
  //    content = "# check documentation\n- asdasd\n- asdasd"
  //    mime_type = "text/markdown"
  //  }
}

// TODO: Add email notifications
//resource "google_monitoring_notification_channel" "basic" {
//  display_name = "Test Notification Channel"
//  type = "email"
//  labels = {
//    email_address = "test@example.com"
//  }
//}