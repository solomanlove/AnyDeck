//! 容器的有界读取与临时工作区；不使用归档中的路径写宿主机文件。
use std::{
    fs::{self, File},
    io::Read,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub type Archive = zip::ZipArchive<File>;
pub const MAX_FILE: u64 = 1024 * 1024 * 1024;
pub const MAX_MANIFEST: u64 = 16 * 1024 * 1024;
pub const MAX_RESOURCES: u64 = 128 * 1024 * 1024;

pub fn open(path: &Path) -> Result<Archive> {
    if path.metadata()?.len() > MAX_FILE {
        return Err("apkInputLimit".into());
    }
    let mut archive = zip::ZipArchive::new(File::open(path)?)?;
    if archive.len() > 100_000 {
        return Err("apkInputLimit".into());
    }
    let mut names = std::collections::HashSet::new();
    for i in 0..archive.len() {
        let entry = archive.by_index_raw(i)?;
        if !names.insert(entry.name().to_owned()) {
            return Err("apkInvalidArchive".into());
        }
        let limit = if entry.name().ends_with("resources.pb") {
            MAX_RESOURCES
        } else if entry.name().ends_with("AndroidManifest.xml")
            || entry.name().starts_with("META-INF/")
        {
            MAX_MANIFEST
        } else {
            MAX_FILE
        };
        if entry.size() > limit {
            return Err("apkInputLimit".into());
        }
    }
    Ok(archive)
}

pub fn read(archive: &mut Archive, name: &str, limit: u64) -> Result<Vec<u8>> {
    let entry = archive.by_name(name)?;
    if entry.size() > limit {
        return Err("apkInputLimit".into());
    }
    let mut data = Vec::new();
    entry.take(limit + 1).read_to_end(&mut data)?;
    if data.len() as u64 > limit {
        return Err("apkInputLimit".into());
    }
    Ok(data)
}

/// Dart 提供父目录并在进程被强杀后清理；CLI 正常退出时由 Drop 回收。
pub struct Workspace(PathBuf);
impl Workspace {
    pub fn new() -> Result<Self> {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::var_os("ANYDECK_APK_WORK_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        for _ in 0..100 {
            let path = root.join(format!(
                "anydeck-inspect-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            let mut builder = fs::DirBuilder::new();
            #[cfg(unix)]
            {
                use std::os::unix::fs::DirBuilderExt;
                builder.mode(0o700);
            }
            match builder.create(&path) {
                Ok(()) => return Ok(Self(path)),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e.into()),
            }
        }
        Err("apkParseFailed".into())
    }
    pub fn apk_path(&self) -> PathBuf {
        self.0.join("part.apk")
    }
}
impl Drop for Workspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
