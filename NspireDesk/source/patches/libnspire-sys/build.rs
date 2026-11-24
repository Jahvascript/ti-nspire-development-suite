use globwalk::DirEntry;

fn main() {
    println!("cargo:rerun-if-changed=libnspire/src/services/screen_rle.h");
    let files: Vec<_> = globwalk::GlobWalkerBuilder::from_patterns("libnspire/src", &["*.{c,cpp}"])
        .build().unwrap().into_iter().filter_map(Result::ok)
        .map(DirEntry::into_path)
        .inspect(|p| println!("cargo:rerun-if-changed={}", p.display())).collect();
    let mut base = cc::Build::new();
    if let Some(include) = std::env::var_os("DEP_USB_1.0_INCLUDE") { base.include(include); }
    base.include("libnspire/src").include("libnspire/src/services").include("libnspire/src/api");
    let mut c = base.clone();
    c.files(files.iter().filter(|p| p.extension().unwrap() == "c")).compile("nspire");
    base.cpp(true).std("c++14")
        .files(files.iter().filter(|p| p.extension().unwrap() == "cpp")).compile("nspire-cx2");
}
