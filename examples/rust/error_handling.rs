//! Result types and fail-closed error handling.
#![allow(dead_code)]

use std::fmt;

// --- Custom error types ---

#[derive(Debug)]
enum AppError {
    Parse { field: String, message: String },
    NotFound { resource: String, id: u64 },
    AccessDenied { reason: String },
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Parse { field, message } => write!(f, "parse error in {field}: {message}"),
            Self::NotFound { resource, id } => write!(f, "{resource} {id} not found"),
            Self::AccessDenied { reason } => write!(f, "access denied: {reason}"),
        }
    }
}

impl std::error::Error for AppError {}

// --- Domain types ---

#[derive(Debug, Clone)]
struct UserId(u64);

// --- Boundary: parse ---

fn parse_user_id(raw: &str) -> Result<UserId, AppError> {
    let n: u64 = raw.trim().parse().map_err(|_| AppError::Parse {
        field: "user_id".into(),
        message: format!("not a valid number: {raw:?}"),
    })?;
    if n == 0 {
        return Err(AppError::Parse {
            field: "user_id".into(),
            message: "must be positive".into(),
        });
    }
    Ok(UserId(n))
}

// --- Core: lookup ---

fn lookup_roles(id: &UserId) -> Result<Vec<String>, AppError> {
    match id.0 {
        1 => Ok(vec!["read".into(), "write".into()]),
        2 => Ok(vec!["read".into()]),
        _ => Err(AppError::NotFound {
            resource: "user".into(),
            id: id.0,
        }),
    }
}

// --- Fail-closed: deny by default on any error ---

fn authorize(raw_id: &str, required: &str) -> Result<(), AppError> {
    let id = parse_user_id(raw_id)?;
    let roles = lookup_roles(&id)?;

    if !roles.iter().any(|r| r == required) {
        return Err(AppError::AccessDenied {
            reason: format!("missing {:?} role", required),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_authorize_success() {
        assert!(authorize("1", "read").is_ok());
        assert!(authorize("1", "write").is_ok());
    }

    #[test]
    fn test_authorize_denied() {
        assert!(authorize("2", "write").is_err());
        assert!(authorize("999", "read").is_err());
        assert!(authorize("abc", "read").is_err());
    }
}
