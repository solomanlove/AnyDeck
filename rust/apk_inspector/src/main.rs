//! 隔离的只读 APK 检查器；stdout 为单个 JSON，所有资源在进程退出时释放。
mod manifest;
use apk_info::{AXML, Apk, Signature};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
use std::{fs::File, io::Read, path::Path};

fn inspect(path: &Path) -> Result<Value, Box<dyn std::error::Error>> {
    // 限制输入及被实际展开的条目，DEX/SO 只读目录索引，不展开内容。
    if path
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_lowercase()
        != "apk"
    {
        return Err("apkInvalidFile".into());
    }
    if path.metadata()?.len() > 1024 * 1024 * 1024 {
        return Err("apkInputLimit".into());
    }
    let mut zip = zip::ZipArchive::new(File::open(path)?)?;
    if zip.len() > 100_000 {
        return Err("apkInputLimit".into());
    }
    let mut libs = vec![];
    let mut dex = vec![];
    let mut abis = std::collections::BTreeSet::new();
    for i in 0..zip.len() {
        let entry = zip.by_index_raw(i)?;
        let name = entry.name();
        let limit = if name == "resources.arsc" {
            Some(128 * 1024 * 1024)
        } else if name == "AndroidManifest.xml" || name.starts_with("META-INF/") {
            Some(16 * 1024 * 1024)
        } else {
            None
        };
        if limit.is_some_and(|max| entry.size() > max) {
            return Err("apkInputLimit".into());
        }
        if name.starts_with("lib/") && name.ends_with(".so") {
            abis.insert(name.split('/').nth(1).unwrap_or("").to_string());
            libs.push(json!({"name": name, "size": entry.size()}));
        }
        if !name.contains('/') && name.ends_with(".dex") {
            dex.push(json!({"name": name, "size": entry.size()}));
        }
    }
    let mut warnings = vec![];
    let apk = match Apk::new(path) {
        Ok(value) => Some(value),
        Err(error) => {
            warnings.push(format!("apkResourceWarning: {error}"));
            None
        }
    };
    // ARSC 损坏时仍尝试读取 Manifest 和 ZIP 清单，保留可用信息。
    let xml = if let Some(apk) = &apk {
        apk.get_xml_string()
    } else {
        let mut data = vec![];
        zip.by_name("AndroidManifest.xml")?
            .take(16 * 1024 * 1024 + 1)
            .read_to_end(&mut data)?;
        AXML::new(&mut &data[..], None)?.get_xml_string()
    };
    let mut result = manifest::parse(&xml)?;
    if let Some(apk) = &apk {
        if let Some(label) = apk.get_application_label() {
            result["label"] = json!(label);
        }
        let mut icon_paths = vec![];
        if let Some(icon) = apk.get_application_icon() {
            icon_paths.push(icon.clone());
            // Android 常使用 adaptive XML，优先寻找同名位图变体。
            let stem = Path::new(&icon)
                .file_stem()
                .and_then(|v| v.to_str())
                .unwrap_or("");
            icon_paths.extend(
                apk.namelist()
                    .filter(|name| {
                        Path::new(name).file_stem().and_then(|v| v.to_str()) == Some(stem)
                            && [".png", ".webp", ".jpg"]
                                .iter()
                                .any(|ext| name.ends_with(ext))
                    })
                    .map(str::to_owned),
            );
        }
        for icon_path in icon_paths {
            if ![".png", ".webp", ".jpg"]
                .iter()
                .any(|ext| icon_path.ends_with(ext))
            {
                continue;
            }
            if let Ok(entry) = zip.by_name(&icon_path) {
                if entry.size() > 4 * 1024 * 1024 {
                    continue;
                }
                let mut bytes = vec![];
                if entry
                    .take(4 * 1024 * 1024 + 1)
                    .read_to_end(&mut bytes)
                    .is_ok()
                    && bytes.len() <= 4 * 1024 * 1024
                {
                    result["icon"] = json!(STANDARD.encode(bytes));
                    break;
                }
            }
        }
        match apk.get_signatures() {
            Ok(signatures) => {
                let mut rows = vec![];
                for signature in signatures {
                    let scheme = signature.name();
                    let certs = match signature {
                        Signature::V1(c)
                        | Signature::V2(c)
                        | Signature::V3(c)
                        | Signature::V31(c) => c,
                        _ => continue,
                    };
                    for cert in certs {
                        rows.push(json!({"name": format!("{} · {}", scheme, cert.subject),
                            "scheme": scheme, "subject": cert.subject, "issuer": cert.issuer,
                            "MD5": cert.md5_fingerprint, "SHA-1": cert.sha1_fingerprint,
                            "SHA-256": cert.sha256_fingerprint}));
                    }
                }
                result["signatures"] = json!(rows);
            }
            Err(error) => warnings.push(format!("apkSignatureWarning: {error}")),
        }
    }
    result["libs"] = json!(libs);
    result["dex"] = json!(dex);
    result["abis"] = json!(abis.into_iter().collect::<Vec<_>>().join(", "));
    result["warnings"] = json!(warnings);
    Ok(result)
}

fn main() {
    let result = std::panic::catch_unwind(|| {
        let path = std::env::args_os().nth(1).ok_or("apkInvalidFile")?;
        inspect(Path::new(&path))
    });
    match result {
        Ok(Ok(value)) => println!("{value}"),
        error => {
            let message = match error {
                Ok(Err(e)) => e.to_string(),
                _ => "apkParseFailed".to_owned(),
            };
            println!("{}", json!({"error": message}));
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn real_companion_apk() {
        let path =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/android/usage_companion.apk");
        let info = inspect(&path).unwrap();
        assert_eq!(info["packageName"], "com.adbmanage.companion");
        assert!(!info["permissions"].as_array().unwrap().is_empty());
        assert!(!info["dex"].as_array().unwrap().is_empty());
        let signatures = info["signatures"].as_array().unwrap();
        for scheme in ["v1", "v2", "v3"] {
            let certificate = signatures.iter().find(|s| s["scheme"] == scheme).unwrap();
            assert!(!certificate["SHA-256"].as_str().unwrap().is_empty());
            assert!(!certificate["MD5"].as_str().unwrap().is_empty());
        }
    }
    #[test]
    fn broken_resources_keep_manifest_and_multi_abi_dex_inventory() {
        use std::io::Write;
        let original =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/android/usage_companion.apk");
        let apk = Apk::new(original).unwrap();
        let path =
            std::env::temp_dir().join(format!("anydeck-test-{} 中文.apk", std::process::id()));
        let mut writer = zip::ZipWriter::new(File::create(&path).unwrap());
        let options = zip::write::SimpleFileOptions::default();
        for (name, bytes) in [
            (
                "AndroidManifest.xml",
                apk.read("AndroidManifest.xml").unwrap().0,
            ),
            ("resources.arsc", b"broken resources".to_vec()),
            ("classes.dex", b"dex1".to_vec()),
            ("classes2.dex", b"dex2".to_vec()),
            ("lib/arm64-v8a/libsample.so", b"arm64".to_vec()),
            ("lib/x86_64/libsample.so", b"x86_64".to_vec()),
        ] {
            writer.start_file(name, options).unwrap();
            writer.write_all(&bytes).unwrap();
        }
        writer.finish().unwrap();
        let result = inspect(&path);
        std::fs::remove_file(path).unwrap();
        let info = result.unwrap();
        assert_eq!(info["packageName"], "com.adbmanage.companion");
        assert_eq!(info["dex"].as_array().unwrap().len(), 2);
        assert_eq!(info["libs"].as_array().unwrap().len(), 2);
        assert_eq!(info["abis"], "arm64-v8a, x86_64");
        assert!(!info["warnings"].as_array().unwrap().is_empty());
    }
    #[test]
    fn rejects_invalid_file() {
        assert!(inspect(Path::new("Cargo.toml")).is_err());
    }
}
