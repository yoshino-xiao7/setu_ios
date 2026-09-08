use std::{io::{Read, Write}, net::TcpStream, sync::Arc, time::Duration};
use base64::Engine;
use rustls::{ClientConfig, ClientConnection, RootCertStore, StreamOwned};
use rustls::client::{EchConfig, EchMode, EchStatus};
use rustls::pki_types::{EchConfigListBytes, ServerName};

fn run(host: &str, path: &str, ech: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
    let roots = RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let config = EchConfig::new(EchConfigListBytes::from(ech.to_vec()), rustls::crypto::aws_lc_rs::hpke::ALL_SUPPORTED_SUITES)?;
    let mut tls = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider())).with_ech(EchMode::from(config))?
        .with_root_certificates(roots).with_no_client_auth();
    tls.alpn_protocols = vec![b"http/1.1".to_vec()];
    let socket = socket2::Socket::new(socket2::Domain::IPV4, socket2::Type::STREAM, Some(socket2::Protocol::TCP))?;
    if let Ok(interface) = std::env::var("ECH_PROBE_INTERFACE") {
        let name = std::ffi::CString::new(interface)?;
        let index = unsafe { libc::if_nametoindex(name.as_ptr()) };
        socket.bind_device_by_index_v4(Some(std::num::NonZeroU32::new(index).ok_or("Interface unavailable")?))?;
    }
    socket.connect_timeout(&"104.18.10.118:443".parse::<std::net::SocketAddr>()?.into(), Duration::from_secs(8))?;
    let socket: TcpStream = socket.into();
    socket.set_read_timeout(Some(Duration::from_secs(12)))?;
    socket.set_write_timeout(Some(Duration::from_secs(12)))?;
    let connection = ClientConnection::new(Arc::new(tls), ServerName::try_from(host.to_owned())?)?;
    let mut stream = StreamOwned::new(connection, socket);
    while stream.conn.is_handshaking() { stream.conn.complete_io(&mut stream.sock)?; }
    if !matches!(stream.conn.ech_status(), EchStatus::Accepted) { return Err("ECH was not accepted".into()); }
    stream.write_all(format!("GET {path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: Setu-ECH-Connectivity-Probe/1.0\r\nConnection: close\r\n\r\n").as_bytes())?;
    let mut response = [0u8; 2048];
    let length = stream.read(&mut response)?;
    let status = String::from_utf8_lossy(&response[..length]).lines().next().unwrap_or("").to_owned();
    println!("{host}: ECH=Accepted certificate=verified {status}");
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("Missing ECH config file")?;
    let bytes = base64::engine::general_purpose::STANDARD.decode(std::fs::read_to_string(path)?.trim())?;
    for (host, path) in [("app-api.pixiv.net", "/v1/illust/recommended"), ("oauth.secure.pixiv.net", "/auth/token"), ("accounts.pixiv.net", "/login")] {
        if let Err(error) = run(host, path, &bytes) { println!("{host}: FAILED {error}"); }
    }
    Ok(())
}
