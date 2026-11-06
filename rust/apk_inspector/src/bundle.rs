//! 原生读取 AAB 模块、Protobuf Manifest 和资源，开发工具只用于测试样本生成。
use crate::{
    archive::{self, MAX_MANIFEST, MAX_RESOURCES, Result},
    proto::{self, Resources},
};
use serde_json::{Value, json};
use std::{collections::BTreeSet, path::Path};

fn module_manifest(bytes: &[u8], resources: &Resources) -> Result<String> {
    if bytes.iter().copied().find(|b| !b.is_ascii_whitespace()) == Some(b'<') {
        return Ok(std::str::from_utf8(bytes)?.to_owned());
    }
    if bytes.starts_with(&[3, 0]) {
        return Ok(apk_info::AXML::new(&mut &bytes[..], None)?.get_xml_string());
    }
    proto::xml(bytes, resources)
}

pub fn inspect(path: &Path) -> Result<Value> {
    let mut zip = archive::open(path)?;
    if zip.by_name("base/manifest/AndroidManifest.xml").is_err() {
        return Err("apkMissingBase".into());
    }
    let mut modules = BTreeSet::new();
    for i in 0..zip.len() {
        let entry = zip.by_index_raw(i)?;
        if let Some(module) = entry.name().strip_suffix("/manifest/AndroidManifest.xml") {
            if !module.contains('/') && !module.is_empty() {
                modules.insert(module.to_owned());
            }
        }
    }
    if modules.len() > 256 {
        return Err("apkInputLimit".into());
    }
    let mut result = json!({});
    let mut module_rows = vec![];
    let mut warnings = vec![];
    let mut abis = BTreeSet::new();
    let mut libs = vec![];
    let mut dex = vec![];
    let mut total_resources = 0u64;
    // base 优先，动态功能与资源包随后合并，不将后者的缺失字段覆盖 base 概况。
    let ordered =
        std::iter::once("base".to_owned()).chain(modules.into_iter().filter(|m| m != "base"));
    for module in ordered {
        let resource_name = format!("{module}/resources.pb");
        let resources = if zip.by_name(&resource_name).is_ok() {
            total_resources += zip.by_name(&resource_name)?.size();
            if total_resources > MAX_RESOURCES {
                return Err("apkInputLimit".into());
            }
            match archive::read(&mut zip, &resource_name, MAX_RESOURCES)
                .and_then(|data| Resources::decode(&data))
            {
                Ok(table) => table,
                Err(error) => {
                    warnings.push(format!("apkResourceWarning: {resource_name}: {error}"));
                    Resources::default()
                }
            }
        } else {
            Resources::default()
        };
        let manifest_name = format!("{module}/manifest/AndroidManifest.xml");
        let parsed = archive::read(&mut zip, &manifest_name, MAX_MANIFEST)
            .and_then(|bytes| module_manifest(&bytes, &resources))
            .and_then(|xml| {
                roxmltree::Document::parse(&xml)?;
                Ok(xml)
            });
        let mut module_row = json!({"name": module});
        match parsed {
            Ok(xml) => {
                let doc = roxmltree::Document::parse(&xml)?;
                let root = doc.root_element();
                let declaration = root.descendants().find(|n| n.has_tag_name("module"));
                let kind = declaration
                    .and_then(|n| {
                        n.attribute(("http://schemas.android.com/apk/distribution", "type"))
                    })
                    .unwrap_or(if module == "base" { "base" } else { "feature" });
                let delivery = root
                    .descendants()
                    .find(|n| {
                        ["on-demand", "install-time", "fast-follow"]
                            .iter()
                            .any(|tag| n.has_tag_name(*tag))
                    })
                    .map(|n| n.tag_name().name())
                    .unwrap_or("");
                module_row["kind"] = json!(kind);
                module_row["delivery"] = json!(delivery);
                module_row["packageName"] = json!(root.attribute("package"));
                if module == "base" {
                    result = crate::manifest::parse(&xml)?;
                } else if let Ok(info) = crate::manifest::parse(&xml) {
                    if info["packageName"] == result["packageName"] {
                        crate::containers::merge(&mut result, &info, &module);
                    } else {
                        warnings.push(format!("apkPackageMismatch: {module}"));
                    }
                }
                if module == "base" {
                    if let Some(icon) = root
                        .children()
                        .find(|n| n.has_tag_name("application"))
                        .and_then(|n| {
                            n.attribute(("http://schemas.android.com/apk/res/android", "icon"))
                        })
                    {
                        let resolved = resources.resolve(icon);
                        let icon_name = format!("{module}/{resolved}");
                        let stem = Path::new(&resolved).file_stem();
                        let candidate = (0..zip.len()).find_map(|index| {
                            let entry = zip.by_index_raw(index).ok()?;
                            let name = entry.name();
                            let bitmap = [".png", ".webp", ".jpg"]
                                .iter()
                                .any(|ext| name.ends_with(ext));
                            (bitmap
                                && name.starts_with("base/res/")
                                && (name == icon_name
                                    || (stem.is_some() && Path::new(name).file_stem() == stem)))
                                .then(|| name.to_owned())
                        });
                        if let Some(candidate) = candidate {
                            if let Ok(bytes) = archive::read(&mut zip, &candidate, 4 * 1024 * 1024)
                            {
                                use base64::Engine;
                                result["icon"] =
                                    json!(base64::engine::general_purpose::STANDARD.encode(bytes));
                            }
                        }
                    }
                }
            }
            Err(error) if module == "base" => return Err(error),
            Err(error) => {
                warnings.push(format!("apkPartWarning: {module}: {error}"));
                module_row["error"] = json!(error.to_string());
            }
        }
        let mut size = 0u64;
        let mut module_dex = 0usize;
        let mut module_libs = 0usize;
        for i in 0..zip.len() {
            let entry = zip.by_index_raw(i)?;
            let name = entry.name();
            let Some(relative) = name.strip_prefix(&format!("{module}/")) else {
                continue;
            };
            size += entry.size();
            if relative.starts_with("lib/") && relative.ends_with(".so") {
                abis.insert(relative.split('/').nth(1).unwrap_or("").to_owned());
                libs.push(json!({"name": name, "size": entry.size(), "source": module}));
                module_libs += 1;
            }
            if relative.starts_with("dex/") && relative.ends_with(".dex") {
                dex.push(json!({"name": name, "size": entry.size(), "source": module}));
                module_dex += 1;
            }
        }
        module_row["size"] = json!(size);
        module_row["dexCount"] = json!(module_dex);
        module_row["libraryCount"] = json!(module_libs);
        module_rows.push(module_row);
    }
    match crate::signatures::bundle(path) {
        Ok(certs) => result["signatures"] = json!(certs),
        Err(error) => warnings.push(format!("apkSignatureWarning: {error}")),
    }
    result["modules"] = json!(module_rows);
    result["libs"] = json!(libs);
    result["dex"] = json!(dex);
    result["abis"] = json!(abis.into_iter().collect::<Vec<_>>().join(", "));
    result["warnings"] = json!(warnings);
    Ok(result)
}
