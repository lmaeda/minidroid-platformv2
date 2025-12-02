#!/bin/bash
# ==============================================================================
# SCRIPT: build_and_scan.sh
# CONTEXT: Runs inside the minidroid-platformv2 directory
# DESCRIPTION:
#   Automates the build process for the Minidroid platform, manages 3rd-party
#   dependencies, and executes a comprehensive security scanning pipeline.
#
# KEY FUNCTIONS:
#   1. Environment Setup: Creates output directories.
#   2. Artifact Processing: Downloads/Compiles binaries (FFmpeg, Toybox, Rclone, etc.).
#   3. Build: Compiles Java (Maven/Gradle), C/C++ (Conan), Python, Go, and Rust components.
#   4. SBOM Generation: Generates Software Bill of Materials using Syft, Scalibr, and Snyk.
#   5. SBOM Consolidation: Merges all SBOMs into a master record.
#   6. Security Scan: Scans the master SBOM for vulnerabilities using Snyk.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# ==============================================================================
# GLOBAL CONFIGURATION
# ==============================================================================
# Output directory structure matching Android build standards
OUT_DIR="out/target/product/generic"
SYSTEM_DIR="$OUT_DIR/system"
VENDOR_DIR="$OUT_DIR/vendor"
SBOM_DIR="$OUT_DIR/sboms"

# Dependency Versions (Centralized for easy maintenance)
FFMPEG_VERSION="5.1.4"
TOYBOX_VERSION="0.8.7"
RCLONE_VERSION="v1.66.0"

# Directories for external dependencies
EXTERNAL_LIB="external/lib"
EXTERNAL_SRC="external"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# Function: init_workspace
# Purpose:  Prepares the build environment by creating necessary directory trees.
#           Ensures that all target paths exist before copying artifacts.
# ------------------------------------------------------------------------------
function init_workspace() {
    echo "========================================================"
    echo "[Init] Initializing Workspace"
    echo "========================================================"
    echo "    - Creating output directories in: $OUT_DIR"
    
    mkdir -p "$SYSTEM_DIR"/bin
    mkdir -p "$SYSTEM_DIR"/framework
    mkdir -p "$SYSTEM_DIR"/app
    mkdir -p "$SYSTEM_DIR"/lib
    mkdir -p "$SYSTEM_DIR"/etc/manifests
    mkdir -p "$VENDOR_DIR"/bin
    mkdir -p "$VENDOR_DIR"/lib64
    mkdir -p "$SBOM_DIR"
    mkdir -p "$EXTERNAL_LIB"
}

# ------------------------------------------------------------------------------
# Function: process_ffmpeg
# Purpose:  Downloads and unpacks FFmpeg source code.
# Reason:   We need the unmanaged C++ source code extracted so that Snyk 
#           can perform a code-level scan for vulnerabilities.
# ------------------------------------------------------------------------------
function process_ffmpeg() {
    echo "[+] Processing Unmanaged C++ (FFmpeg ${FFMPEG_VERSION})..."
    local archive="ffmpeg-${FFMPEG_VERSION}.tar.gz"
    local url="https://ffmpeg.org/releases/${archive}"
    local dest="${EXTERNAL_LIB}/${archive}"
    local src_dir="${EXTERNAL_SRC}/ffmpeg_src"

    mkdir -p "$src_dir"

    # 1. Download if missing
    if [ ! -f "$dest" ]; then
        echo "    - Downloading source..."
        wget -q "$url" -O "$dest"
    fi

    # 2. Extract for scanning
    #    We strip the top-level directory to keep paths clean in the SBOM
    echo "    - Extracting to $src_dir..."
    tar -xzf "$dest" -C "$src_dir" --strip-components=1

    # 3. Simulate Build
    #    In a real scenario, we would run ./configure && make here.
    #    Touching a file simulates the binary creation for this demo.
    touch "$SYSTEM_DIR/bin/ffmpeg_custom"
    echo "    - Build artifact simulated at $SYSTEM_DIR/bin/ffmpeg_custom"
}

# ------------------------------------------------------------------------------
# Function: process_toybox
# Purpose:  Downloads and unpacks Toybox source code.
# Reason:   Similar to FFmpeg, unmanaged source code is required for 
#           accurate vulnerability scanning.
# ------------------------------------------------------------------------------
function process_toybox() {
    echo "[+] Processing Unmanaged C++ (Toybox ${TOYBOX_VERSION})..."
    local archive="toybox-${TOYBOX_VERSION}.tar.gz"
    local url="http://landley.net/toybox/downloads/${archive}"
    local dest="${EXTERNAL_LIB}/${archive}"
    local src_dir="${EXTERNAL_SRC}/toybox_src"

    mkdir -p "$src_dir"

    # 1. Download if missing
    if [ ! -f "$dest" ]; then
        echo "    - Downloading source..."
        wget -q "$url" -O "$dest"
    fi

    # 2. Extract for scanning
    echo "    - Extracting to $src_dir..."
    tar -xzf "$dest" -C "$src_dir" --strip-components=1

    # 3. Simulate Build
    touch "$SYSTEM_DIR/bin/toybox_custom"
    echo "    - Build artifact simulated at $SYSTEM_DIR/bin/toybox_custom"
}

# ------------------------------------------------------------------------------
# Function: process_rclone
# Purpose:  Downloads and installs the Rclone binary.
# Reason:   This is a pre-compiled binary integration. We unzip it to allow
#           scanners to see the binary and license files, then install it.
# ------------------------------------------------------------------------------
function process_rclone() {
    echo "[+] Processing Android Common (Rclone ${RCLONE_VERSION})..."
    local zip_name="rclone-${RCLONE_VERSION}-linux-amd64.zip"
    local folder_name="rclone-${RCLONE_VERSION}-linux-amd64"
    local url="https://github.com/rclone/rclone/releases/download/${RCLONE_VERSION}/${zip_name}"
    local dest="${EXTERNAL_LIB}/${zip_name}"
    local extract_base="${EXTERNAL_SRC}/rclone_bin_dir"

    # 1. Download if missing
    if [ ! -f "$dest" ]; then
        echo "    - Downloading binary archive..."
        wget -q "$url" -O "$dest"
    fi

    # 2. Extract
    #    Required for Snyk to analyze the binary signature if supported,
    #    and for general file visibility.
    echo "    - Extracting to $extract_base..."
    unzip -q -o "$dest" -d "$extract_base"

    # 3. Install
    local binary_src="${extract_base}/${folder_name}/rclone"
    local binary_local="${EXTERNAL_SRC}/rclone_bin"
    
    if [ -f "$binary_src" ]; then
        # Copy to external/rclone_bin (local reference)
        cp "$binary_src" "$binary_local"
        # Copy to system image (final artifact)
        cp "$binary_local" "$SYSTEM_DIR/bin/rclone_bin"
        echo "    - Installed rclone to system/bin"
    else
        echo "    ! ERROR: Rclone binary not found at $binary_src"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Function: build_conan_cpp
# Purpose:  Manages C/C++ dependencies via Conan and compiles native services.
# ------------------------------------------------------------------------------
function build_conan_cpp() {
    echo "[+] Building C/C++ Native Services (Conan)..."
    
    # Prerequisite Check
    if ! command -v gcc &> /dev/null; then
        echo "    ! GCC not found. Skipping compilation."
        touch "$SYSTEM_DIR/bin/native_service"
        return
    fi

    # Conan Dependency Management
    if command -v conan &> /dev/null; then
        echo "    - Resolving dependencies with Conan..."
        conan profile detect --force > /dev/null 2>&1 || true
        
        # Compatibility fix for newer Apple Clang versions in Conan default profile
        if [ -f "$HOME/.conan2/profiles/default" ]; then
             sed -i.bak 's/compiler.version=17/compiler.version=16/' "$HOME/.conan2/profiles/default"
        fi
        
        # Install dependencies defined in system/core/conanfile.txt
        (cd system/core && conan lock create conanfile.txt > /dev/null && conan install conanfile.txt > /dev/null)
    else
        echo "    ! Conan not found. Skipping dependency installation."
    fi
    
    # Compilation
    echo "    - Compiling native_service.c..."
    gcc system/core/native_service.c -o "$SYSTEM_DIR/bin/native_service"
    
    # Manifest Preservation (For SBOM correlation)
    echo "    - Archiving build manifests..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/native_service"
    [ -f "system/core/conanfile.txt" ] && cp system/core/conanfile.txt "$SYSTEM_DIR/etc/manifests/native_service/"
    [ -f "system/core/conan.lock" ] && cp system/core/conan.lock "$SYSTEM_DIR/etc/manifests/native_service/"
}

# ------------------------------------------------------------------------------
# Function: build_java_maven
# Purpose:  Builds the 'Launcher' application using Maven.
# ------------------------------------------------------------------------------
function build_java_maven() {
    echo "[+] Building Java App: Launcher (Maven)..."
    
    if ! command -v mvn &> /dev/null; then
        echo "    ! Maven not found. Skipping build."
        touch "$SYSTEM_DIR/app/Launcher.jar"
        return
    fi

    # Build
    echo "    - Running mvn package..."
    (cd packages/apps/Launcher && mvn package -q -DskipTests)
    
    # Install
    echo "    - Installing JAR..."
    cp packages/apps/Launcher/target/*.jar "$SYSTEM_DIR/app/Launcher.jar"
    
    # Manifest Preservation
    echo "    - Archiving pom.xml..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/Launcher"
    cp packages/apps/Launcher/pom.xml "$SYSTEM_DIR/etc/manifests/Launcher/pom.xml"
}

# ------------------------------------------------------------------------------
# Function: build_java_gradle
# Purpose:  Builds the 'Settings' application using Gradle.
# ------------------------------------------------------------------------------
function build_java_gradle() {
    echo "[+] Building Java App: Settings (Gradle)..."
    
    if ! command -v gradle &> /dev/null; then
        echo "    ! Gradle not found. Skipping build."
        touch "$SYSTEM_DIR/app/Settings.jar"
        return
    fi

    # Build
    echo "    - Running gradle build..."
    (cd packages/apps/Settings && gradle build --write-locks -q -x test)
    
    # Install
    echo "    - Installing JAR..."
    # '|| true' handles cases where build might fail or produce different outputs in demo env
    cp packages/apps/Settings/build/libs/*.jar "$SYSTEM_DIR/app/Settings.jar" || true
    
    # Manifest Preservation
    echo "    - Archiving build.gradle and locks..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/Settings"
    cp packages/apps/Settings/build.gradle "$SYSTEM_DIR/etc/manifests/Settings/build.gradle"
    [ -f packages/apps/Settings/gradle.lockfile ] && cp packages/apps/Settings/gradle.lockfile "$SYSTEM_DIR/etc/manifests/Settings/gradle.lockfile"
}

# ------------------------------------------------------------------------------
# Function: build_python
# Purpose:  Sets up a Python virtual environment and installs tooling.
# Reason:   Ensures reproducible Python tool execution and captures 
#           dependencies (requirements.txt) for the SBOM.
# ------------------------------------------------------------------------------
function build_python() {
    echo "[+] Building Python Tools..."
    
    # Environment Setup
    if [ ! -f "./.venv/bin/activate" ]; then
        echo "    - Creating virtual environment (.venv)..."
        python3 -m venv ./.venv
    fi
    
    echo "    - Activating virtual environment..."
    source "./.venv/bin/activate"
    
    # Install Dependencies
    echo "    - Installing requirements..."
    pip install -q -r system/tools/requirements.txt
    
    # Install Script
    echo "    - Installing sys_monitor.py..."
    cp system/tools/sys_monitor.py "$SYSTEM_DIR/bin/sys_monitor.py"
    
    # Manifest Preservation
    echo "    - Archiving requirements.txt..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/sys_monitor"
    cp system/tools/requirements.txt "$SYSTEM_DIR/etc/manifests/sys_monitor/requirements.txt"
}

# ------------------------------------------------------------------------------
# Function: build_go
# Purpose:  Compiles the 'netdaemon' microservice using Go.
# ------------------------------------------------------------------------------
function build_go() {
    echo "[+] Building Go Service: netdaemon..."
    
    if ! command -v go &> /dev/null; then
        echo "    ! Go not found. Skipping build."
        touch "$SYSTEM_DIR/bin/netdaemon"
        return
    fi

    echo "    - Compiling..."
    # Go mod tidy ensures go.sum is up to date for SBOM accuracy
    (cd vendor/services/netdaemon && go mod tidy && go build -o "../../../$SYSTEM_DIR/bin/netdaemon" .)
    
    # Manifest Preservation
    echo "    - Archiving go.mod/go.sum..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/netdaemon"
    cp vendor/services/netdaemon/go.mod "$SYSTEM_DIR/etc/manifests/netdaemon/"
    cp vendor/services/netdaemon/go.sum "$SYSTEM_DIR/etc/manifests/netdaemon/"
}

# ------------------------------------------------------------------------------
# Function: build_rust
# Purpose:  Compiles the 'secure_enclave' service using Rust/Cargo.
# ------------------------------------------------------------------------------
function build_rust() {
    echo "[+] Building Rust Service: secure_enclave..."
    
    if ! command -v cargo &> /dev/null; then
        echo "    ! Cargo not found. Skipping build."
        touch "$VENDOR_DIR/lib64/secure_enclave"
        return
    fi

    echo "    - Compiling (Release mode)..."
    (cd vendor/services/enclave && cargo build --release --quiet)
    
    # Install
    echo "    - Installing binary..."
    cp vendor/services/enclave/target/release/secure-enclave "$VENDOR_DIR/lib64/secure_enclave"
    
    # Manifest Preservation
    echo "    - Archiving Cargo.toml/lock..."
    mkdir -p "$SYSTEM_DIR/etc/manifests/secure_enclave"
    cp vendor/services/enclave/Cargo.toml "$SYSTEM_DIR/etc/manifests/secure_enclave/"
    cp vendor/services/enclave/Cargo.lock "$SYSTEM_DIR/etc/manifests/secure_enclave/"
}

# ------------------------------------------------------------------------------
# Function: generate_sboms
# Purpose:  Orchestrates the generation of SBOMs from various sources.
# Tools:
#   - Scalibr: Scans the final directory (binary fingerprinting).
#   - Syft: Scans the directory structure (filesystem analysis).
#   - Snyk: Scans unmanaged source code (C/C++).
# ------------------------------------------------------------------------------
function generate_sboms() {
    echo "========================================================"
    echo "[Phase 2] SBOM Generation"
    echo "========================================================"

    # 1. Scalibr (Google's SBOM Generator & Scanner)
    #    Scans the build output directory to identify packages.
    echo "[Security] Running Scalibr (OSV-Scanner)..."
    if command -v scalibr &> /dev/null; then
        scalibr --root="$OUT_DIR" -o cdx-json="$SBOM_DIR/scalibr.json"
        
        # Post-processing: Fix missing component types if necessary to ensure compliance
        if [ -f "$SBOM_DIR/scalibr.json" ]; then
             sed 's/"type": ""/"type": "application"/' "$SBOM_DIR/scalibr.json" > "$SBOM_DIR/scalibr.json.tmp" && \
             mv "$SBOM_DIR/scalibr.json.tmp" "$SBOM_DIR/scalibr.json"
             echo "    - Scalibr SBOM generated: $SBOM_DIR/scalibr.json"
        fi
    else
        echo "    ! Scalibr not found. Skipping."
    fi

    # 2. Syft (Anchore)
    #    Generates a file-system based SBOM of the output directory.
    echo "[Security] Running Syft..."
    if command -v syft &> /dev/null; then
        [ -f "$SBOM_DIR/syft-fs.json" ] && rm "$SBOM_DIR/syft-fs.json"
        syft dir:$OUT_DIR -o cyclonedx-json@1.6 > "$SBOM_DIR/syft-fs.json"
        echo "    - Syft SBOM generated: $SBOM_DIR/syft-fs.json"
    else
        echo "    ! Syft not found. Skipping."
    fi

    # 3. Snyk (Unmanaged C++)
    #    Scans the 'external' directory where we unpacked the C++ sources.
    echo "[Security] Running Snyk Unmanaged (C++)..."
    [ -f "$SBOM_DIR/snyk-unmanaged.json" ] && rm "$SBOM_DIR/snyk-unmanaged.json"
    
    if [ ! -z "$SNYK_TOKEN" ]; then
        # Use '|| true' to prevent build failure if vulnerability found (we want to report, not stop yet)
        snyk sbom --unmanaged --format=cyclonedx1.6+json ./external/ > "$SBOM_DIR/snyk-unmanaged.json" || true
        echo "    - Snyk Unmanaged SBOM generated: $SBOM_DIR/snyk-unmanaged.json"
    else
        echo "    ! SNYK_TOKEN not set. Creating placeholder SBOM."
        echo "{ \"bomFormat\": \"CycloneDX\", \"components\": [] }" > "$SBOM_DIR/snyk-unmanaged.json"
    fi
}

# ------------------------------------------------------------------------------
# Function: merge_sboms
# Purpose:  Consolidates individual tool SBOMs into a single Master SBOM.
# Tool:     CycloneDX CLI
# ------------------------------------------------------------------------------
function merge_sboms() {
    echo "========================================================"
    echo "[Phase 3] SBOM Consolidation"
    echo "========================================================"
    
    local master_sbom="$OUT_DIR/MASTER_PLATFORM_SBOM.json"
    local input_files=("$SBOM_DIR/syft-fs.json" "$SBOM_DIR/snyk-unmanaged.json" "$SBOM_DIR/scalibr.json")
    
    # Filter for files that actually exist
    local valid_inputs=()
    for f in "${input_files[@]}"; do
        [ -f "$f" ] && valid_inputs+=("$f")
    done

    if command -v cyclonedx &> /dev/null; then
        echo "[Merge] merging ${#valid_inputs[@]} SBOM files..."
        
        if [ ${#valid_inputs[@]} -gt 0 ]; then
            cyclonedx merge \
                --input-files "${valid_inputs[@]}" \
                --output-file "$master_sbom" \
                --output-format json \
                --output-version v1_6
            echo "[Success] MASTER SBOM created at: $master_sbom"
        else
            echo "[Error] No valid SBOMs to merge."
        fi
    else
        echo "[Merge] cyclonedx-cli not found. Falling back to simple concatenation (Demo mode)."
        # Fallback: Just take the Syft one if available, or the first valid one
        if [ ${#valid_inputs[@]} -gt 0 ]; then
             cp "${valid_inputs[0]}" "$master_sbom"
             echo "[Warning] Performed simple copy of ${valid_inputs[0]}. Install cyclonedx-cli for true merging."
        fi
    fi
}

# ------------------------------------------------------------------------------
# Function: scan_sbom
# Purpose:  Submits the Master SBOM to Snyk for vulnerability analysis.
# ------------------------------------------------------------------------------
function scan_sbom() {
    echo "========================================================"
    echo "[Phase 4] Security Scan & Monitor"
    echo "========================================================"
    
    local master_sbom="$OUT_DIR/MASTER_PLATFORM_SBOM.json"
    local report_file="$OUT_DIR/Snyk_SBOM_security_scan.json"
    
    if [ -f "$master_sbom" ]; then
        echo "    - Testing SBOM for vulnerabilities..."
        # 1. Test (Output JSON for machine reading)
        snyk sbom test --file="$master_sbom" --experimental --json > "$report_file" || true
        
        # 2. Test (Output to console for human reading)
        snyk sbom test --file="$master_sbom" --experimental || true

        # 3. Monitor (Upload to Snyk Dashboard)
        echo "    - Uploading snapshot to Snyk Monitor..."
        snyk sbom monitor \
            --org=c649b690-a033-490d-b6ca-b9e80bc1832b \
            --file="$master_sbom" \
            --experimental || true
    else
        echo "    ! Master SBOM not found. Skipping scan."
    fi
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================
function main() {
    init_workspace
    
    echo "========================================================"
    echo "[Phase 1] Build & Prepare Artifacts"
    echo "========================================================"
    
    # Process 3rd Party Binaries/Sources
    process_ffmpeg
    process_toybox
    process_rclone
    
    # Build System Components
    build_conan_cpp
    build_java_maven
    build_java_gradle
    build_python
    build_go
    build_rust
    
    # Security Pipeline
    generate_sboms
    merge_sboms
    scan_sbom
    
    echo "========================================================"
    echo "[Done] Build and Scan Complete."
    echo "========================================================"
}

# Execute Main
main