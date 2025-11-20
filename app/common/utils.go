package common

import (
	"encoding/hex"

	"github.com/google/uuid"
)

func GenerateId() string {
	id := uuid.New()

	return hex.EncodeToString(id[:])
}
