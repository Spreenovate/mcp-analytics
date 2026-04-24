package server

import "testing"

func TestIsValidVisitorID(t *testing.T) {
	for _, s := range []string{
		"abc123def4567890",                     // 16 hex
		"0123456789abcdef0123456789abcdef",     // 32 hex (stripped UUID)
		"550e8400-e29b-41d4-a716-446655440000", // dashed UUID
		"ABCxyz123MixedCase0000",               // mixed alnum
	} {
		if !isValidVisitorID(s) {
			t.Errorf("expected valid: %q", s)
		}
	}

	for _, s := range []string{
		"",
		"short",                                 // <16
		repeat("a", 65),                        // >64
		"has space here xxxxx",
		"has/slash/inside/abcd",
		"underscore_is_invalid_abcdef",
		"<script>alert(1)</script>xxx",
	} {
		if isValidVisitorID(s) {
			t.Errorf("expected invalid: %q", s)
		}
	}
}

func repeat(s string, n int) string {
	out := ""
	for i := 0; i < n; i++ {
		out += s
	}
	return out
}
