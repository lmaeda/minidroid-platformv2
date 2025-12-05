# Minidroid Platform v2 - SCA & SBOM パイプライン POC

このプロジェクトは、Androidプラットフォームのビルドを模倣した、複雑な混合言語システムに対する包括的な **SCA（ソフトウェア構成分析）** パイプラインを実証する概念実証（POC）です。

Java、C/C++、Python、Go、Rustなどの多様なエコシステムにまたがる **SBOM（ソフトウェア部品表）** を生成、統合、およびスキャンするために、最新のセキュリティツールをどのように統合するかを示しています。

## 🚀 主な技術とツール

このパイプラインでは、完全な可視性とセキュリティを確保するために、以下の業界標準ツールを利用しています。

| ツール | 目的 |
|--------|------|
| **[Scalibr](https://github.com/google/osv-scalibr)** | **バイナリSCAエンジン**。Google製のSBOMジェネレーター。最終的なビルド成果物（バイナリ、JAR）をスキャンして、インストールされたパッケージを特定します。ソースコードが完全に透明でないコンパイル済み成果物の脆弱性を検出するために重要です。 |
| **[Syft](https://github.com/anchore/syft)** | Anchore社のCLIツール。ファイルシステム構造をスキャンして、ベースラインとなるSBOMを生成します。 |
| **[CycloneDX CLI](https://github.com/CycloneDX/cyclonedx-cli)** | 複数の部分的なSBOMを単一の「マスターSBOM」に統合するために使用されます。 |
| **[Snyk](https://snyk.io/)** | セキュリティプラットフォーム。非管理（Unmanaged）のC/C++ソースコードをスキャンし、最終的なマスターSBOMの脆弱性を分析します。 |

### なぜ Scalibr なのか？ (バイナリ SCA)
従来のソースコードスキャナーとは異なり、**Scalibr** はコンパイルされたバイナリを直接分析します。これは以下の点において不可欠です：
- **検証 (Verification):** 成果物がソースコードの主張通りの内容を含んでいるか確認します。
- **静的リンク (Static Linking):** ソーススキャナーでは見落とされがちな、コンパイル済みバイナリ内にバンドルされた依存関係を特定します。
- **バイナリブロブ (Binary Blobs):** ビルド中にソースコードが入手できない事前コンパイルされたバイナリ（本プロジェクトの `rclone` バイナリなど）内のコンポーネントを検出します。

## 📂 プロジェクト構造

このプロジェクトは、Androidのソースツリー構造をシミュレートしています。

- **`build_and_scan.sh`**: メインのオーケストレーションスクリプト。
- **`fix_spdx_sbom.py`**: SBOMのコンプライアンスを保証するヘルパースクリプト。
- **`external/`**: サードパーティのソースコード（FFmpeg, Toybox, Rclone）。
- **`packages/`**: MavenおよびGradleでビルドされるJavaアプリケーション（Launcher, Settings）。
- **`system/`**: コアシステムバイナリ（C/C++）、Pythonツール。
- **`vendor/`**: マイクロサービス（Go, Rust）。
- **`out/`**: ビルド出力ディレクトリ（成果物およびSBOM）。

## 🛠️ 前提条件

このパイプラインを完全に実行するには、以下のツールがインストールされている必要があります。

- **言語:** Java (JDK 11+), Python 3, Go, Rust (Cargo), GCC。
- **ビルドツール:** Maven, Gradle, Conan。
- **セキュリティツール:**
  - `snyk` (CLI、`snyk auth` で認証済みであること)
  - `syft`
  - `scalibr`
  - `cyclonedx` (CycloneDX CLI)

## ▶️ 使用方法

1.  **Snykの認証:**
    ```bash
    export SNYK_TOKEN=<あなたのAPIトークン>
    # または
    snyk auth
    ```

2.  **パイプラインの実行:**
    ```bash
    chmod +x build_and_scan.sh
    ./build_and_scan.sh
    ```

## ⚙️ 動作の仕組み（スクリプトの解説）

`build_and_scan.sh` スクリプトは、特定の機能ごとにモジュール化されています。

### 1. `init_workspace`
*   **コード:** `system/`、`vendor/`、`out/` ディレクトリ構造を作成します。
*   **目的:** ビルドを開始する前に、クリーンで標準的なAndroidライクな環境を確保します。

### 2. `process_ffmpeg` & `process_toybox`
*   **コード:** ソースのtarballをダウンロードし、`external/` に展開します。
*   **目的:** **非管理（Unmanaged）C++** コードを準備します。Snykはこれらのソースファイルを直接スキャン（`snyk sbom --unmanaged`）します。これは、適切にリンクされていない場合、バイナリスキャナーが見落とす可能性のある標準パッケージマニフェスト（`pom.xml`など）がないことが多いためです。

### 3. `process_rclone`
*   **コード:** 事前コンパイルされたバイナリをダウンロードし、`system/bin` に配置します。
*   **目的:** 「バイナリブロブ」やプロプライエタリなコンポーネントをシミュレートします。**Scalibr** はここで重要となり、ソースコードを必要とせずにファイルシステムから直接バイナリのフィンガープリントを取得して識別します。

### 4. `build_conan_cpp`
*   **コード:** Conanを使用してC++ライブラリをインストールし、Cバイナリ（`native_service`）をコンパイルします。
*   **目的:** 管理されたC++ビルドを実証します。SBOMツールが正確なバージョンを解析できるように、`conan.lock` を出力ディレクトリにアーカイブします。

### 5. `build_java_maven` & `build_java_gradle`
*   **コード:** Javaアプリをビルドし、`pom.xml` / `gradle.lockfile` を `system/etc/manifests` にコピーします。
*   **目的:** Syftが正確なコンポーネントリストを生成できるように、Javaの依存関係ツリーを確実に保持します。

### 6. `generate_sboms`
SBOM生成ツールを並行して実行します。
*   **Scalibr (バイナリSCA):** `out/` ディレクトリをスキャンします。OSV-Scanner技術を使用してバイナリのフィンガープリントを取得します。
*   **Syft (ファイルシステム):** ファイルレベルのメタデータを取得するためにディレクトリ構造をスキャンします。
*   **Snyk (ソース):** 生のC++ソースコード内の脆弱性を検出するために `external/` ディレクトリをスキャンします。

### 7. `merge_sboms`
*   **コード:** `cyclonedx merge` を使用して、Syft、Scalibr、SnykのSBOMを1つのマスターレコードに結合します。
*   **修正:** 変換されたSPDX JSONにパッチを適用するために `fix_spdx_sbom.py` を実行します。これにより、変換中に発生する可能性のある欠落フィールド（コンポーネント名など）を修正し、Snykの取り込みAPIへの厳密な準拠を保証します。

### 8. `scan_sbom`
*   **コード:** SBOMをSnykに送信します。
*   **アクション:**
    1.  `snyk sbom test` を実行して脆弱性を分析し、JSONレポート（`Snyk_SBOM_security_scan.json` および `.spdx.json`）を生成します。
    2.  `snyk sbom monitor` を実行してスナップショットをSnyk Web UIにアップロードし、継続的な監視を行います。

## 📊 出力

実行が成功したら、`out/target/product/generic/` ディレクトリを確認してください。

- **`MASTER_PLATFORM_SBOM.json`**: 統合されたSBOM (CycloneDX形式)。
- **`MASTER_PLATFORM_SBOM.spdx.json`**: Snyk準拠のSPDX SBOM。
- **`Snyk_SBOM_security_scan.json`**: CycloneDX SBOMの脆弱性レポート。
- **`Snyk_SBOM_security_scan.spdx.json`**: SPDX SBOMの脆弱性レポート。
