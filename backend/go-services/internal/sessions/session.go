package sessions

import "time"

// Session represents a persistent refresh session stored in MongoDB
type Session struct {
	ID           string    `bson:"_id,omitempty" json:"id"`
	RefreshToken string    `bson:"refreshToken" json:"refreshToken"`
	Sub          string    `bson:"sub" json:"sub"`
	ExpiresAt    time.Time `bson:"expiresAt" json:"expiresAt"`
	CreatedAt    time.Time `bson:"createdAt" json:"createdAt"`
}
