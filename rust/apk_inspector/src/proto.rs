//! 有界解码 AAPT2 Resources.proto 的 XML 与字符串/文件资源。
//! 字段依据 AOSP tools/aapt2/Resources.proto；跳过未知字段以兼容新增元数据。
use crate::archive::Result;
use std::collections::HashMap;
const ANDROID: &str = "http://schemas.android.com/apk/res/android";
const DIST: &str = "http://schemas.android.com/apk/distribution";

#[derive(Clone, Copy)]
enum Data<'a> {
    Number(u64),
    Bytes(&'a [u8]),
}
struct Message<'a>(Vec<(u32, Data<'a>)>);

fn varint(data: &[u8], at: &mut usize) -> Result<u64> {
    let mut value = 0u64;
    for shift in (0..70).step_by(7) {
        let byte = *data.get(*at).ok_or("apkInvalidProto")?;
        *at += 1;
        if shift == 63 && byte > 1 {
            return Err("apkInvalidProto".into());
        }
        value |= ((byte & 0x7f) as u64) << shift;
        if byte < 0x80 {
            return Ok(value);
        }
    }
    Err("apkInvalidProto".into())
}
impl<'a> Message<'a> {
    fn decode(data: &'a [u8]) -> Result<Self> {
        let mut at = 0usize;
        let mut fields = vec![];
        while at < data.len() {
            if fields.len() >= 100_000 {
                return Err("apkInputLimit".into());
            }
            let key = varint(data, &mut at)?;
            let tag = u32::try_from(key >> 3)?;
            if tag == 0 {
                return Err("apkInvalidProto".into());
            }
            let value = match key & 7 {
                0 => Data::Number(varint(data, &mut at)?),
                wire @ (1 | 2 | 5) => {
                    let len = if wire == 2 {
                        usize::try_from(varint(data, &mut at)?)?
                    } else if wire == 1 {
                        8
                    } else {
                        4
                    };
                    let end = at.checked_add(len).ok_or("apkInvalidProto")?;
                    let bytes = data.get(at..end).ok_or("apkInvalidProto")?;
                    at = end;
                    if wire == 2 {
                        Data::Bytes(bytes)
                    } else {
                        Data::Number(
                            bytes
                                .iter()
                                .enumerate()
                                .fold(0u64, |n, (i, b)| n | ((*b as u64) << (i * 8))),
                        )
                    }
                }
                _ => return Err("apkInvalidProto".into()),
            };
            fields.push((tag, value));
        }
        Ok(Self(fields))
    }
    fn bytes(&self, tag: u32) -> Option<&'a [u8]> {
        self.all(tag).next()
    }
    fn all(&self, tag: u32) -> impl Iterator<Item = &'a [u8]> + '_ {
        self.0.iter().filter_map(move |(t, d)| match d {
            Data::Bytes(v) if *t == tag => Some(*v),
            _ => None,
        })
    }
    fn number(&self, tag: u32) -> Option<u64> {
        self.0.iter().find_map(|(t, d)| match d {
            Data::Number(v) if *t == tag => Some(*v),
            _ => None,
        })
    }
    fn text(&self, tag: u32) -> Result<&'a str> {
        Ok(std::str::from_utf8(self.bytes(tag).unwrap_or_default())?)
    }
    fn child(&self, tag: u32) -> Result<Message<'a>> {
        Self::decode(self.bytes(tag).unwrap_or_default())
    }
}

/// 资源名与资源 ID 都可寻址，循环引用最多追踪 16 次。
#[derive(Default)]
pub struct Resources(HashMap<String, String>);
impl Resources {
    pub fn decode(data: &[u8]) -> Result<Self> {
        let table = Message::decode(data)?;
        let mut result = Self::default();
        for package in table.all(2) {
            let package = Message::decode(package)?;
            let package_id = package.child(1)?.number(1).unwrap_or(0);
            let package_name = package.text(2)?;
            for kind in package.all(3) {
                let kind = Message::decode(kind)?;
                let type_id = kind.child(1)?.number(1).unwrap_or(0);
                let type_name = kind.text(2)?;
                for entry in kind.all(3) {
                    let entry = Message::decode(entry)?;
                    let id = (package_id << 24)
                        | (type_id << 16)
                        | entry.child(1)?.number(1).unwrap_or(0);
                    let mut selected = None;
                    for config in entry.all(6) {
                        let config = Message::decode(config)?;
                        if let Some(item) = config.child(2)?.bytes(4) {
                            let value = item_value(item)?;
                            if selected.is_none() || config.bytes(1).unwrap_or_default().is_empty()
                            {
                                selected = value;
                            }
                            if config.bytes(1).unwrap_or_default().is_empty() {
                                break;
                            }
                        }
                    }
                    if let Some(value) = selected {
                        let name = format!("{type_name}/{}", entry.text(2)?);
                        for key in [
                            format!("@{name}"),
                            format!("@{package_name}:{name}"),
                            format!("@0x{id:08x}"),
                        ] {
                            result.0.insert(key, value.clone());
                        }
                    }
                }
            }
        }
        Ok(result)
    }
    pub fn resolve(&self, value: &str) -> String {
        let mut current = value.to_owned();
        for _ in 0..16 {
            match self.0.get(&current) {
                Some(next) if *next != current => current = next.clone(),
                _ => break,
            }
        }
        current
    }
}

fn item_value(data: &[u8]) -> Result<Option<String>> {
    let item = Message::decode(data)?;
    for tag in [2, 3, 4, 5] {
        if let Some(value) = item.bytes(tag) {
            return Ok(Some(Message::decode(value)?.text(1)?.to_owned()));
        }
    }
    if let Some(reference) = item.bytes(1) {
        let reference = Message::decode(reference)?;
        let name = reference.text(3)?;
        return Ok(Some(if !name.is_empty() {
            format!("@{}", name.trim_start_matches('@'))
        } else {
            format!("@0x{:08x}", reference.number(2).unwrap_or(0))
        }));
    }
    if let Some(primitive) = item.bytes(7) {
        let primitive = Message::decode(primitive)?;
        if let Some(v) = primitive.number(8) {
            return Ok(Some((v != 0).to_string()));
        }
        if let Some(v) = primitive.number(6) {
            return Ok(Some((v as u32 as i32).to_string()));
        }
        if let Some(v) = primitive.number(7) {
            return Ok(Some(v.to_string()));
        }
        if let Some(v) = primitive.number(3) {
            return Ok(Some(f32::from_bits(v as u32).to_string()));
        }
    }
    Ok(None)
}
fn escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 256
        && name.chars().enumerate().all(|(i, c)| {
            c.is_ascii_alphabetic()
                || c == '_'
                || (i > 0 && (c.is_ascii_digit() || c == '-' || c == '.'))
        })
}

pub fn xml(data: &[u8], resources: &Resources) -> Result<String> {
    let mut output = String::new();
    xml_node(data, resources, 0, &mut output)?;
    Ok(output)
}
fn xml_node(data: &[u8], resources: &Resources, depth: usize, output: &mut String) -> Result<()> {
    if depth > 64 || output.len() > 32 * 1024 * 1024 {
        return Err("apkInputLimit".into());
    }
    let node = Message::decode(data)?;
    if let Some(element) = node.bytes(1) {
        let element = Message::decode(element)?;
        let name = element.text(3)?;
        if !valid_name(name) {
            return Err("apkInvalidProto".into());
        }
        let uri = element.text(2)?;
        let tag = if uri.is_empty() {
            name.to_owned()
        } else {
            format!("ns:{name}")
        };
        output.push_str(&format!(
            "<{tag} xmlns:android=\"{ANDROID}\" xmlns:dist=\"{DIST}\""
        ));
        if !uri.is_empty() {
            output.push_str(&format!(" xmlns:ns=\"{}\"", escape(uri)));
        }
        for (index, attr) in element.all(4).enumerate() {
            let attr = Message::decode(attr)?;
            let name = attr.text(2)?;
            if !valid_name(name) {
                return Err("apkInvalidProto".into());
            }
            let uri = attr.text(1)?;
            let prefix = if uri.is_empty() {
                String::new()
            } else if uri == ANDROID {
                "android:".into()
            } else if uri == DIST {
                "dist:".into()
            } else {
                output.push_str(&format!(" xmlns:a{index}=\"{}\"", escape(uri)));
                format!("a{index}:")
            };
            let raw = attr.text(3)?;
            let value = if !raw.is_empty() {
                raw.to_owned()
            } else {
                attr.bytes(6)
                    .map(item_value)
                    .transpose()?
                    .flatten()
                    .unwrap_or_default()
            };
            output.push_str(&format!(
                " {prefix}{name}=\"{}\"",
                escape(&resources.resolve(&value))
            ));
        }
        output.push('>');
        for child in element.all(5) {
            xml_node(child, resources, depth + 1, output)?;
        }
        output.push_str(&format!("</{tag}>"));
    } else if let Some(text) = node.bytes(2) {
        output.push_str(&escape(std::str::from_utf8(text)?));
    } else {
        return Err("apkInvalidProto".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recursion_and_resource_cycles_are_bounded() {
        let mut node = vec![10, 3, 26, 1, b'x'];
        for _ in 0..70 {
            let mut element = vec![26, 1, b'x', 42];
            let mut len = node.len();
            while len >= 128 {
                element.push((len as u8 & 127) | 128);
                len >>= 7;
            }
            element.push(len as u8);
            element.extend(node);
            node = vec![10];
            let mut len = element.len();
            while len >= 128 {
                node.push((len as u8 & 127) | 128);
                len >>= 7;
            }
            node.push(len as u8);
            node.extend(element);
        }
        assert!(
            xml(&node, &Resources::default())
                .unwrap_err()
                .to_string()
                .contains("apkInputLimit")
        );
        let resources = Resources(HashMap::from([
            ("@string/a".into(), "@string/b".into()),
            ("@string/b".into(), "@string/a".into()),
        ]));
        assert_eq!(resources.resolve("@string/a"), "@string/a");
    }
    #[test]
    fn rejects_truncated_lengths_and_overflow() {
        for bytes in [&[0x0a, 0xff][..], &[0; 2][..], &[0x80; 10][..]] {
            assert!(xml(bytes, &Resources::default()).is_err());
        }
    }
}
