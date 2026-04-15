project     = "myapp"
aws_region  = "us-east-1"
owner       = "platform-team"
cost_center = "eng-platform"

# Networking remote state — must match the backend bucket in networking-spoke/backend.tf.
networking_state_bucket = "your-terraform-state-bucket"
networking_state_region = "us-east-1"

# Aurora Serverless v2 (PostgreSQL)
db_name               = "appdb"
db_master_username    = "dbadmin"
aurora_engine_version = "16.4"
aurora_min_capacity   = 0.5 # Scale to 0.5 ACU when idle (~1 GB RAM)
aurora_max_capacity   = 4

backup_retention_period = 7

# Add application tier security group IDs to allow DB connections.
# aurora_allowed_sg_ids = ["sg-xxxxxxxxxxxxxxxxx"]

# RDS Proxy — recommended for Lambda/containerised workloads.
enable_rds_proxy = true

# Unique suffix to make the S3 bucket name globally unique (e.g. last 6 digits of account ID).
app_data_bucket_suffix = "abc123"
