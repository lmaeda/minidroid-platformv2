# Minidroid Platform v2 - SCA & SBOM Pipeline POC

This project is a Proof of Concept (POC) demonstrating a comprehensive **Software Composition Analysis (SCA)** pipeline for a complex, mixed-language system mimicking an Android platform build.

It showcases how to integrate modern security tools to generate, merge, and scan **Software Bill of Materials (SBOMs)** across various ecosystems (Java, C/C++, Python, Go, Rust).

## 🚀 Key Technologies & Tools

This pipeline utilizes a suite of industry-standard tools to ensure complete visibility and security:

| Tool | Purpose |
|------|---------|
| **[Scalibr](https://github.com/google/osv-scalibr)** | **Binary SCA Engine.** Google's SBOM generator. Scans the final build artifacts (binaries, JARs) to identify installed packages. Crucial for detecting vulnerabilities in compiled artifacts where source code might not be fully transparent. |
| **[Syft](https://github.com/anchore/syft)** | Anchore's CLI tool. Scans the filesystem structure to generate a baseline SBOM. |
| **[CycloneDX CLI](https://github.com/CycloneDX/cyclonedx-cli)** | Used to merge multiple partial SBOMs into a single "Master SBOM". |
| **[Snyk](https://snyk.io/)** | Security platform. Scans unmanaged C/C++ source code and analyzes the final Master SBOM for vulnerabilities. |

### Why Scalibr? (Binary SCA)
Unlike traditional source code scanners, **Scalibr** analyzes the compiled binaries directly. This is essential for:
- **Verification:** Confirming that the final artifacts actually contain what the source code claims.
- **Static Linking:** Identifying dependencies bundled inside compiled binaries that source scanners might miss.
- **Binary Blobs:** Detecting components in pre-compiled binaries (like the `rclone` binary in this project) where source code is unavailable during the build.

## 📂 Project Structure

The project simulates an Android source tree:

- **`build_and_scan.sh`**: The main orchestration script.
- **`fix_spdx_sbom.py`**: Helper script to ensure SBOM compliance.
- **`external/`**: 3rd-party source code (FFmpeg, Toybox, Rclone).
- **`packages/`**: Java applications (Launcher, Settings) built with Maven and Gradle.
- **`system/`**: Core system binaries (C/C++, Python tools).
- **`vendor/`**: Microservices (Go, Rust).
- **`out/`**: The build output directory (artifacts & SBOMs).

## 🛠️ Prerequisites

To run this pipeline fully, you need the following tools installed:

- **Languages:** Java (JDK 11+), Python 3, Go, Rust (Cargo), GCC.
- **Build Tools:** Maven, Gradle, Conan.
- **Security Tools:**
  - `snyk` (CLI authenticated with `snyk auth`)
  - `syft`
  - `scalibr`
  - `cyclonedx` (CycloneDX CLI)

## ▶️ Usage

1.  **Authenticate Snyk:**
    ```bash
    export SNYK_TOKEN=<your_api_token>
    # or
    snyk auth
    ```

2.  **Run the Pipeline:**
    ```bash
    chmod +x build_and_scan.sh
    ./build_and_scan.sh
    ```

## ⚙️ How It Works (Script Breakdown)

The `build_and_scan.sh` script is modularized into specific functions:

### 1. `init_workspace`
*   **Code:** Creates the `system/`, `vendor/`, and `out/` directory structures.
*   **Purpose:** Ensures a clean, standard Android-like environment before the build begins.

### 2. `process_ffmpeg` & `process_toybox`
*   **Code:** Downloads source tarballs and extracts them to `external/`.
*   **Purpose:** Prepares **Unmanaged C++** code. Snyk scans these source files directly (`snyk sbom --unmanaged`) because they often lack standard package manifests (like `pom.xml`) that binary scanners might miss if not properly linked.

### 3. `process_rclone`
*   **Code:** Downloads a pre-compiled binary and places it in `system/bin`.
*   **Purpose:** Simulates a "binary blob" or proprietary component. **Scalibr** is crucial here as it fingerprints this binary directly from the filesystem, identifying it without needing source code.

### 4. `build_conan_cpp`
*   **Code:** Uses Conan to install C++ libraries and compiles a C binary (`native_service`).
*   **Purpose:** Demonstrates managed C++ builds. It archives `conan.lock` to the output directory so the SBOM tools can parse exact versions.

### 5. `build_java_maven` & `build_java_gradle`
*   **Code:** Builds Java apps and copies `pom.xml`/`gradle.lockfile` to `system/etc/manifests`.
*   **Purpose:** Ensures Java dependency trees are preserved for Syft to generate accurate component lists.

### 6. `generate_sboms`
Runs the SBOM generation tools in parallel:
*   **Scalibr (Binary SCA):** Scans the `out/` directory. It uses OSV-Scanner technology to fingerprint binaries.
*   **Syft (Filesystem):** Scans the directory structure for file-level metadata.
*   **Snyk (Source):** Scans the `external/` directory to catch vulnerabilities in the raw C++ source code.

### 7. `merge_sboms`
*   **Code:** Uses `cyclonedx merge` to combine the Syft, Scalibr, and Snyk SBOMs into one master record.
*   **Fix:** Executes `fix_spdx_sbom.py` to patch the converted SPDX JSON. This ensures strict compliance with Snyk's ingestion API by fixing missing fields (e.g., component names) that can occur during conversion.

### 8. `scan_sbom`
*   **Code:** Submits the SBOMs to Snyk.
*   **Action:**
    1.  Runs `snyk sbom test` to analyze vulnerabilities and generate JSON reports (`Snyk_SBOM_security_scan.json` & `.spdx.json`).
    2.  Runs `snyk sbom monitor` to upload the snapshots to the Snyk web UI for continuous monitoring.

## 📊 Outputs

After a successful run, check the `out/target/product/generic/` directory:

- **`MASTER_PLATFORM_SBOM.json`**: The consolidated SBOM (CycloneDX format).
- **`MASTER_PLATFORM_SBOM.spdx.json`**: The Snyk-compliant SPDX SBOM.
- **`Snyk_SBOM_security_scan.json`**: Vulnerability report for the CycloneDX SBOM.
- **`Snyk_SBOM_security_scan.spdx.json`**: Vulnerability report for the SPDX SBOM.