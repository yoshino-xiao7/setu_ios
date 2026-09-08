//! Bounded native Pixiv transport. No cookies, persistent credentials or request logging.
use std::{collections::HashMap, ffi::{CStr, CString, c_char}, io::Read, sync::{Arc, Mutex, OnceLock, atomic::{AtomicBool, Ordering}}, time::{Duration, Instant}};
use base64::Engine;
use reqwest::{blocking::Client, Url};
use rustls::{ClientConfig, RootCertStore, client::{EchConfig, EchMode}, pki_types::EchConfigListBytes};
use serde::Deserialize;

type Result<T> = std::result::Result<T, &'static str>;
mod login;
mod image;
const API_HOSTS: [&str; 3] = ["app-api.pixiv.net", "oauth.secure.pixiv.net", "accounts.pixiv.net"];
const IMAGE_HOSTS: [&str; 4] = ["i.pximg.net", "s.pximg.net", "i-cf.pximg.net", "i.pixiv.re"];

#[derive(Deserialize)]
struct Request {
    url: String,
    method: String,
    #[serde(default)] headers: HashMap<String, String>,
    body: Option<String>,
    max_bytes: usize,
    #[serde(default)] public_image_probe: u8,
    #[serde(default)] image_mirror_host: Option<String>,
}
struct CachedClient { client: Client, expires: Instant, tls: Arc<ClientConfig> }
static ECH_CLIENT: OnceLock<Mutex<Option<CachedClient>>> = OnceLock::new();
static RHTTP_API: OnceLock<setu_rhttp_native::api::client::RequestClient> = OnceLock::new();
static RHTTP_RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn roots() -> RootCertStore { RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned()) }
fn base() -> reqwest::blocking::ClientBuilder {
    Client::builder().no_proxy().connect_timeout(Duration::from_secs(8)).timeout(Duration::from_secs(35))
        .redirect(reqwest::redirect::Policy::none()).pool_max_idle_per_host(4)
}
fn target(raw: &str) -> Result<Url> {
    let url=Url::parse(raw).map_err(|_| "INVALID_DESTINATION")?;
    if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() || url.fragment().is_some()
        || url.port_or_known_default() != Some(443)
        || !url.host_str().is_some_and(|h| API_HOSTS.contains(&h) || IMAGE_HOSTS.contains(&h)) { return Err("INVALID_DESTINATION"); }
    Ok(url)
}
fn parse_ech(payload: &serde_json::Value) -> Result<(Vec<u8>, u64)> {
    for answer in payload["Answer"].as_array().ok_or("ECH_DNS_UNAVAILABLE")? {
        if answer["type"].as_u64() != Some(65) { continue; }
        for part in answer["data"].as_str().unwrap_or("").split_whitespace() {
            if let Some(encoded) = part.strip_prefix("ech=") {
                let data=base64::engine::general_purpose::STANDARD.decode(encoded.trim_matches('"')).map_err(|_| "ECH_CONFIG_INVALID")?;
                if data.is_empty() || data.len()>65535 { return Err("ECH_CONFIG_INVALID"); }
                return Ok((data, answer["TTL"].as_u64().unwrap_or(15).clamp(1,300)));
            }
        }
    }
    Err("ECH_CONFIG_UNAVAILABLE")
}
fn ech_client() -> Result<Client> {
    let mut cached=ECH_CLIENT.get_or_init(||Mutex::new(None)).lock().map_err(|_|"NETWORK_UNAVAILABLE")?;
    if let Some(entry)=cached.as_ref() { if entry.expires>Instant::now() { return Ok(entry.client.clone()); } }
    let bootstrap=base().tls_backend_preconfigured(ClientConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider()))
        .with_safe_default_protocol_versions().map_err(|_|"TLS_UNAVAILABLE")?.with_root_certificates(roots()).with_no_client_auth())
        .build().map_err(|_|"NETWORK_UNAVAILABLE")?;
    let response=bootstrap.get("https://223.5.5.5/resolve?name=cloudflare-ech.com&type=HTTPS").header("Accept","application/json")
        .send().map_err(|_|"ECH_DNS_UNAVAILABLE")?;
    if !response.status().is_success() { return Err("ECH_DNS_UNAVAILABLE"); }
    let mut body=Vec::new();response.take(131073).read_to_end(&mut body).map_err(|_|"ECH_DNS_UNAVAILABLE")?;
    if body.len()>131072 { return Err("ECH_DNS_UNAVAILABLE"); }
    let (bytes,ttl)=parse_ech(&serde_json::from_slice(&body).map_err(|_|"ECH_DNS_UNAVAILABLE")?)?;
    let ech=EchConfig::new(EchConfigListBytes::from(bytes),rustls::crypto::aws_lc_rs::hpke::ALL_SUPPORTED_SUITES).map_err(|_|"ECH_CONFIG_INVALID")?;
    let mut tls=ClientConfig::builder_with_provider(Arc::new(rustls::crypto::aws_lc_rs::default_provider())).with_ech(EchMode::from(ech))
        .map_err(|_|"ECH_CONFIG_INVALID")?.with_root_certificates(roots()).with_no_client_auth();
    tls.alpn_protocols=vec![b"h2".to_vec(),b"http/1.1".to_vec()];
    let config=Arc::new(tls.clone());
    let mut builder=base().tls_backend_preconfigured(tls);
    for host in API_HOSTS { builder=builder.resolve_to_addrs(host,&["104.18.10.118:443".parse().unwrap(),"104.18.11.118:443".parse().unwrap()]); }
    let client=builder.build().map_err(|_|"NETWORK_UNAVAILABLE")?;
    *cached=Some(CachedClient {client:client.clone(),expires:Instant::now()+Duration::from_secs(ttl),tls:config});
    Ok(client)
}
// The actual Pixez MIT rhttp client handles ECH discovery, TLS, DNS and connection caching.
// This adapter constrains its general-purpose settings to our fixed, verified destinations.
fn rhttp_settings(image: bool) -> setu_rhttp_native::api::client::ClientSettings {
    use setu_rhttp_native::api::client::*;
    let hosts: &[&str] = if image { &IMAGE_HOSTS } else { &API_HOSTS };
    let addresses = if image { vec!["210.140.139.133".into()] }
        else { vec!["104.18.10.118".into(), "104.18.11.118".into()] };
    ClientSettings {
        enable_ech: !image, require_ech: !image,
        throw_on_status_code: false,
        proxy_settings: Some(ProxySettings::NoProxy),
        redirect_settings: Some(RedirectSettings::NoRedirect),
        timeout_settings: Some(TimeoutSettings {
            timeout: Some(chrono::Duration::seconds(35)),
            connect_timeout: Some(chrono::Duration::seconds(8)),
            keep_alive_timeout: None, keep_alive_ping: None,
        }),
        tls_settings: Some(TlsSettings {
            root_cert_source: RootCertSource::Webpki, trusted_root_certificates: Vec::new(),
            verify_certificates: true, client_certificate: None,
            min_tls_version: None, max_tls_version: None, sni: !image,
        }),
        dns_settings: Some(DnsSettings::StaticDns(StaticDnsSettings {
            overrides: hosts.iter().map(|h| (h.to_string(), addresses.clone())).collect(), fallback: None,
        })),
        ..ClientSettings::default()
    }
}
async fn rhttp_client(image: bool, url: &Url) -> Result<reqwest::Client> {
    if image { return image::client(url).await; }
    let cache = &RHTTP_API;
    if cache.get().is_none() {
        let client = setu_rhttp_native::api::client::RequestClient::new(rhttp_settings(image))
            .map_err(|_| "NETWORK_UNAVAILABLE")?;
        let _ = cache.set(client);
    }
    cache.get().ok_or("NETWORK_UNAVAILABLE")?.client_for_url(url).await
        .map_err(|_| "ECH_CONFIG_UNAVAILABLE")
}

#[repr(C)]
pub struct SetuPixivCancellation { cancelled: AtomicBool }
#[repr(C)]
pub struct SetuPixivResponse { status:i32,bytes:*mut u8,length:usize,content_type:*mut c_char,error:*mut c_char }
fn check(cancel:&SetuPixivCancellation)->Result<()> { if cancel.cancelled.load(Ordering::Relaxed) { Err("CANCELLED") } else { Ok(()) } }
fn execute(input:Request,cancel:&SetuPixivCancellation)->Result<(i32,Vec<u8>,String)> {
    check(cancel)?;
    if RHTTP_RUNTIME.get().is_none() {
        let runtime = tokio::runtime::Builder::new_multi_thread().worker_threads(4)
            .enable_all().build().map_err(|_| "NETWORK_UNAVAILABLE")?;
        let _ = RHTTP_RUNTIME.set(runtime);
    }
    RHTTP_RUNTIME.get().ok_or("NETWORK_UNAVAILABLE")?.block_on(async {
        tokio::select! {
            value = tokio::time::timeout(Duration::from_secs(45), execute_async(input, cancel)) =>
                value.map_err(|_| "NETWORK_UNAVAILABLE")?,
            _ = async { loop {
                if check(cancel).is_err() { break; }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }} => Err("CANCELLED"),
        }
    })
}
async fn execute_async(input:Request,cancel:&SetuPixivCancellation)->Result<(i32,Vec<u8>,String)> {
    check(cancel)?;
    if input.public_image_probe > 0 { return image::public_probe(input.public_image_probe).await; }
    let custom = input.image_mirror_host.as_deref();
    let mut url=image::destination(&input.url, custom)?;
    let image=custom.is_some() || IMAGE_HOSTS.contains(&url.host_str().unwrap_or(""));
    if input.max_bytes==0 || input.max_bytes>100*1024*1024 || input.headers.len()>20
        || !["GET","POST"].contains(&input.method.as_str()) || (image && (input.method!="GET" || input.body.is_some()))
        || input.body.as_ref().is_some_and(|b| b.len()>65536) { return Err("INVALID_REQUEST"); }
    if image && input.headers.keys().any(|k| !["referer", "user-agent", "accept", "range"].contains(&k.to_ascii_lowercase().as_str())) { return Err("INVALID_REQUEST"); }
    for attempt in 0..4 {
        let client=if custom.is_some() { image::custom_client(&url).await? } else { rhttp_client(image, &url).await? };check(cancel)?;
        let mut request=client.request(input.method.parse().map_err(|_|"INVALID_REQUEST")?,url.clone());
        for (name,value) in &input.headers {
            if name.eq_ignore_ascii_case("cookie") || name.eq_ignore_ascii_case("host") || value.len()>16384 { return Err("INVALID_REQUEST"); }
            request=request.header(name,value);
        }
        if let Some(body)=&input.body { request=request.body(body.clone()); }
        let sent = if image {
            match tokio::time::timeout(Duration::from_secs(10), request.send()).await {
                Ok(Ok(response)) => Ok(response), _ => Err("IMAGE_HEADERS_UNAVAILABLE"),
            }
        } else { request.send().await.map_err(|_| "NETWORK_UNAVAILABLE") };
        check(cancel)?;
        let mut response = match sent {
            Ok(response) => response,
            Err(_) if image && attempt == 0 => continue,
            Err(error) => return Err(error),
        };
        if response.status().is_redirection() {
            // Only already-public images may follow redirects; API/OAuth credentials never cross destinations.
            if !image { return Err("UNEXPECTED_REDIRECT"); }
            url=image::destination(url.join(response.headers().get("location").and_then(|h|h.to_str().ok()).ok_or("INVALID_REDIRECT")?)
                .map_err(|_|"INVALID_REDIRECT")?.as_str(), custom)?;
            if custom.is_none() && !IMAGE_HOSTS.contains(&url.host_str().unwrap_or("")) {return Err("INVALID_REDIRECT");}
            continue;
        }
        if response.content_length().is_some_and(|n| n>input.max_bytes as u64) { return Err("RESPONSE_TOO_LARGE"); }
        let status=response.status().as_u16() as i32;
        let content_type=response.headers().get("content-type").and_then(|v|v.to_str().ok()).unwrap_or("application/octet-stream").to_owned();
        let mut bytes=Vec::new();
        while let Some(chunk)=response.chunk().await.map_err(|_| if image {"IMAGE_BODY_UNAVAILABLE"} else {"NETWORK_UNAVAILABLE"})? {
            check(cancel)?;
            if bytes.len()+chunk.len()>input.max_bytes {return Err("RESPONSE_TOO_LARGE");}
            bytes.extend_from_slice(&chunk);
        }
        return Ok((status,bytes,content_type));
    }
    Err("INVALID_REDIRECT")
}
fn response(value:Result<(i32,Vec<u8>,String)>)->*mut SetuPixivResponse {
    let (status,bytes,mime,error)=match value { Ok((s,b,m))=>(s,b,m,String::new()),Err(e)=>(0,Vec::new(),String::new(),e.to_owned()) };
    let boxed=bytes.into_boxed_slice();let length=boxed.len();let bytes=Box::into_raw(boxed) as *mut u8;
    Box::into_raw(Box::new(SetuPixivResponse {status,bytes,length,content_type:CString::new(mime).unwrap_or_default().into_raw(),error:CString::new(error).unwrap().into_raw()}))
}
#[no_mangle] pub extern "C" fn setu_pixiv_cancellation_create()->*mut SetuPixivCancellation {Box::into_raw(Box::new(SetuPixivCancellation {cancelled:AtomicBool::new(false)}))}
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_cancel(value:*mut SetuPixivCancellation) {if let Some(value)=value.as_ref(){value.cancelled.store(true,Ordering::Relaxed);}}
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_cancellation_free(value:*mut SetuPixivCancellation) {if !value.is_null(){drop(Box::from_raw(value));}}
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_request(json:*const c_char,cancel:*const SetuPixivCancellation)->*mut SetuPixivResponse {
    if json.is_null() || cancel.is_null(){return response(Err("INVALID_REQUEST"));}
    // The Swift bridge owns both pointers for the entire call. Do not expose panic text or upstream bodies in errors.
    response(std::panic::catch_unwind(||{
        let bytes=CStr::from_ptr(json).to_bytes();if bytes.len()>131072{return Err("INVALID_REQUEST");}
        execute(serde_json::from_slice(bytes).map_err(|_|"INVALID_REQUEST")?,&*cancel)
    }).unwrap_or(Err("NETWORK_UNAVAILABLE")))
}
#[no_mangle] pub unsafe extern "C" fn setu_pixiv_response_free(value:*mut SetuPixivResponse) {
    if value.is_null(){return;}let value=Box::from_raw(value);
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(value.bytes,value.length)));
    drop(CString::from_raw(value.content_type));drop(CString::from_raw(value.error));
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn reused_rhttp_keeps_credentials_and_trust_boundaries() {
        use setu_rhttp_native::api::client::*;
        for image in [false, true] {
            let settings = rhttp_settings(image);
            assert!(settings.cookie_settings.is_none());
            assert!(matches!(settings.redirect_settings, Some(RedirectSettings::NoRedirect)));
            assert!(matches!(settings.proxy_settings, Some(ProxySettings::NoProxy)));
            let tls = settings.tls_settings.unwrap();
            assert!(tls.verify_certificates);
            assert!(matches!(tls.root_cert_source, RootCertSource::Webpki));
            assert!(tls.trusted_root_certificates.is_empty());
            assert_eq!(settings.require_ech, !image);
            assert_eq!(tls.sni, !image);
        }
    }
    // Public, deliberately invalid grant: never reads or uses an account credential.
    // Opt-in only; a 400 proves reaching OAuth validation, not successful authorization.
    #[test]
    #[ignore = "explicit public OAuth connectivity check only"]
    fn public_oauth_reaches_grant_validation() {
        let input=Request {
            url: "https://oauth.secure.pixiv.net/auth/token".into(), method: "POST".into(),
            headers: HashMap::from([
                ("User-Agent".into(), "PixivAndroidApp/5.0.155 (Android 6.0; Pixel C)".into()),
                ("App-OS".into(), "Android".into()), ("App-OS-Version".into(), "Android 6.0".into()),
                ("App-Version".into(), "5.0.166".into()), ("Accept-Language".into(), "zh-CN".into()),
                ("Content-Type".into(), "application/x-www-form-urlencoded".into()),
            ]),
            body: Some("grant_type=setu_connectivity_probe".into()), max_bytes: 1048576, public_image_probe: 0, image_mirror_host: None,
        };
        let cancel=SetuPixivCancellation {cancelled: AtomicBool::new(false)};
        let (status, _, mime)=execute(input,&cancel).expect("Transport could not reach OAuth");
        eprintln!("Public OAuth validation HTTP {status}, MIME {mime}");
        assert_eq!(status, 400, "Upstream did not reach OAuth grant validation");
    }
    #[test]
    #[ignore = "Public ECH differential: no account credentials"]
    fn public_ech_configuration_comparison() {
        use setu_rhttp_native::api::client::*;
        use setu_rhttp_native::api::http::HttpVersionPref;
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let url = Url::parse("https://app-api.pixiv.net/v1/illust/recommended?filter=for_ios").unwrap();
            for variant in ["current", "explicit-host", "upstream-defaults", "http1"] {
                let mut settings = rhttp_settings(false);
                if variant == "upstream-defaults" {
                    settings.proxy_settings = None;
                    settings.timeout_settings = None;
                    // Keep no redirects and certificate verification in every probe.
                }
                if variant == "http1" { settings.http_version_pref = HttpVersionPref::Http11; }
                let client = RequestClient::new(settings).unwrap().client_for_url(&url).await.unwrap();
                let mut request = client.get(url.clone()).header("User-Agent", "PixivAndroidApp/5.0.155 (Android 10.0; Pixel C)");
                if variant == "explicit-host" { request = request.header("Host", "app-api.pixiv.net"); }
                match tokio::time::timeout(Duration::from_secs(25), request.send()).await {
                    Ok(Ok(response)) => eprintln!("public ECH {variant}: HTTP {}, JSON {}", response.status(), response.headers().get("content-type").is_some_and(|h| h.to_str().unwrap_or("").contains("application/json"))),
                    _ => eprintln!("public ECH {variant}: connection failed"),
                }
            }
        });
    }
    #[test]
    #[ignore = "Public image endpoint diagnostic: no account credentials"]
    fn public_image_endpoints() {
        use setu_rhttp_native::api::client::*;
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let mut jobs = tokio::task::JoinSet::new();
            for ip in ["210.140.139.129", "210.140.139.132", "210.140.139.133", "210.140.139.137"] {
                jobs.spawn(async move {
                    let mut settings = rhttp_settings(true);
                    settings.dns_settings = Some(DnsSettings::StaticDns(StaticDnsSettings {
                        overrides: HashMap::from([("i.pximg.net".into(), vec![ip.into()])]), fallback: None,
                    }));
                    let url = Url::parse("https://i.pximg.net/img-original/img/2025/05/15/00/08/58/130412285_p0.jpg").unwrap();
                    let client = RequestClient::new(settings).unwrap().client_for_url(&url).await.unwrap();
                    let start = Instant::now();
                    let result = tokio::time::timeout(Duration::from_secs(12), client.get(url).header("Referer", "https://www.pixiv.net/").send()).await;
                    match result {
                        Ok(Ok(response)) => eprintln!("public image {ip}: HTTP {}, {:?}, {}ms", response.status(), (response.headers().get("content-type"), response.content_length()), start.elapsed().as_millis()),
                        _ => eprintln!("public image {ip}: failed {}ms", start.elapsed().as_millis()),
                    }
                });
            }
            while jobs.join_next().await.is_some() {}
        });
    }
    #[test] fn unsafe_destinations_fail_before_network() {
        for value in ["http://app-api.pixiv.net/", "https://127.0.0.1/", "https://app-api.pixiv.net.evil/", "https://a@app-api.pixiv.net/", "https://i.pximg.net:444/", "https://i.pximg.net/#fragment"] {assert!(target(value).is_err());}
        assert!(target("https://i.pximg.net/image.jpg").is_ok());
        assert!(target("https://i.pixiv.re/image.jpg").is_ok());
        assert!(target("https://i.pixiv.re.evil/image.jpg").is_err());
    }
    #[test] fn image_mirror_rejects_credentials_and_custom_headers_before_network() {
        for header in ["Authorization", "Cookie", "X-Signature", "X-Timestamp", "Host", "X-Api-Key"] {
            let input = Request { url: "https://i.pixiv.re/image.jpg".into(), method: "GET".into(),
                headers: HashMap::from([(header.into(), "fixture".into())]), body: None,
                max_bytes: 100, public_image_probe: 0, image_mirror_host: None };
            let cancel = SetuPixivCancellation { cancelled: AtomicBool::new(false) };
            assert_eq!(execute(input, &cancel).unwrap_err(), "INVALID_REQUEST");
        }
    }
    #[test] fn cancellation_prevents_requests() {
        let input=Request {url:"https://app-api.pixiv.net/v1/illust/detail".into(),method:"GET".into(),headers:HashMap::new(),body:None,max_bytes:100,public_image_probe:0,image_mirror_host:None};
        let cancel=SetuPixivCancellation {cancelled:AtomicBool::new(true)};
        assert_eq!(execute(input,&cancel).unwrap_err(),"CANCELLED");
    }
    #[test] fn ech_dns_requires_https_record_and_bounded_configuration() {
        assert!(parse_ech(&serde_json::json!({"Answer":[{"type":1,"data":"ech=AQID","TTL":10}]})).is_err());
        let (bytes,ttl)=parse_ech(&serde_json::json!({"Answer":[{"type":65,"data":"1 . ech=AQID","TTL":9000}]})).unwrap();
        assert_eq!(bytes,vec![1,2,3]);assert_eq!(ttl,300);
    }
}
