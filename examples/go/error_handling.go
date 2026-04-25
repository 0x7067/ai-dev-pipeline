// Result-style error handling and fail-closed patterns.
package examples

import (
	"errors"
	"fmt"
)

// --- Custom error types ---

type AuthError struct {
	Reason string
	UserID int
}

func (e *AuthError) Error() string {
	return fmt.Sprintf("auth denied for user %d: %s", e.UserID, e.Reason)
}

type NotFoundError struct {
	Resource string
	ID       int
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("%s %d not found", e.Resource, e.ID)
}

// --- Core logic with structured errors ---

type UserID struct{ Value int }

type Permission struct {
	UserID UserID
	Roles  []string
}

func ParseUserID(raw int) (UserID, error) {
	if raw < 1 {
		return UserID{}, fmt.Errorf("user id must be positive, got %d", raw)
	}
	return UserID{Value: raw}, nil
}

var knownPerms = map[int][]string{
	1: {"read", "write"},
	2: {"read"},
}

func LookupPermissions(id UserID) (Permission, error) {
	roles, ok := knownPerms[id.Value]
	if !ok {
		return Permission{}, &NotFoundError{Resource: "user", ID: id.Value}
	}
	return Permission{UserID: id, Roles: roles}, nil
}

func hasRole(roles []string, required string) bool {
	for _, r := range roles {
		if r == required {
			return true
		}
	}
	return false
}

// Authorize demonstrates fail-closed: deny on any error.
func Authorize(rawID int, required string) error {
	id, err := ParseUserID(rawID)
	if err != nil {
		return &AuthError{Reason: err.Error(), UserID: rawID}
	}

	perm, err := LookupPermissions(id)
	if err != nil {
		var nf *NotFoundError
		if errors.As(err, &nf) {
			return &AuthError{Reason: "unknown user", UserID: rawID}
		}
		return &AuthError{Reason: "lookup failed", UserID: rawID}
	}

	if !hasRole(perm.Roles, required) {
		return &AuthError{Reason: fmt.Sprintf("missing %q role", required), UserID: rawID}
	}
	return nil
}
