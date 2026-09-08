//! A WebKit-scoped loopback CONNECT transport. Its temporary certificate is
//! pinned by that WebView only; upstream certificate verification is unchanged.
use super::*;
use std::{net::TcpListener, sync::atomic::{AtomicUsize, AtomicU32}};
use tokio::{io::{AsyncReadExt, AsyncWriteExt}, sync::{watch, Semaphore}};
use tokio_rustls::{TlsAcceptor, TlsConnector};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer, ServerName};

const HOSTS: [&str; 7] = ["app-api.pixiv.net", "accounts.pixiv.net", "oauth.secure.pixiv.net", "www.pixiv.net", "i.pximg.net", "s.pximg.net", "i-cf.pximg.net"];
static ACTIVE: AtomicUsize = AtomicUsize::new(0);

pub struct SetuPixivLogin {
    port: u16,
    certificate: Vec<u8>,
    stop: watch::Sender<bool>,
    stage: Arc<AtomicU32>,
}

fn connect_host(header: &[u8], expected_auth: &str) -> Result<String> {
    let header = std::str::from_utf8(header).map_err(|_| "INVALID_CONNECT")?;
    let mut lines = header.split("\r\n");
    let mut first = lines.next().unwrap_or("").split_whitespace();
    if first.next() != Some("CONNECT") { return Err("INVALID_CONNECT"); }
    let authority = first.next().ok_or("INVALID_CONNECT")?;
    if first.next() != Some("HTTP/1.1") || first.next().is_some() { return Err("INVALID_CONNECT"); }
    let host = authority.strip_suffix(":443").ok_or("INVALID_CONNECT")?;
    if !HOSTS.contains(&host) { return Err("INVALID_CONNECT"); }
    let mut authenticated = false;
    for line in lines {
        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("proxy-authorization") { authenticated = value.trim() == expected_auth; }
        }
    }
    if !authenticated { return Err("PROXY_AUTH_REQUIRED"); }
    Ok(host.to_owned())
}

fn upstream_config(host: &str) -> Result<ClientConfig> {
    let mut tls = if IMAGE_HOSTS.contains(&host) {
        let mut config = ClientConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider()))
            .with_safe_default_protocol_versions().map_err(|_| "TLS_UNAVAILABLE")?
            .with_root_certificates(roots()).with_no_client_auth();
        config.enable_sni = false;
        config
    } else {
        ech_client()?;
        let cached = ECH_CLIENT.get().ok_or("NETWORK_UNAVAILABLE")?.lock().map_err(|_| "NETWORK_UNAVAILABLE")?;
        (*cached.as_ref().ok_or("NETWORK_UNAVAILABLE")?.tls).clone()
    };
    tls.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(tls)
}

async fn forward(mut socket: tokio::net::TcpStream, acceptor: TlsAcceptor, auth: Arc<String>, stage: Arc<AtomicU32>) -> Result<()> {
    stage.store(1, Ordering::Relaxed);
    let mut header = Vec::new();
    // Read only the CONNECT header. Do not consume bytes from the subsequent TLS handshake.
    loop {
        let mut byte = [0];
        socket.read_exact(&mut byte).await.map_err(|_| "CONNECT_CLOSED")?;
        header.push(byte[0]);
        if header.ends_with(b"\r\n\r\n") { break; }
        if header.len() >= 8192 { return Err("INVALID_CONNECT"); }
    }
    let host = match connect_host(&header, &auth) {
        Ok(host) => host,
        Err("PROXY_AUTH_REQUIRED") => {
            let _ = socket.write_all(b"HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"Setu local login\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").await;
            return Err("PROXY_AUTH_REQUIRED");
        }
        Err(error) => return Err(error),
    };
    stage.store(2, Ordering::Relaxed);
    let server = ServerName::try_from(host.clone()).map_err(|_| "INVALID_CONNECT")?;
    let tls = tokio::task::spawn_blocking(move || upstream_config(&host)).await.map_err(|_| "NETWORK_UNAVAILABLE")??;
    stage.store(3, Ordering::Relaxed);
    let host = server.to_str().to_string();
    let addresses: &[&str] = if IMAGE_HOSTS.contains(&host.as_str()) { &["210.140.139.133:443"] }
        else { &["104.18.10.118:443", "104.18.11.118:443"] };
    let mut upstream = None;
    for address in addresses {
        if let Ok(Ok(stream)) = tokio::time::timeout(Duration::from_secs(8), tokio::net::TcpStream::connect(address)).await {
            upstream = Some(stream); break;
        }
    }
    let socket_upstream = upstream.ok_or("NETWORK_UNAVAILABLE")?;
    stage.store(4, Ordering::Relaxed);
    socket_upstream.set_nodelay(true).map_err(|_| "NETWORK_UNAVAILABLE")?;
    let mut remote = TlsConnector::from(Arc::new(tls)).connect(server, socket_upstream).await.map_err(|_| "TLS_UNAVAILABLE")?;
    stage.store(5, Ordering::Relaxed);
    socket.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n").await.map_err(|_| "CONNECT_CLOSED")?;
    let local = acceptor.accept(socket).await.map_err(|_| "LOCAL_TLS_UNAVAILABLE")?;
    stage.store(6, Ordering::Relaxed);
    // Limit each direction and lifetime. Login data is streamed and never persisted or logged.
    let (local_read, local_write) = tokio::io::split(local);
    let (remote_read, remote_write) = tokio::io::split(&mut remote);
    let outbound = async { let mut r = local_read.take(32 * 1024 * 1024); let mut w = remote_write; tokio::io::copy(&mut r, &mut w).await };
    let inbound = async { let mut r = remote_read.take(64 * 1024 * 1024); let mut w = local_write; tokio::io::copy(&mut r, &mut w).await };
    tokio::select! { _ = outbound => {}, _ = inbound => {} }
    Ok(())
}

fn start(password: &str) -> Result<SetuPixivLogin> {
    if password.len() < 32 || password.len() > 128 || !password.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') { return Err("INVALID_REQUEST"); }
    let cert = rcgen::generate_simple_self_signed(HOSTS.iter().map(|s| s.to_string()).collect::<Vec<_>>()).map_err(|_| "TLS_UNAVAILABLE")?;
    let certificate = cert.cert.der().to_vec();
    let key = PrivatePkcs8KeyDer::from(cert.signing_key.serialize_der());
    let mut server = rustls::ServerConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider()))
        .with_safe_default_protocol_versions().map_err(|_| "TLS_UNAVAILABLE")?.with_no_client_auth()
        .with_single_cert(vec![CertificateDer::from(certificate.clone())], key.into()).map_err(|_| "TLS_UNAVAILABLE")?;
    server.alpn_protocols = vec![b"http/1.1".to_vec()];
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|_| "NETWORK_UNAVAILABLE")?;
    let port = listener.local_addr().map_err(|_| "NETWORK_UNAVAILABLE")?.port();
    listener.set_nonblocking(true).map_err(|_| "NETWORK_UNAVAILABLE")?;
    let acceptor = TlsAcceptor::from(Arc::new(server));
    let auth = Arc::new(format!("Basic {}", base64::engine::general_purpose::STANDARD.encode(format!("setu:{password}"))));
    let (stop, mut stopped) = watch::channel(false);
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(|_| "NETWORK_UNAVAILABLE")?;
    let stage = Arc::new(AtomicU32::new(0));
    let worker_stage = stage.clone();
    std::thread::spawn(move || runtime.block_on(async move {
        let Ok(listener) = tokio::net::TcpListener::from_std(listener) else { return };
        let slots = Arc::new(Semaphore::new(8));
        let mut tasks = tokio::task::JoinSet::new();
        let expiry = tokio::time::sleep(Duration::from_secs(600)); tokio::pin!(expiry);
        loop {
            tokio::select! {
                _ = stopped.changed() => break,
                _ = &mut expiry => break,
                Some(_) = tasks.join_next(), if !tasks.is_empty() => {},
                accepted = listener.accept() => {
                    let Ok((socket, _)) = accepted else { break };
                    let Ok(permit) = slots.clone().try_acquire_owned() else { continue };
                    let acceptor = acceptor.clone(); let auth = auth.clone();
                    let stage = worker_stage.clone();
                    tasks.spawn(async move {
                        let _permit = permit;
                        let _ = tokio::time::timeout(Duration::from_secs(120), forward(socket, acceptor, auth, stage)).await;
                    });
                }
            }
        }
        tasks.abort_all();
    }));
    Ok(SetuPixivLogin { port, certificate, stop, stage })
}

#[no_mangle] pub unsafe extern "C" fn setu_pixiv_login_start(password: *const c_char) -> *mut SetuPixivLogin {
    if password.is_null() { return std::ptr::null_mut(); }
    if ACTIVE.fetch_add(1, Ordering::SeqCst) >= 2 { ACTIVE.fetch_sub(1, Ordering::SeqCst); return std::ptr::null_mut(); }
    match std::panic::catch_unwind(|| start(CStr::from_ptr(password).to_str().unwrap_or(""))) {
        Ok(Ok(session)) => Box::into_raw(Box::new(session)),
        _ => { ACTIVE.fetch_sub(1, Ordering::SeqCst); std::ptr::null_mut() }
    }
}
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_login_port(value: *const SetuPixivLogin) -> u16 { value.as_ref().map_or(0, |s| s.port) }
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_login_certificate(value: *const SetuPixivLogin) -> *const u8 { value.as_ref().map_or(std::ptr::null(), |s| s.certificate.as_ptr()) }
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_login_certificate_length(value: *const SetuPixivLogin) -> usize { value.as_ref().map_or(0, |s| s.certificate.len()) }
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_login_stage(value: *const SetuPixivLogin) -> u32 { value.as_ref().map_or(0, |s| s.stage.load(Ordering::Relaxed)) }
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_login_free(value: *mut SetuPixivLogin) {
    if !value.is_null() { let session = Box::from_raw(value); let _ = session.stop.send(true); ACTIVE.fetch_sub(1, Ordering::SeqCst); }
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn connect_requires_fixed_destination_and_session_credential() {
        let valid = b"CONNECT accounts.pixiv.net:443 HTTP/1.1\r\nProxy-Authorization: Basic test\r\n\r\n";
        assert_eq!(connect_host(valid, "Basic test").unwrap(), "accounts.pixiv.net");
        assert_eq!(connect_host(valid, "Basic other").unwrap_err(), "PROXY_AUTH_REQUIRED");
        for host in ["127.0.0.1", "evil.invalid", "accounts.pixiv.net.evil", "user@accounts.pixiv.net"] {
            let header = format!("CONNECT {host}:443 HTTP/1.1\r\nProxy-Authorization: Basic test\r\n\r\n");
            assert!(connect_host(header.as_bytes(), "Basic test").is_err());
        }
    }
    #[test] fn local_certificates_are_fresh_and_listeners_bind_loopback() {
        let first = start("12345678-1234-1234-1234-123456789012").unwrap();
        let second = start("12345678-1234-1234-1234-123456789013").unwrap();
        assert_ne!(first.certificate, second.certificate);
        assert_ne!(first.port, second.port);
        let _ = first.stop.send(true); let _ = second.stop.send(true);
    }
}
