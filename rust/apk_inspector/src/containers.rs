//! APKS/XAPK 逐个分析内含 APK，保留来源，OBB 只读目录信息。
use crate::archive::{self, MAX_FILE, Result, Workspace};
use serde_json::{Value, json};
use std::{collections::BTreeSet, path::Path};

const DETAILS: [&str; 9] = [
    "activities",
    "services",
    "receivers",
    "providers",
    "permissions",
    "metadata",
    "dex",
    "libs",
    "signatures",
];

/// 合并同包、同版本的内容；组件按语义去重，文件和证书保留各自来源。
pub fn merge(result: &mut Value, other: &Value, source: &str) {
    for key in DETAILS {
        let current = result
            .as_object_mut()
            .unwrap()
            .entry(key)
            .or_insert(json!([]))
            .as_array_mut()
            .unwrap();
        for row in other[key].as_array().into_iter().flatten() {
            if !matches!(key, "libs" | "dex" | "signatures")
                && current.iter().any(|existing| {
                    let mut existing = existing.clone();
                    existing.as_object_mut().unwrap().remove("source");
                    existing == *row
                })
            {
                continue;
            }
            let mut row = row.clone();
            row["source"] = json!(source);
            current.push(row);
        }
    }
}

pub fn inspect(path: &Path) -> Result<Value> {
    let mut zip = archive::open(path)?;
    let mut apks = vec![];
    let mut entries = vec![];
    let mut total = 0u64;
    for i in 0..zip.len() {
        let entry = zip.by_index_raw(i)?;
        let name = entry.name().to_owned();
        let lower = name.to_ascii_lowercase();
        if lower.ends_with(".apk") && !entry.is_dir() {
            total = total.checked_add(entry.size()).ok_or("apkInputLimit")?;
            if total > MAX_FILE || apks.len() >= 256 {
                return Err("apkInputLimit".into());
            }
            apks.push((name, entry.size()));
        } else if lower.ends_with(".obb") {
            entries.push(json!({"name": name, "size": entry.size(), "kind": "OBB"}));
        }
    }
    if apks.is_empty() {
        return Err("apkEmptyArchive".into());
    }
    apks.sort_by(|a, b| a.0.cmp(&b.0));
    let work = Workspace::new()?;
    let mut parsed = vec![];
    let mut warnings = vec![];
    for (name, size) in apks {
        let info = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            // 只写固定文件名；释放解压字节后再解析，内存不随分包数量累计。
            {
                let bytes = archive::read(&mut zip, &name, MAX_FILE)?;
                std::fs::write(work.apk_path(), bytes)?;
            }
            crate::inspect_apk(&work.apk_path())
        }));
        match info {
            Ok(Ok(info)) => {
                entries.push(json!({"name": name, "size": size, "kind": "APK", "packageName": info["packageName"],
                    "versionCode": info["versionCode"], "split": info["split"], "splitName": info["splitName"], "abis": info["abis"]}));
                parsed.push((name, info));
            }
            error => {
                let message = match error {
                    Ok(Err(e)) => e.to_string(),
                    _ => "apkParseFailed".to_owned(),
                };
                warnings.push(format!("apkPartWarning: {name}: {message}"));
                entries.push(json!({"name": name, "size": size, "kind": "APK", "error": message}));
            }
        }
    }
    if parsed.is_empty() {
        return Err("apkInvalidArchive".into());
    }
    // 名称只决定候选顺序，最终仍要求 Manifest 声明为 base，避免误用 config split。
    let primary = parsed
        .iter()
        .enumerate()
        .min_by_key(|(_, (name, info))| {
            let name = name.to_ascii_lowercase();
            let rank = if name.ends_with("base-master.apk") {
                0
            } else if name.ends_with("base.apk") {
                1
            } else if name.ends_with("universal.apk") {
                2
            } else {
                3
            };
            (info["split"] == true, rank)
        })
        .unwrap()
        .0;
    let mut result = parsed[primary].1.clone();
    result["primaryEntry"] = json!(parsed[primary].0);
    let package = result["packageName"].clone();
    let version = result["versionCode"].clone();
    let mut abis = BTreeSet::new();
    for key in DETAILS {
        result[key] = json!([]);
    }
    if parsed[primary].1["split"] == true {
        warnings.push("apkMissingBase".to_owned());
    }
    for (name, info) in &parsed {
        if info["packageName"] != package || info["versionCode"] != version {
            warnings.push(format!("apkPackageMismatch: {name}"));
            continue;
        }
        if let Some(value) = info["abis"].as_str() {
            abis.extend(
                value
                    .split(", ")
                    .filter(|v| !v.is_empty())
                    .map(str::to_owned),
            );
        }
        for warning in info["warnings"].as_array().into_iter().flatten() {
            if let Some(warning) = warning.as_str() {
                warnings.push(format!("{name}: {warning}"));
            }
        }
        merge(&mut result, info, name);
    }
    // manifest.json 仅作容器信息展示，不能覆盖真实 APK 包名和版本。
    if zip.by_name("manifest.json").is_ok() {
        match archive::read(&mut zip, "manifest.json", 1024 * 1024)
            .and_then(|bytes| Ok(serde_json::from_slice::<Value>(&bytes)?))
        {
            Ok(metadata) => {
                if let Some(name) = metadata["package_name"].as_str() {
                    if package.as_str() != Some(name) {
                        warnings.push("apkPackageMismatch: manifest.json".to_owned());
                    }
                }
                if let Some(values) = metadata.as_object() {
                    result["containerMetadata"] = json!(
                        values
                            .iter()
                            .map(|(k, v)| json!({"name": k, "value": v}))
                            .collect::<Vec<_>>()
                    );
                }
            }
            Err(error) => warnings.push(format!("apkPartWarning: manifest.json: {error}")),
        }
    }
    result["archiveEntries"] = json!(entries);
    result["abis"] = json!(abis.into_iter().collect::<Vec<_>>().join(", "));
    result["warnings"] = json!(warnings);
    Ok(result)
}
