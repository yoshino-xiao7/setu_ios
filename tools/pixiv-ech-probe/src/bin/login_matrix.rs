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
    let h1 = std::env::var("LOGIN_HTTP1").is_ok();
    tls.alpn_protocols = if h1 { vec![b"http/1.1".to_vec()] } else { vec![b"h2".to_vec(), b"http/1.1".to_vec()] };
    let builder = reqwest::blocking::Client::builder().tls_backend_preconfigured(tls).no_proxy()
        .resolve("app-api.pixiv.net", "104.18.10.118:443".parse()?)
        .resolve("oauth.secure.pixiv.net", "104.18.10.118:443".parse()?)
        .resolve("accounts.pixiv.net", "104.18.10.118:443".parse()?)
        .timeout(Duration::from_secs(20)).redirect(reqwest::redirect::Policy::none())
        .user_agent("PixivAndroidApp/5.0.166 (Android 14; Pixel 8)");
    let builder = if let Ok(interface) = std::env::var("ECH_PROBE_INTERFACE") { builder.interface(&interface) } else { builder };
    let builder = if h1 { builder.http1_only() } else { builder };
    let client = builder.build()?;
    for url in ["https://app-api.pixiv.net/web/v1/login?code_challenge=0123456789012345678901234567890123456789012AA&code_challenge_method=S256&client=pixiv-android", "https://accounts.pixiv.net/login"] {
        let response = client.get(url).header("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148").send()?;
        println!("host={} status={} protocol={:?} location={:?}", response.url().host_str().unwrap(), response.status(),response.version(),response.headers().get("location"));
        let body=response.text()?;
        println!("blocked={} input={} body-length={}",body.contains("blocked") || body.contains("被阻止"),body.contains("<input"),body.len());
    }
    Ok(())
}
