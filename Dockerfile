# ==============================================================================
# Dockerfile for Minidroid Platform v2
# Description: Defines the build environment with all necessary tools and languages.
# ==============================================================================

# Base image with build tools
FROM ubuntu:22.04

# Metadata
LABEL maintainer="Minidroid Platform Team"
LABEL description="Build environment for Minidroid Platform v2"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Environment variables for tools
ENV GRADLE_VERSION=8.5
ENV GRADLE_HOME=/opt/gradle
# Add Gradle and Go binaries to PATH
ENV PATH=$PATH:$GRADLE_HOME/bin:/root/go/bin

# ------------------------------------------------------------------------------
# 1. System Dependencies & Languages
# ------------------------------------------------------------------------------
# Install:
# - Build essentials (gcc, make, etc.)
# - Common utilities (curl, wget, git, zip/unzip)
# - Java (OpenJDK 17) for Launcher app
# - Maven for Launcher app
# - Python 3 & Pip for scripting and Conan
# - Go (Golang) for microservices
# - Rust (Cargo) for secure enclave
# ------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    unzip \
    zip \
    openjdk-17-jdk \
    maven \
    python3 \
    python3-pip \
    python3-venv \
    golang-go \
    cargo \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------
# 2. Build Tools Configuration
# ------------------------------------------------------------------------------

# Install Gradle (Manual install required for Java 17 compatibility, apt version is too old)
RUN wget -q https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip \
    && unzip -q gradle-${GRADLE_VERSION}-bin.zip -d /opt \
    && ln -s /opt/gradle-${GRADLE_VERSION} /opt/gradle \
    && rm gradle-${GRADLE_VERSION}-bin.zip

# Install Conan (C++ Package Manager) via Pip
RUN pip3 install --no-cache-dir conan

# ------------------------------------------------------------------------------
# 3. Security & Compliance Tools
# ------------------------------------------------------------------------------

# Install Syft (SBOM Generator)
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Install Scalibr (Vulnerability Scanner)
# Replaces osv-scanner. Installed via Go.
RUN GOBIN=/usr/local/bin go install github.com/google/osv-scalibr/binary/scalibr@latest

# Install Snyk CLI (Security Scanning)
# Using standalone binary
RUN curl -L https://github.com/snyk/snyk/releases/latest/download/snyk-linux -o /usr/local/bin/snyk \
    && chmod +x /usr/local/bin/snyk

# Install CycloneDX CLI (For Merging SBOMs)
RUN wget -q https://github.com/CycloneDX/cyclonedx-cli/releases/download/v0.25.0/cyclonedx-linux-x64 \
    -O /usr/local/bin/cyclonedx && \
    chmod +x /usr/local/bin/cyclonedx

# ------------------------------------------------------------------------------
# 4. Runtime Configuration
# ------------------------------------------------------------------------------

# Set working directory
WORKDIR /app

# Default command
CMD ["bash"]
