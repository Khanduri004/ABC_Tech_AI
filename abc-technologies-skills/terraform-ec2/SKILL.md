---
name: terraform-ec2
description: Writes Terraform for a standalone AWS EC2 instance (e.g. a combined dev/CI box running Jenkins, Docker, Maven), consuming vpc_id/subnet_ids/security_group_ids from the terraform-vpc skill. Use whenever the user is provisioning an EC2 instance, sizing it for a CI/CD workload, or wiring a provisioning script via user_data.
---

Reference the `terraform-vpc` module's outputs for `subnet_ids` and `security_group_ids` — never hardcode a VPC/subnet ID.

## 1. AMI selection
Use a `data "aws_ami"` lookup for the latest image (e.g. Ubuntu 22.04/24.04 or Amazon Linux 2023) rather than a hardcoded, region-specific AMI ID that will go stale.

## 2. Sizing for the actual workload
Don't default to the free-tier instance type without checking what's running on the box. A combined dev/CI instance running Jenkins + Docker + Maven together typically needs more than 1GB RAM — size at least `t3.small`, and say so explicitly rather than silently picking the cheapest option, since undersizing here causes hard-to-diagnose OOM failures during builds.

## 3. Instance resource
```hcl
resource "aws_instance" "this" {
  ami                         = data.aws_ami.selected.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id            # from terraform-vpc
  vpc_security_group_ids      = var.security_group_ids   # from terraform-vpc
  key_name                    = var.key_name
  associate_public_ip_address = true                      # only if in a public subnet

  root_block_device {
    volume_size = var.root_volume_size
  }

  user_data = file("${path.module}/scripts/install_tools.sh")
}
```

## 4. user_data as an external file, not an inline heredoc
Reference the provisioning script via `file()` rather than inlining a large script as a string — it's easier to read, diff, and test independently of the Terraform config.

## 5. Provisioning script reliability
When writing/reviewing the referenced install script, check for two common failure modes on fresh instances:
- **GPG key rotation**: package repo signing keys (e.g. Jenkins's apt key) expire and get rotated — always fetch the current key path from the vendor's docs rather than a cached URL from memory.
- **JDK version conflicts**: if the CI tool (e.g. Jenkins) requires a newer JDK than the application target version, install both and pin the CI tool to the newer one via `update-alternatives` rather than forcing one JDK version for everything.

## 6. Security group scope
Only open the ports actually needed: 22 (SSH, ideally restricted to a known CIDR, not `0.0.0.0/0`), and whatever the CI tool's UI port is (e.g. 8080 for Jenkins).

## 7. Outputs and cost reminder
Output `public_ip` and `public_dns`. Remind the user this instance bills continuously — `terraform destroy` at the end of a work session if it's not needed running 24/7.
