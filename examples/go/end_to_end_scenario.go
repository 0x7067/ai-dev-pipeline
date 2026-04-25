// Full pipeline: parse HTTP request → core logic → serialize response.
package examples

import (
	"encoding/json"
	"fmt"
	"net/http"
)

// --- Domain types ---

type CreateUserRequest struct {
	Name  string `json:"name"`
	Email Email  `json:"-"`
	Age   int    `json:"age"`
}

type User struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
	Age   int    `json:"age"`
}

// --- Boundary: parse ---

func ParseCreateUser(data []byte) (CreateUserRequest, error) {
	var raw struct {
		Name  *string `json:"name"`
		Email *string `json:"email"`
		Age   *int    `json:"age"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return CreateUserRequest{}, fmt.Errorf("invalid JSON")
	}
	if raw.Name == nil || *raw.Name == "" {
		return CreateUserRequest{}, fmt.Errorf("name is required")
	}
	if raw.Email == nil {
		return CreateUserRequest{}, fmt.Errorf("email is required")
	}
	email, err := ParseEmail(*raw.Email)
	if err != nil {
		return CreateUserRequest{}, err
	}
	if raw.Age == nil || *raw.Age < 0 || *raw.Age > 150 {
		return CreateUserRequest{}, fmt.Errorf("age must be 0-150")
	}
	return CreateUserRequest{Name: *raw.Name, Email: email, Age: *raw.Age}, nil
}

// --- Core: pure logic ---

func CreateUser(req CreateUserRequest, nextID int) User {
	return User{
		ID:    nextID,
		Name:  req.Name,
		Email: req.Email.String(),
		Age:   req.Age,
	}
}

// --- Shell: HTTP handler ---

func HandleCreateUser(nextID int) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body []byte
		body = make([]byte, r.ContentLength)
		_, _ = r.Body.Read(body)

		req, err := ParseCreateUser(body)
		if err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}

		user := CreateUser(req, nextID)

		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(user)
	}
}
