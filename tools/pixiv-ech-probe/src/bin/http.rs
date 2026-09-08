use std::{sync::Arc, time::Duration};
use base64::Engine;
use rustls::{ClientConfig, RootCertStore};
use rustls::client::{EchConfig, EchMode};
use rustls::pki_types::EchConfigListBytes;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let ech = base64::engine::general_purpose::STANDARD.decode(std::fs::read_to_string(&std::env::var("ECH_PROBE_CONFIG")?)?.trim())?;
    let config = EchConfig::new(EchConfigListBytes::from(ech), rustls::crypto::aws_lc_rs::hpke::ALL_SUPPORTED_SUITES)?;
    let roots = RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let mut tls = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider())).with_ech(EchMode::from(config))?
        .with_root_certificates(roots).with_no_client_auth();
    tls.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    let builder = reqwest::blocking::Client::builder().tls_backend_preconfigured(tls).no_proxy()
        .resolve("app-api.pixiv.net", "104.18.10.118:443".parse()?)
        .resolve("oauth.secure.pixiv.net", "104.18.10.118:443".parse()?)
        .resolve("accounts.pixiv.net", "104.18.10.118:443".parse()?)
        .timeout(Duration::from_secs(20)).redirect(reqwest::redirect::Policy::none())
        .user_agent("PixivAndroidApp/5.0.166 (Android 14; Pixel 8)");
    let builder = if let Ok(interface) = std::env::var("ECH_PROBE_INTERFACE") { builder.interface(&interface) } else { builder };
    let client = builder.build()?;
    let headers: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&std::env::var("ECH_PROBE_HEADERS")?)?)?;
    for url in ["https://app-api.pixiv.net/v1/illust/recommended?filter=for_ios&include_ranking_label=true", "https://oauth.secure.pixiv.net/auth/token", "https://accounts.pixiv.net/login"] {
        let response = client.get(url).header("App-OS","android").header("App-OS-Version","14").header("App-Version","5.0.166")
            .header("X-Client-Time",headers["X-Client-Time"].as_str().unwrap()).header("X-Client-Hash",headers["X-Client-Hash"].as_str().unwrap()).send()?;
        println!("host={} status={} protocol={:?} server={:?} challenge={:?}", response.url().host_str().unwrap(), response.status(),response.version(),response.headers().get("server"),response.headers().get("cf-mitigated"));
        let body=response.text()?;
        println!("public unauthenticated body prefix: {}",body.chars().take(120).collect::<String>());
    }
    Ok(())
}
