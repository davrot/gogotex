package models

import "time"

// User represents an application user (mapped from Keycloak claims)
type User struct {
	ID        string    `bson:"_id,omitempty" json:"id"`
	Sub       string    `bson:"sub" json:"sub"` // OIDC subject
	OIDCId    string    `bson:"oidcId,omitempty" json:"oidcId,omitempty"`
	Email     string    `bson:"email" json:"email"`
	Name      string    `bson:"name" json:"name"`
	CreatedAt time.Time `bson:"createdAt" json:"createdAt"`
	UpdatedAt time.Time `bson:"updatedAt" json:"updatedAt"`
}
