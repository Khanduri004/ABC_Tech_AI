#!/bin/bash
# install_tools.sh — installs JDK 17 + 21, Maven, Jenkins, Docker, AWS CLI, kubectl
# Target: Ubuntu 22.04 (runs via EC2 user_data, executes as root — no sudo needed in this file)
#
# ORDER MATTERS in this script — do not reorder without understanding why:
#   1. Java 17 + 21 BEFORE Jenkins — Jenkins requires Java 21 minimum (as of 2026) and
#      auto-starts itself during its own package install, using whatever `java` is
#      active at that moment. Installing Java second would cause Jenkins to crash-loop.
#   2. Docker BEFORE usermod — the docker group must exist before users can be added to it.
#
# LIVE DEPENDENCY WARNING: the Jenkins key URL and version below are correct as of
# 2026-09. Jenkins rotates its signing key periodically (the previous one expired
# 2026-03-26) — if this script starts failing with a GPG "NO_PUBKEY" error, check
# https://www.jenkins.io/doc/book/platform-information/debian-ubuntu-repositories/
# for the current key URL before assuming anything else is wrong.

set -euo pipefail

echo "=== Starting install_tools.sh ==="

apt-get update -y

# --- Java 17 (matches the app's Tomcat 10.1 runtime target) ---
echo "=== Installing Java 17 ==="
apt-get install -y openjdk-17-jdk

# --- Java 21 (Jenkins' own minimum required version) ---
# Must run BEFORE Jenkins installs — see order note above.
echo "=== Installing Java 21 (for Jenkins) ==="
apt-get install -y openjdk-21-jdk
update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java

# --- Maven ---
echo "=== Installing Maven ==="
apt-get install -y maven

# --- Jenkins ---
# Key/path current as of 2026-09 — see LIVE DEPENDENCY WARNING above if this fails.
echo "=== Installing Jenkins ==="
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2026.key | tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  "https://pkg.jenkins.io/debian binary/" | tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
systemctl enable jenkins
systemctl start jenkins

# --- Docker ---
echo "=== Installing Docker ==="
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

# Let both the default ubuntu user and jenkins run docker without sudo
usermod -aG docker ubuntu
usermod -aG docker jenkins
systemctl restart jenkins

# --- AWS CLI v2 ---
echo "=== Installing AWS CLI ==="
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt-get install -y unzip
unzip -o awscliv2.zip
./aws/install

# --- kubectl (matching EKS version 1.34) ---
echo "=== Installing kubectl ==="
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# --- kind (for local manifest testing before touching real EKS) ---
echo "=== Installing kind ==="
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind

# --- Verification summary — check this in cloud-init-output.log after boot ---
echo "=== Installation verification ==="
echo "Java (default): $(java -version 2>&1 | head -1)"
echo "Maven: $(mvn -version 2>&1 | head -1)"
echo "Jenkins service: $(systemctl is-active jenkins || echo 'NOT ACTIVE - CHECK LOGS')"
echo "Docker: $(docker --version 2>&1 || echo 'NOT INSTALLED - CHECK LOGS')"
echo "AWS CLI: $(aws --version 2>&1 || echo 'NOT INSTALLED - CHECK LOGS')"
echo "kubectl: $(kubectl version --client 2>&1 | head -1 || echo 'NOT INSTALLED - CHECK LOGS')"
echo "kind: $(kind --version 2>&1 || echo 'NOT INSTALLED - CHECK LOGS')"
echo "=== install_tools.sh complete ==="
