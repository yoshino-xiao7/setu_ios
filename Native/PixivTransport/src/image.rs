//! Verified image origin connections with bounded, encrypted DNS and node rotation.
use super::*;
use setu_rhttp_native::api::client::{DnsSettings, RequestClient, StaticDnsSettings};
use std::net::Ipv4Addr;

struct Pool { clients: Vec<reqwest::Client>, next: usize, expires: Instant }
static POOLS: OnceLock<tokio::sync::Mutex<HashMap<String, Pool>>> = OnceLock::new();

fn valid_custom_host(host: &str) -> bool {
    host.len() <= 253 && host.contains('.') && !host.ends_with(".local") && !host.ends_with(".localhost")
        && host != "pixiv.net" && !host.ends_with(".pixiv.net")
        && host.rsplit('.').next().is_some_and(|last| last.bytes().any(|b| b.is_ascii_alphabetic()))
        && host.split('.').all(|label| !label.is_empty() && label.len() <= 63
            && !label.starts_with('-') && !label.ends_with('-')
            && label.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'))
}

pub(super) fn destination(raw: &str, custom: Option<&str>) -> Result<Url> {
    let Some(host) = custom else { return target(raw); };
    let url = Url::parse(raw).map_err(|_| "INVALID_DESTINATION")?;
    if !valid_custom_host(host) || url.host_str() != Some(host) || url.scheme() != "https"
        || !url.username().is_empty() || url.password().is_some() || url.fragment().is_some()
        || url.port_or_known_default() != Some(443) { return Err("INVALID_DESTINATION"); }
    Ok(url)
}

fn public_address(ip: std::net::IpAddr) -> bool {
    match ip {
        std::net::IpAddr::V4(ip) => public_ipv4(&ip.to_string()).is_some(),
        std::net::IpAddr::V6(ip) => {
            if let Some(ip) = ip.to_ipv4_mapped() { return public_ipv4(&ip.to_string()).is_some(); }
            let segments = ip.segments();
            !ip.is_loopback() && !ip.is_unspecified() && !ip.is_multicast() && !ip.is_unique_local()
                && !ip.is_unicast_link_local() && (segments[0] & 0xe000) == 0x2000
                && !(segments[0] == 0x2001 && segments[1] == 0x0db8)
        }
    }
}

pub(super) async fn custom_client(url: &Url) -> Result<reqwest::Client> {
    struct Cached { client: reqwest::Client, expires: Instant }
    static CUSTOM: OnceLock<tokio::sync::Mutex<HashMap<String, Cached>>> = OnceLock::new();
    let host = url.host_str().ok_or("INVALID_DESTINATION")?;
    if !valid_custom_host(host) { return Err("INVALID_DESTINATION"); }
    let mut clients = CUSTOM.get_or_init(|| tokio::sync::Mutex::new(HashMap::new())).lock().await;
    if let Some(value) = clients.get(host).filter(|c| c.expires > Instant::now()) { return Ok(value.client.clone()); }
    let resolved = tokio::time::timeout(Duration::from_secs(6), tokio::net::lookup_host((host, 443)))
        .await.map_err(|_| "IMAGE_DNS_UNAVAILABLE")?.map_err(|_| "IMAGE_DNS_UNAVAILABLE")?;
    let addresses: Vec<_> = resolved.collect();
    if addresses.is_empty() || addresses.len() > 64 || addresses.iter().any(|a| !public_address(a.ip())) {
        return Err("INVALID_DESTINATION");
    }
    // Pin the validated resolution, including redirects on the same host. No DNS rebinding into LAN.
    let client = reqwest::Client::builder().no_proxy().resolve_to_addrs(host, &addresses)
        .redirect(reqwest::redirect::Policy::none()).connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(35)).pool_max_idle_per_host(4)
        .build().map_err(|_| "NETWORK_UNAVAILABLE")?;
    clients.retain(|_, value| value.expires > Instant::now());
    if clients.len() >= 4 { clients.clear(); }
    clients.insert(host.into(), Cached { client: client.clone(), expires: Instant::now() + Duration::from_secs(60) });
    Ok(client)
}

// Explicit public-fixture diagnostic only. Ignores all caller URLs, headers and credentials.
// Reuses each variant's client so the second round measures a warm connection.
pub(super) async fn public_probe(probe: u8) -> Result<(i32, Vec<u8>, String)> {
    static CLIENTS: OnceLock<Mutex<HashMap<u8, reqwest::Client>>> = OnceLock::new();
    if !(1..=8).contains(&probe) { return Err("INVALID_REQUEST"); }
    let full = probe >= 6;
    let variant = match probe { 6 => 1, 7 => 5, 8 => 2, _ => probe };
    let limit = if full { 2 * 1024 * 1024 } else { 65536 };
    let host = if variant == 5 { "i.pixiv.re" } else { "i.pximg.net" };
    let url = Url::parse(&format!("https://{host}/img-original/img/2025/05/15/00/08/58/130412285_p0.jpg")).unwrap();
    let cached = CLIENTS.get_or_init(|| Mutex::new(HashMap::new())).lock().map_err(|_| "NETWORK_UNAVAILABLE")?.get(&variant).cloned();
    let client = if let Some(client) = cached { client } else {
        let client = if variant == 5 {
            reqwest::Client::builder().no_proxy().redirect(reqwest::redirect::Policy::none())
                .timeout(Duration::from_secs(20)).build().map_err(|_| "NETWORK_UNAVAILABLE")?
        } else {
            let mut settings = rhttp_settings(true);
            if variant % 2 == 0 { settings.http_version_pref = setu_rhttp_native::api::http::HttpVersionPref::Http11; }
            let ip = if variant <= 2 { "210.140.139.133" } else { "210.140.139.129" };
            settings.dns_settings = Some(DnsSettings::StaticDns(StaticDnsSettings {
                overrides: HashMap::from([(host.into(), vec![ip.into()])]), fallback: None,
            }));
            RequestClient::new(settings).map_err(|_| "NETWORK_UNAVAILABLE")?.client_for_url(&url).await.map_err(|_| "NETWORK_UNAVAILABLE")?
        };
        CLIENTS.get().unwrap().lock().map_err(|_| "NETWORK_UNAVAILABLE")?.insert(variant, client.clone());
        client
    };
    let mut request = client.get(url).header("Referer", "https://www.pixiv.net/").header("User-Agent", "PixivIOSApp/5.8.0")
        .timeout(Duration::from_secs(25));
    if !full { request = request.header("Range", "bytes=0-65535"); }
    let mut response = request.send().await.map_err(|_| "IMAGE_HEADERS_UNAVAILABLE")?;
    let status = response.status().as_u16() as i32;
    let mime = response.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("").to_owned();
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "IMAGE_BODY_UNAVAILABLE")? {
        if bytes.len() + chunk.len() > limit { return Err("RESPONSE_TOO_LARGE"); }
        bytes.extend_from_slice(&chunk);
    }
    Ok((status, bytes, mime))
}

fn public_ipv4(value: &str) -> Option<String> {
    let ip: Ipv4Addr = value.parse().ok()?;
    let [a, b, c, _] = ip.octets();
    if a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254)
        || (a == 172 && (16..=31).contains(&b)) || (a == 192 && b == 168)
        || (a == 100 && (64..=127).contains(&b)) || (a == 198 && (18..=19).contains(&b))
        || (a == 192 && b == 0) || (a == 198 && b == 51 && c == 100)
        || (a == 203 && b == 0 && c == 113) { return None; }
    Some(ip.to_string())
}

fn parse_dns(body: &[u8]) -> Result<(Vec<String>, u64)> {
    if body.len() > 65536 { return Err("IMAGE_DNS_INVALID"); }
    let value: serde_json::Value = serde_json::from_slice(body).map_err(|_| "IMAGE_DNS_INVALID")?;
    if value["Status"].as_u64() != Some(0) || value["TC"].as_bool() == Some(true) { return Err("IMAGE_DNS_INVALID"); }
    let answers = value["Answer"].as_array().ok_or("IMAGE_DNS_INVALID")?;
    let mut addresses = Vec::new();
    let mut ttl = 600;
    for answer in answers {
        if answer["type"].as_u64() != Some(1) { continue; }
        if let Some(ip) = answer["data"].as_str().and_then(public_ipv4) {
            if !addresses.contains(&ip) && addresses.len() < 12 { addresses.push(ip); }
            ttl = ttl.min(answer["TTL"].as_u64().unwrap_or(30).clamp(1, 600));
        }
    }
    if addresses.is_empty() { return Err("IMAGE_DNS_INVALID"); }
    Ok((addresses, ttl))
}

async fn lookup(host: &str) -> Result<(Vec<String>, u64)> {
    let bootstrap = reqwest::Client::builder().no_proxy()
        .resolve_to_addrs("1dot1dot1dot1.cloudflare-dns.com", &[
            "104.16.248.249:443".parse().unwrap(), "104.16.249.249:443".parse().unwrap()])
        .timeout(Duration::from_secs(6)).redirect(reqwest::redirect::Policy::none())
        .build().map_err(|_| "IMAGE_DNS_UNAVAILABLE")?;
    let mut response = bootstrap.get("https://1dot1dot1dot1.cloudflare-dns.com/dns-query")
        .query(&[("name", host), ("type", "A")]).header("Accept", "application/dns-json")
        .send().await.map_err(|_| "IMAGE_DNS_UNAVAILABLE")?;
    if !response.status().is_success() || response.content_length().is_some_and(|n| n > 65536) { return Err("IMAGE_DNS_INVALID"); }
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| "IMAGE_DNS_UNAVAILABLE")? {
        if body.len() + chunk.len() > 65536 { return Err("IMAGE_DNS_INVALID"); }
        body.extend_from_slice(&chunk);
    }
    parse_dns(&body)
}

pub(super) async fn client(url: &Url) -> Result<reqwest::Client> {
    let host = url.host_str().ok_or("INVALID_DESTINATION")?;
    if !IMAGE_HOSTS.contains(&host) { return Err("INVALID_DESTINATION"); }
    if host == "i.pixiv.re" {
        static MIRROR: OnceLock<reqwest::Client> = OnceLock::new();
        if let Some(client) = MIRROR.get() { return Ok(client.clone()); }
        // Standard verified HTTPS to this one selected image mirror. Never forward credentials.
        let client = reqwest::Client::builder().no_proxy().redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(8)).timeout(Duration::from_secs(35))
            .pool_max_idle_per_host(4).build().map_err(|_| "NETWORK_UNAVAILABLE")?;
        let _ = MIRROR.set(client.clone());
        return Ok(client);
    }
    let mut pools = POOLS.get_or_init(|| tokio::sync::Mutex::new(HashMap::new())).lock().await;
    let now = Instant::now();
    if !pools.get(host).is_some_and(|pool| pool.expires > now) {
        // Resolver outages may use the known official-origin nodes briefly, never a third-party image mirror.
        let (addresses, ttl) = lookup(host).await.unwrap_or_else(|_| (
            vec!["210.140.139.129".into(), "210.140.139.132".into(), "210.140.139.137".into(), "210.140.139.133".into()], 15));
        let mut clients = Vec::new();
        for ip in addresses {
            let mut settings = rhttp_settings(true);
            settings.dns_settings = Some(DnsSettings::StaticDns(StaticDnsSettings {
                overrides: HashMap::from([(host.to_owned(), vec![ip])]), fallback: None,
            }));
            clients.push(RequestClient::new(settings).map_err(|_| "NETWORK_UNAVAILABLE")?
                .client_for_url(url).await.map_err(|_| "NETWORK_UNAVAILABLE")?);
        }
        pools.insert(host.to_owned(), Pool { clients, next: 0, expires: Instant::now() + Duration::from_secs(ttl) });
    }
    let pool = pools.get_mut(host).ok_or("IMAGE_DNS_UNAVAILABLE")?;
    let client = pool.clients[pool.next % pool.clients.len()].clone();
    pool.next = (pool.next + 1) % pool.clients.len();
    Ok(client)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn custom_mirror_is_exact_https_host_and_public_addresses_only() {
        assert!(destination("https://images.example.org/path.jpg", Some("images.example.org")).is_ok());
        for raw in ["http://images.example.org/a", "https://user@images.example.org/a", "https://images.example.org:444/a", "https://other.example.org/a", "https://app-api.pixiv.net/a", "https://images.example.org/a#f"] {
            assert!(destination(raw, Some("images.example.org")).is_err());
        }
        for host in ["localhost", "127.0.0.1", "a.local", "a.localhost", "app-api.pixiv.net", "a..org", "-a.org", "a-.org"] { assert!(!valid_custom_host(host)); }
        for ip in ["127.0.0.1", "10.0.0.1", "169.254.169.254", "::1", "::ffff:127.0.0.1", "fe80::1", "fd00::1", "2001:db8::1"] { assert!(!public_address(ip.parse().unwrap())); }
        for ip in ["210.140.139.133", "2606:4700:4700::1111"] { assert!(public_address(ip.parse().unwrap())); }
    }
    #[test]
    #[ignore = "Fixed public image only; explicit protocol/node/mirror diagnostic"]
    fn public_image_speed_comparison() {
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            for round in 1..=2 {
                for variant in 1..=5 {
                    let started = Instant::now();
                    let result = public_probe(variant).await.map(|(status, bytes, _)| (status, bytes.len()));
                    eprintln!("round={round} variant={variant} result={result:?} ms={}", started.elapsed().as_millis());
                }
            }
        });
    }
    #[test] fn dns_keeps_public_a_records_deduplicates_and_bounds_ttl() {
        let body = br#"{"Status":0,"Answer":[{"type":5,"data":"alias"},{"type":1,"data":"10.0.0.1"},{"type":1,"data":"210.140.139.129","TTL":9000},{"type":1,"data":"210.140.139.129","TTL":20},{"type":1,"data":"210.140.139.132","TTL":40}]}"#;
        let (ips, ttl) = parse_dns(body).unwrap();
        assert_eq!(ips, ["210.140.139.129", "210.140.139.132"]);
        assert_eq!(ttl, 20);
    }
    #[test] fn dns_rejects_failed_truncated_or_non_public_answers() {
        for body in [br#"{"Status":2,"Answer":[]}"#.as_slice(), br#"{"Status":0,"TC":true,"Answer":[]}"#, br#"{"Status":0,"Answer":[{"type":1,"data":"127.0.0.1"}]}"#] {
            assert!(parse_dns(body).is_err());
        }
        for ip in ["localhost", "::1", "169.254.169.254", "192.168.1.1", "100.64.0.1", "224.0.0.1"] { assert!(public_ipv4(ip).is_none()); }
    }
}
