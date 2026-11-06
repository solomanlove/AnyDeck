//! 应用签名与 AAB 上传证书只读展示，不执行完整性验签。
use crate::archive::Result;
use apk_info::{Signature, ZipEntry};
use serde_json::{Value, json};
use std::{fs::File, path::Path};

pub fn rows(signatures: Vec<Signature>, source: Option<&str>) -> Vec<Value> {
    let mut rows = vec![];
    for signature in signatures {
        let scheme = source
            .map(str::to_owned)
            .unwrap_or_else(|| signature.name());
        let certs = match signature {
            Signature::V1(c) | Signature::V2(c) | Signature::V3(c) | Signature::V31(c) => c,
            _ => continue,
        };
        for cert in certs {
            rows.push(json!({"name": format!("{} · {}", scheme, cert.subject),
                "scheme": scheme, "subject": cert.subject, "issuer": cert.issuer,
                "MD5": cert.md5_fingerprint, "SHA-1": cert.sha1_fingerprint,
                "SHA-256": cert.sha256_fingerprint}));
        }
    }
    rows
}

pub fn bundle(path: &Path) -> Result<Vec<Value>> {
    let zip = ZipEntry::from_reader(File::open(path)?)?;
    let has_cert = zip.namelist().any(|name| {
        let upper = name.to_ascii_uppercase();
        upper.starts_with("META-INF/")
            && [".RSA", ".DSA", ".EC"]
                .iter()
                .any(|ext| upper.ends_with(ext))
    });
    if !has_cert {
        return Ok(vec![]);
    }
    Ok(rows(vec![zip.get_signature_v1()?], Some("JAR v1")))
}
