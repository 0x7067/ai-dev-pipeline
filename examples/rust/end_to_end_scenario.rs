//! Full pipeline: parse request → core logic → serialize response.
#![allow(dead_code)]

use std::collections::HashMap;
use std::fmt;

// --- Domain types ---

#[derive(Debug)]
struct CreateUserRequest {
    name: String,
    email: String,
    age: u8,
}

#[derive(Debug)]
struct User {
    id: u64,
    name: String,
    email: String,
    age: u8,
}

#[derive(Debug)]
struct ApiError {
    code: u16,
    message: String,
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}

// --- Boundary: parse ---

fn parse_create_user(fields: &HashMap<String, String>) -> Result<CreateUserRequest, ApiError> {
    let name = fields
        .get("name")
        .filter(|s| !s.trim().is_empty())
        .ok_or(ApiError { code: 400, message: "name is required".into() })?
        .trim()
        .to_string();

    let email = fields
        .get("email")
        .filter(|s| s.contains('@'))
        .ok_or(ApiError { code: 400, message: "valid email is required".into() })?
        .trim()
        .to_string();

    let age: u8 = fields
        .get("age")
        .ok_or(ApiError { code: 400, message: "age is required".into() })?
        .parse()
        .map_err(|_| ApiError { code: 400, message: "age must be 0-150".into() })?;

    if age > 150 {
        return Err(ApiError { code: 400, message: "age must be 0-150".into() });
    }

    Ok(CreateUserRequest { name, email, age })
}

// --- Core: pure logic ---

fn create_user(req: CreateUserRequest, next_id: u64) -> User {
    User {
        id: next_id,
        name: req.name,
        email: req.email,
        age: req.age,
    }
}

// --- Boundary: serialize ---

fn serialize_user(user: &User) -> String {
    format!(
        r#"{{"id":{},"name":"{}","email":"{}","age":{}}}"#,
        user.id, user.name, user.email, user.age
    )
}

fn serialize_error(err: &ApiError) -> String {
    format!(r#"{{"error":{{"code":{},"message":"{}"}}}}"#, err.code, err.message)
}

// --- Shell: request handler ---

fn handle_create_user(fields: &HashMap<String, String>, next_id: u64) -> (u16, String) {
    match parse_create_user(fields) {
        Err(err) => (err.code, serialize_error(&err)),
        Ok(req) => {
            let user = create_user(req, next_id);
            (201, serialize_user(&user))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_fields(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn test_success() {
        let fields = make_fields(&[("name", "Alice"), ("email", "a@b.com"), ("age", "30")]);
        let (status, body) = handle_create_user(&fields, 1);
        assert_eq!(status, 201);
        assert!(body.contains("Alice"));
    }

    #[test]
    fn test_missing_name() {
        let fields = make_fields(&[("email", "a@b.com"), ("age", "30")]);
        let (status, _) = handle_create_user(&fields, 1);
        assert_eq!(status, 400);
    }
}
