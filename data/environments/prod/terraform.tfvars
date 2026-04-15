project     = "myapp"
aws_region  = "us-east-1"
owner       = "platform-team"
cost_center = "eng-platform"

networking_state_bucket = "your-terraform-state-bucket"
networking_state_region = "us-east-1"

db_name               = "appdb"
db_master_username    = "dbadmin"
aurora_engine_version = "16.4"
aurora_min_capacity   = 1
aurora_max_capacity   = 64

backup_retention_period = 14

# aurora_allowed_sg_ids = ["sg-xxxxxxxxxxxxxxxxx"]

enable_rds_proxy = true

app_data_bucket_suffix = "abc123"
