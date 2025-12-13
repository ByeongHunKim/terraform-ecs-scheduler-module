terraform {
  cloud {
    organization = "meiko_Org"

    workspaces {
      name = "ecs-scheduler-stg"
    }
  }
}
