package bot

import "strings"

// Lowercased UA substrings that indicate a bot / crawler / automation.
// Kept intentionally small — easy to extend.
var botMarkers = []string{
	"bot", "crawl", "spider", "slurp", "mediapartners", "facebookexternalhit",
	"embedly", "pingdom", "uptimerobot", "gtmetrix", "lighthouse", "pagespeed",
	"headlesschrome", "phantomjs", "selenium", "puppeteer", "playwright",
	"preview", "fetch", "python-requests", "curl/", "wget/", "go-http-client",
	"okhttp/", "apache-httpclient", "java/", "http.rb/", "httpx",
	"applebot", "bingpreview", "yandex", "baiduspider", "duckduckbot",
	"semrush", "ahrefs", "dotbot", "mj12bot", "bytespider", "petalbot",
}

func IsBot(ua string) bool {
	if ua == "" {
		return true
	}
	lo := strings.ToLower(ua)
	for _, m := range botMarkers {
		if strings.Contains(lo, m) {
			return true
		}
	}
	return false
}
