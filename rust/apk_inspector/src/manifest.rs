//! 将 Android Manifest 转成稳定的 UI 数据，未声明的状态保持缺失。
use roxmltree::{Document, Node};
use serde_json::{Value, json};
const ANDROID: &str = "http://schemas.android.com/apk/res/android";
fn attr<'a>(node: Node<'a, '_>, name: &str) -> Option<&'a str> {
    node.attribute((ANDROID, name))
        .or_else(|| node.attribute(name))
}

pub fn parse(xml: &str) -> Result<Value, Box<dyn std::error::Error>> {
    let doc = Document::parse(xml)?;
    let root = doc.root_element();
    let package = root.attribute("package").ok_or("apkInvalidFile")?;
    let app = root
        .children()
        .find(|n| n.has_tag_name("application"))
        .ok_or("apkInvalidFile")?;
    let sdk = root.children().find(|n| n.has_tag_name("uses-sdk"));
    let mut result = json!({
        "packageName": package, "label": attr(app, "label"),
        "versionName": attr(root, "versionName"), "versionCode": attr(root, "versionCode"),
        "minSdk": sdk.and_then(|n| attr(n,"minSdkVersion")),
        "targetSdk": sdk.and_then(|n| attr(n,"targetSdkVersion")),
        "maxSdk": sdk.and_then(|n| attr(n,"maxSdkVersion")),
        "debuggable": matches!(attr(app,"debuggable"), Some("true" | "1")),
        "split": root.attribute("split").is_some_and(|v| !v.is_empty()),
        "signatures": [],
    });
    for (key, tags) in [
        ("activities", vec!["activity", "activity-alias"]),
        ("services", vec!["service"]),
        ("receivers", vec!["receiver"]),
        ("providers", vec!["provider"]),
        (
            "permissions",
            vec!["uses-permission", "uses-permission-sdk-23", "permission"],
        ),
        ("metadata", vec!["meta-data"]),
    ] {
        let mut rows = vec![];
        for node in root
            .descendants()
            .filter(|n| tags.iter().any(|t| n.has_tag_name(*t)))
        {
            let mut row = serde_json::Map::new();
            for attribute in node.attributes() {
                row.insert(attribute.name().to_string(), json!(attribute.value()));
            }
            if let Some(name) = attr(node, "name") {
                let is_component =
                    matches!(key, "activities" | "services" | "receivers" | "providers");
                let full_name = if is_component && name.starts_with('.') {
                    format!("{package}{name}")
                } else if is_component && !name.contains('.') {
                    format!("{package}.{name}")
                } else {
                    name.to_string()
                };
                row.insert("name".into(), json!(full_name));
            }
            if key == "metadata" {
                row.insert(
                    "owner".into(),
                    json!(
                        node.parent_element()
                            .and_then(|n| attr(n, "name"))
                            .unwrap_or("application")
                    ),
                );
            }
            // exported 未显式声明时不伪造 true/false，保留 intent-filter 供详情查看。
            if node.children().any(|n| n.has_tag_name("intent-filter")) {
                row.insert("intentFilter".into(), json!(true));
            }
            rows.push(Value::Object(row));
        }
        result[key] = json!(rows);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn component_and_sdk_semantics() {
        let info = parse(r#"<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="example.app" android:versionCode="7"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="34"/><uses-permission android:name="android.permission.CAMERA"/><application android:label="中文"><activity android:name=".Main"/><activity-alias android:name="Alias" android:targetActivity=".Main"/><service android:name="Sync" android:exported="false"/></application></manifest>"#).unwrap();
        assert_eq!(info["activities"][0]["name"], "example.app.Main");
        assert!(info["activities"][0].get("exported").is_none());
        assert_eq!(info["targetSdk"], "34");
        assert!(info["maxSdk"].is_null());
        assert_eq!(info["services"][0]["exported"], "false");
        assert!(info["permissions"][0].get("granted").is_none());
    }
}
