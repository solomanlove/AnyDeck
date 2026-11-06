//! 用 AAPT2 产生的真实 AXML/Protobuf 样本覆盖容器与原有 APK 回归。
use crate::{archive::Workspace, inspect};
use serde_json::json;
use std::{
    fs::File,
    io::{Cursor, Write},
    path::Path,
};
const BASE: &[u8] = include_bytes!("../tests/fixtures/base-manifest.axml");
const SPLIT: &[u8] = include_bytes!("../tests/fixtures/split-manifest.axml");
const PROTO: &[u8] = include_bytes!("../tests/fixtures/base-manifest.pb");
const FEATURE: &[u8] = include_bytes!("../tests/fixtures/feature-manifest.pb");

fn zip_bytes(files: &[(&str, &[u8])]) -> Vec<u8> {
    let mut writer = zip::ZipWriter::new(Cursor::new(Vec::new()));
    for (name, bytes) in files {
        writer
            .start_file(
                *name,
                zip::write::SimpleFileOptions::default()
                    .compression_method(zip::CompressionMethod::Deflated),
            )
            .unwrap();
        writer.write_all(bytes).unwrap();
    }
    writer.finish().unwrap().into_inner()
}
fn write_zip(path: &Path, files: &[(&str, &[u8])]) {
    std::fs::write(path, zip_bytes(files)).unwrap();
}

#[test]
fn apks_selects_manifest_base_and_combines_feature_contents() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("APKS");
    let base = zip_bytes(&[("AndroidManifest.xml", BASE)]);
    let split = zip_bytes(&[
        ("AndroidManifest.xml", SPLIT),
        ("classes.dex", b"dex"),
        ("lib/arm64-v8a/libtest.so", b"so"),
    ]);
    write_zip(
        &path,
        &[
            ("aaa.apk", &split),
            ("zzz.APK", &base),
            ("toc.pb", b"metadata"),
        ],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["format"], "APKS");
    assert_eq!(info["primaryEntry"], "zzz.APK");
    assert_eq!(info["label"], "AnyDeck 包格式测试");
    assert_eq!(info["versionCode"], "9");
    assert_eq!(info["archiveEntries"].as_array().unwrap().len(), 2);
    assert_eq!(
        info["services"][0]["name"],
        "test.anydeck.package.FeatureService"
    );
    assert_eq!(info["services"][0]["source"], "aaa.apk");
    assert_eq!(info["dex"][0]["source"], "aaa.apk");
    assert_eq!(info["abis"], "arm64-v8a");
}
#[test]
fn xapk_retains_obb_and_untrusted_metadata_without_overwriting_apk() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("xapk");
    let base = zip_bytes(&[("AndroidManifest.xml", BASE)]);
    write_zip(
        &path,
        &[
            ("folder/base.apk", &base),
            ("Android/obb/test/main.9.obb", b"obb"),
            (
                "manifest.json",
                br#"{"package_name":"untrusted.package","version_name":"fake"}"#,
            ),
        ],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["format"], "XAPK");
    assert_eq!(info["packageName"], "test.anydeck.package");
    assert_eq!(info["versionName"], "1.9");
    assert_eq!(info["containerMetadata"].as_array().unwrap().len(), 2);
    assert!(
        info["archiveEntries"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["kind"] == "OBB")
    );
    assert!(
        info["warnings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|w| w.as_str().unwrap().contains("apkPackageMismatch"))
    );
}
#[test]
fn damaged_split_isolated_and_paths_never_extracted() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("apks");
    let base = zip_bytes(&[("AndroidManifest.xml", BASE)]);
    write_zip(
        &path,
        &[("../../outside.apk", &base), ("bad.apk", b"corrupt")],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["packageName"], "test.anydeck.package");
    assert_eq!(info["archiveEntries"].as_array().unwrap().len(), 2);
    assert!(!info["warnings"].as_array().unwrap().is_empty());
    assert!(
        !path
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("outside.apk")
            .exists()
    );
}
#[test]
fn mismatched_package_excluded_from_combined_details() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("apks");
    let base = zip_bytes(&[("AndroidManifest.xml", BASE)]);
    let other = std::fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/android/usage_companion.apk"),
    )
    .unwrap();
    write_zip(&path, &[("base.apk", &base), ("other.apk", &other)]);
    let info = inspect(&path).unwrap();
    assert_eq!(info["packageName"], "test.anydeck.package");
    assert_eq!(info["services"], json!([]));
    assert!(
        info["warnings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v.as_str().unwrap().contains("apkPackageMismatch"))
    );
}
#[test]
fn rejects_empty_container_missing_aab_base_and_excess_apks() {
    let work = Workspace::new().unwrap();
    let apks = work.apk_path().with_extension("apks");
    write_zip(&apks, &[("readme.txt", b"not an app")]);
    assert!(
        inspect(&apks)
            .unwrap_err()
            .to_string()
            .contains("apkEmptyArchive")
    );
    let aab = work.apk_path().with_extension("aab");
    write_zip(&aab, &[("feature/manifest/AndroidManifest.xml", FEATURE)]);
    assert!(
        inspect(&aab)
            .unwrap_err()
            .to_string()
            .contains("apkMissingBase")
    );
    let mut writer = zip::ZipWriter::new(File::create(&apks).unwrap());
    for i in 0..257 {
        writer
            .start_file(format!("{i}.apk"), zip::write::SimpleFileOptions::default())
            .unwrap();
    }
    writer.finish().unwrap();
    assert!(
        inspect(&apks)
            .unwrap_err()
            .to_string()
            .contains("apkInputLimit")
    );
}
#[test]
fn aab_reads_real_proto_manifest_features_and_inventory() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("aab");
    write_zip(
        &path,
        &[
            ("base/manifest/AndroidManifest.xml", PROTO),
            ("tools/manifest/AndroidManifest.xml", FEATURE),
            ("base/dex/classes.dex", b"dex1"),
            ("tools/dex/classes2.dex", b"dex2"),
            ("base/lib/arm64-v8a/libtest.so", b"so"),
            ("tools/lib/x86_64/libtest.so", b"so"),
            ("BundleConfig.pb", b""),
        ],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["format"], "AAB");
    assert_eq!(info["packageName"], "test.anydeck.package");
    assert_eq!(info["minSdk"], "23");
    assert_eq!(info["targetSdk"], "35");
    assert_eq!(info["debuggable"], true);
    assert_eq!(
        info["services"][0]["name"],
        "test.anydeck.package.FeatureService"
    );
    assert_eq!(info["modules"].as_array().unwrap().len(), 2);
    assert_eq!(info["dex"].as_array().unwrap().len(), 2);
    assert_eq!(info["abis"], "arm64-v8a, x86_64");
    assert_eq!(info["signatures"], json!([]));
}
#[test]
fn aab_resolves_compiled_resource_reference() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("aab");
    write_zip(
        &path,
        &[
            (
                "base/manifest/AndroidManifest.xml",
                include_bytes!("../tests/fixtures/resource-manifest.pb"),
            ),
            (
                "base/resources.pb",
                include_bytes!("../tests/fixtures/resources.pb"),
            ),
        ],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["label"], "AnyDeck 容器测试");
    assert_eq!(info["versionName"], "2.0");
    assert_eq!(info["targetSdk"], "36");
}
#[test]
fn aab_corrupt_feature_preserves_base_and_corrupt_base_fails() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("aab");
    write_zip(
        &path,
        &[
            ("base/manifest/AndroidManifest.xml", PROTO),
            ("tools/manifest/AndroidManifest.xml", b"bad protobuf"),
        ],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["packageName"], "test.anydeck.package");
    assert!(!info["warnings"].as_array().unwrap().is_empty());
    write_zip(
        &path,
        &[("base/manifest/AndroidManifest.xml", b"bad protobuf")],
    );
    assert!(inspect(&path).is_err());
}

/// 按公开 AAPT2 schema 编码资源包节点，覆盖无 application 的 asset pack。
fn proto_field(tag: u8, bytes: &[u8]) -> Vec<u8> {
    let mut output = vec![(tag << 3) | 2];
    let mut length = bytes.len();
    while length >= 128 {
        output.push((length as u8 & 127) | 128);
        length >>= 7;
    }
    output.push(length as u8);
    output.extend(bytes);
    output
}
fn proto_element(name: &str, attrs: &[(&str, &str, &str)], children: &[Vec<u8>]) -> Vec<u8> {
    let mut element = proto_field(3, name.as_bytes());
    if ["module", "delivery", "on-demand"].contains(&name) {
        element.extend(proto_field(
            2,
            b"http://schemas.android.com/apk/distribution",
        ));
    }
    for (uri, name, value) in attrs {
        let mut attr = proto_field(1, uri.as_bytes());
        attr.extend(proto_field(2, name.as_bytes()));
        attr.extend(proto_field(3, value.as_bytes()));
        element.extend(proto_field(4, &attr));
    }
    for child in children {
        element.extend(proto_field(5, child));
    }
    proto_field(1, &element)
}
#[test]
fn aab_asset_pack_without_application_preserves_delivery_metadata() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("aab");
    let dist = "http://schemas.android.com/apk/distribution";
    let delivery = proto_element("delivery", &[], &[proto_element("on-demand", &[], &[])]);
    let module = proto_element("module", &[(dist, "type", "asset-pack")], &[delivery]);
    let manifest = proto_element(
        "manifest",
        &[("", "package", "test.anydeck.package")],
        &[module],
    );
    write_zip(
        &path,
        &[
            ("base/manifest/AndroidManifest.xml", PROTO),
            ("assets_pack/manifest/AndroidManifest.xml", &manifest),
        ],
    );
    let info = inspect(&path).unwrap();
    let pack = info["modules"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["name"] == "assets_pack")
        .unwrap();
    assert_eq!(pack["kind"], "asset-pack");
    assert_eq!(pack["delivery"], "on-demand");
}
#[test]
fn aab_jar_certificate_is_distinct_from_apk_signing_scheme() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("aab");
    let original =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/android/usage_companion.apk");
    let mut original = crate::archive::open(&original).unwrap();
    let mut writer = zip::ZipWriter::new(File::create(&path).unwrap());
    writer
        .start_file(
            "base/manifest/AndroidManifest.xml",
            zip::write::SimpleFileOptions::default(),
        )
        .unwrap();
    writer.write_all(PROTO).unwrap();
    // 只测试读取证书，复制条目不声称测试包具有有效完整性签名。
    for i in 0..original.len() {
        let name = original.by_index_raw(i).unwrap().name().to_owned();
        if name.starts_with("META-INF/") && !name.ends_with('/') {
            writer
                .start_file(&name, zip::write::SimpleFileOptions::default())
                .unwrap();
            writer
                .write_all(&crate::archive::read(&mut original, &name, 1024 * 1024).unwrap())
                .unwrap();
        }
    }
    writer.finish().unwrap();
    let info = inspect(&path).unwrap();
    assert!(!info["signatures"].as_array().unwrap().is_empty());
    assert!(
        info["signatures"]
            .as_array()
            .unwrap()
            .iter()
            .all(|v| v["scheme"] == "JAR v1")
    );
}

#[test]
fn aab_bad_resource_table_retains_module_details() {
    let work = Workspace::new().unwrap();
    let path = work.apk_path().with_extension("aab");
    write_zip(
        &path,
        &[
            ("base/manifest/AndroidManifest.xml", PROTO),
            ("base/resources.pb", b"bad resource table"),
        ],
    );
    let info = inspect(&path).unwrap();
    assert_eq!(info["label"], "AnyDeck 包格式测试");
    assert!(
        info["warnings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v.as_str().unwrap().contains("apkResourceWarning"))
    );
}
