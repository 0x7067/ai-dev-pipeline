//! Parse, don't validate: convert raw input to typed domain values or structured errors.
//!
//! For production Rust, use `serde` + `serde_json` for parsing. This example
//! shows the pattern with stdlib only.
#![allow(dead_code)]

use std::fmt;

// --- Domain types ---

#[derive(Debug, Clone, PartialEq)]
struct Email {
    local: String,
    domain: String,
}

impl fmt::Display for Email {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}@{}", self.local, self.domain)
    }
}

#[derive(Debug, Clone, PartialEq)]
struct Age(u8);

// --- Parse errors ---

#[derive(Debug)]
enum ParseError {
    InvalidEmail(String),
    InvalidAge(String),
    MissingField(String),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidEmail(msg) => write!(f, "invalid email: {msg}"),
            Self::InvalidAge(msg) => write!(f, "invalid age: {msg}"),
            Self::MissingField(name) => write!(f, "missing field: {name}"),
        }
    }
}

// --- Parsing (returns typed value or error) ---

fn parse_email(raw: &str) -> Result<Email, ParseError> {
    let raw = raw.trim();
    let at = raw
        .find('@')
        .ok_or_else(|| ParseError::InvalidEmail("missing @".into()))?;

    let local = &raw[..at];
    let domain = &raw[at + 1..];

    if local.is_empty() {
        return Err(ParseError::InvalidEmail("empty local part".into()));
    }
    if domain.is_empty() || !domain.contains('.') {
        return Err(ParseError::InvalidEmail("invalid domain".into()));
    }

    Ok(Email {
        local: local.to_string(),
        domain: domain.to_string(),
    })
}

fn parse_age(raw: &str) -> Result<Age, ParseError> {
    let n: u8 = raw
        .trim()
        .parse()
        .map_err(|_| ParseError::InvalidAge(format!("not a valid number: {raw:?}")))?;
    if n > 150 {
        return Err(ParseError::InvalidAge(format!("out of range: {n}")));
    }
    Ok(Age(n))
}

// --- CORRECT: Only accept parsed types ---

fn send_welcome(email: &Email) -> String {
    format!("Welcome email sent to {email}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_email_valid() {
        let email = parse_email("user@example.com").unwrap();
        assert_eq!(email.local, "user");
        assert_eq!(email.domain, "example.com");
    }

    #[test]
    fn test_parse_email_invalid() {
        assert!(parse_email("no-at").is_err());
        assert!(parse_email("@nodomain.com").is_err());
        assert!(parse_email("user@").is_err());
    }

    #[test]
    fn test_parse_age_valid() {
        assert_eq!(parse_age("25").unwrap(), Age(25));
    }

    #[test]
    fn test_parse_age_invalid() {
        assert!(parse_age("abc").is_err());
        assert!(parse_age("200").is_err());
    }
}
