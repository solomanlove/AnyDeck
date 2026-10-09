//! macOS 实验性 UxPlay 协议核心构建；不构建上游 GStreamer renderer。
use std::{env, path::Path};

fn main() {
    println!("cargo:rerun-if-changed=native/uxplay_bridge.c");
    println!("cargo:rerun-if-changed=vendor/uxplay");
    if env::var_os("CARGO_FEATURE_AIRPLAY_UXPLAY").is_none() {
        return;
    }
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        panic!("airplay-uxplay currently supports macOS only");
    }
    // 支持显式 PKG_CONFIG_PATH，同时补齐两种 Homebrew 安装位置。
    let mut paths = env::var_os("PKG_CONFIG_PATH")
        .map(|v| env::split_paths(&v).collect::<Vec<_>>())
        .unwrap_or_default();
    for prefix in ["/opt/homebrew", "/usr/local"] {
        paths.push(format!("{prefix}/opt/openssl@3/lib/pkgconfig").into());
        paths.push(format!("{prefix}/opt/libplist/lib/pkgconfig").into());
    }
    env::set_var("PKG_CONFIG_PATH", env::join_paths(paths).unwrap());
    let crypto = pkg_config::Config::new()
        .cargo_metadata(false)
        .statik(true)
        .probe("libcrypto")
        .expect("Install OpenSSL 3 (brew install openssl@3)");
    let plist = pkg_config::Config::new()
        .cargo_metadata(false)
        .statik(true)
        .atleast_version("2.3")
        .probe("libplist-2.0")
        .expect("Install libplist >= 2.3 (brew install libplist)");
    let root = Path::new("vendor/uxplay/lib");
    let mut build = cc::Build::new();
    build
        .file("native/uxplay_bridge.c")
        .include(root)
        .include(root.join("playfair"))
        .include(root.join("llhttp"))
        .include(root.join("dns_sd"))
        .includes(&crypto.include_paths)
        .includes(&plist.include_paths)
        .define("PLIST_210", None)
        .define("PLIST_230", None)
        .define("OPENSSL_API_COMPAT", "0x10101000L")
        .flag_if_supported("-std=gnu11")
        .warnings(false);
    for dir in [root.to_path_buf(), root.join("playfair"), root.join("llhttp"), root.join("dns_sd")] {
        let mut files = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().is_some_and(|s| s == "c"))
            .collect::<Vec<_>>();
        files.sort();
        build.files(files);
    }
    build.compile("anydeck_uxplay");
    let out = std::path::PathBuf::from(env::var_os("OUT_DIR").unwrap());
    for lib in [&plist, &crypto] {
        for name in &lib.libs {
            let archive = lib.link_paths.iter().map(|p| p.join(format!("lib{name}.a")))
                .find(|p| p.is_file()).expect("Static dependency archive is required");
            // Darwin 优先搜索同名 dylib；使用私有归档名避免意外链接 Homebrew 动态库。
            let bundled = format!("anydeck_{name}");
            let target = out.join(format!("lib{bundled}.a"));
            // Homebrew 归档可能为只读；删除上轮复制件再写入，确保增量构建可重复。
            if target.exists() { std::fs::remove_file(&target).unwrap(); }
            std::fs::copy(&archive, &target).unwrap();
            println!("cargo:rerun-if-changed={}", archive.display());
            println!("cargo:rustc-link-lib=static={bundled}");
        }
    }
    println!("cargo:rustc-link-lib=dylib=z");
    println!("cargo:rustc-link-lib=framework=Security");
}
