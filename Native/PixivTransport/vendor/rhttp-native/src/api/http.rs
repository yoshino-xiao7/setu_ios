// MIT: types from Pixez rhttp http.rs; Flutter request bindings are not included.
#[derive(Clone, Copy)]
pub enum HttpVersionPref { Http10, Http11, Http2, Http3, All }
#[derive(Clone, Debug)]
pub enum HttpResponseBody { Text(String), Bytes(Vec<u8>), Stream }
