locals {
  primary_region      = "us-east-2"
  instance_size_small = "t3.medium"
  instance_size_large = "z1d.3xlarge"
  instance_ssd_size = 140
  // The cron schedule for upsizing the server (in UTC)
  upsize_schedules = [
    "cron(00 22 ? * SUN *)", // This is 6:00pm EST on Sunday
    "cron(00 00 ? * THU *)"  // This is 8:00pm EST on Wednesday
  ]
  // The cron schedule for downsizing the server (in UTC)
  downsize_schedules = [
    "cron(20 02 ? * MON *)", // This is 10:20pm EST on Sunday
    "cron(20 03 ? * THU *)"  // This is 11:20pm EST on Wednesday
  ]
}
