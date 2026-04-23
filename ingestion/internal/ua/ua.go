package ua

import (
	"regexp"
	"strings"
)

type Parsed struct {
	Browser        string
	BrowserVersion string
	OS             string
	DeviceType     string // desktop | mobile | tablet | bot | other
}

var (
	reEdge      = regexp.MustCompile(`Edg(?:e|A|iOS)?/([\d\.]+)`)
	reOpera     = regexp.MustCompile(`(?:OPR|Opera)/([\d\.]+)`)
	reSamsung   = regexp.MustCompile(`SamsungBrowser/([\d\.]+)`)
	reFirefox   = regexp.MustCompile(`Firefox/([\d\.]+)`)
	reChrome    = regexp.MustCompile(`Chrom(?:e|ium)/([\d\.]+)`)
	reSafari    = regexp.MustCompile(`Version/([\d\.]+) Safari/`)
	reFirefoxIOS = regexp.MustCompile(`FxiOS/([\d\.]+)`)
	reChromeIOS  = regexp.MustCompile(`CriOS/([\d\.]+)`)
)

// Parse performs a lightweight UA sniff. It is intentionally approximate —
// good enough for top-level breakdowns, not a full UA database.
func Parse(ua string) Parsed {
	p := Parsed{
		Browser:    "Other",
		OS:         "Other",
		DeviceType: "desktop",
	}
	if ua == "" {
		return p
	}

	// OS
	switch {
	case strings.Contains(ua, "Windows NT 10"):
		p.OS = "Windows"
	case strings.Contains(ua, "Windows"):
		p.OS = "Windows"
	case strings.Contains(ua, "Mac OS X") || strings.Contains(ua, "Macintosh"):
		p.OS = "macOS"
	case strings.Contains(ua, "Android"):
		p.OS = "Android"
	case strings.Contains(ua, "iPhone") || strings.Contains(ua, "iPad") || strings.Contains(ua, "iPod"):
		p.OS = "iOS"
	case strings.Contains(ua, "CrOS"):
		p.OS = "ChromeOS"
	case strings.Contains(ua, "Linux"):
		p.OS = "Linux"
	}

	// Device type
	switch {
	case strings.Contains(ua, "iPad") || strings.Contains(ua, "Tablet"):
		p.DeviceType = "tablet"
	case strings.Contains(ua, "Mobile") || strings.Contains(ua, "iPhone") || strings.Contains(ua, "Android"):
		if !strings.Contains(ua, "iPad") && !strings.Contains(ua, "Tablet") {
			p.DeviceType = "mobile"
		}
	}

	// Browser — order matters because some UAs include multiple tokens.
	switch {
	case matchBrowser(ua, reEdge, &p, "Edge"):
	case matchBrowser(ua, reOpera, &p, "Opera"):
	case matchBrowser(ua, reSamsung, &p, "Samsung Internet"):
	case matchBrowser(ua, reFirefoxIOS, &p, "Firefox"):
	case matchBrowser(ua, reChromeIOS, &p, "Chrome"):
	case matchBrowser(ua, reFirefox, &p, "Firefox"):
	case strings.Contains(ua, "Chrome/"):
		matchBrowser(ua, reChrome, &p, "Chrome")
	case strings.Contains(ua, "Safari/"):
		matchBrowser(ua, reSafari, &p, "Safari")
	}

	return p
}

func matchBrowser(ua string, re *regexp.Regexp, p *Parsed, name string) bool {
	m := re.FindStringSubmatch(ua)
	if len(m) < 2 {
		return false
	}
	p.Browser = name
	p.BrowserVersion = majorVersion(m[1])
	return true
}

func majorVersion(v string) string {
	if i := strings.Index(v, "."); i > 0 {
		return v[:i]
	}
	return v
}
