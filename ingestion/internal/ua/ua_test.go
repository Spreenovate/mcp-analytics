package ua

import "testing"

func TestParse_Chrome(t *testing.T) {
	p := Parse("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	if p.Browser != "Chrome" || p.BrowserVersion != "120" {
		t.Errorf("got browser=%q version=%q", p.Browser, p.BrowserVersion)
	}
	if p.OS != "Windows" || p.DeviceType != "desktop" {
		t.Errorf("got os=%q device=%q", p.OS, p.DeviceType)
	}
}

func TestParse_Safari_macOS(t *testing.T) {
	p := Parse("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")
	if p.Browser != "Safari" || p.BrowserVersion != "17" {
		t.Errorf("got browser=%q version=%q", p.Browser, p.BrowserVersion)
	}
	if p.OS != "macOS" {
		t.Errorf("os: got %q want macOS", p.OS)
	}
}

func TestParse_Firefox_Linux(t *testing.T) {
	p := Parse("Mozilla/5.0 (X11; Linux x86_64; rv:122.0) Gecko/20100101 Firefox/122.0")
	if p.Browser != "Firefox" || p.BrowserVersion != "122" {
		t.Errorf("got browser=%q version=%q", p.Browser, p.BrowserVersion)
	}
	if p.OS != "Linux" {
		t.Errorf("os: got %q", p.OS)
	}
}

func TestParse_Edge_BeatsChrome(t *testing.T) {
	// Edge UA contains Chrome/ — must match Edge first.
	p := Parse("Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.2210.91")
	if p.Browser != "Edge" {
		t.Errorf("expected Edge to win over Chrome, got %q", p.Browser)
	}
}

func TestParse_iPhone_isMobile_iOS(t *testing.T) {
	p := Parse("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
	if p.OS != "iOS" {
		t.Errorf("os: got %q", p.OS)
	}
	if p.DeviceType != "mobile" {
		t.Errorf("device: got %q", p.DeviceType)
	}
}

func TestParse_iPad_isTablet(t *testing.T) {
	p := Parse("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
	if p.DeviceType != "tablet" {
		t.Errorf("device: got %q want tablet", p.DeviceType)
	}
}

func TestParse_Android(t *testing.T) {
	p := Parse("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
	if p.OS != "Android" || p.DeviceType != "mobile" || p.Browser != "Chrome" {
		t.Errorf("got os=%q device=%q browser=%q", p.OS, p.DeviceType, p.Browser)
	}
}

func TestParse_EmptyDefaults(t *testing.T) {
	p := Parse("")
	if p.Browser != "Other" || p.OS != "Other" || p.DeviceType != "desktop" {
		t.Errorf("empty UA defaults wrong: %+v", p)
	}
}
