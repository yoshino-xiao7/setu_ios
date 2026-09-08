use std::{sync::Arc, time::Duration};
use rustls::{ClientConfig, RootCertStore};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let roots = RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let mut tls = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider())).with_safe_default_protocol_versions()?
        .with_root_certificates(roots).with_no_client_auth();
    tls.enable_sni = false; // Certificate chain and i.pximg.net hostname verification remain enabled.
    tls.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    let builder = reqwest::blocking::Client::builder().tls_backend_preconfigured(tls).no_proxy()
        .resolve("i.pximg.net", "210.140.139.133:443".parse()?).timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none());
    let builder = if let Ok(interface) = std::env::var("ECH_PROBE_INTERFACE") { builder.interface(&interface) } else { builder };
    let client = builder.build()?;
    let mut response = client.get("https://i.pximg.net/img-original/img/2025/05/15/00/08/58/130412285_p0.jpg")
        .header("Referer","https://www.pixiv.net/").send()?;
    println!("image status={} type={:?} certificate=verified",response.status(),response.headers().get("content-type"));
    let mut prefix=[0;4]; std::io::Read::read_exact(&mut response,&mut prefix)?;
    println!("image prefix={:x?}",prefix);
    Ok(())
}
