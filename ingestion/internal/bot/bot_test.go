package bot

import "testing"

func TestIsBot_KnownMarkers(t *testing.T) {
	bots := []string{
		"Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
		"Mozilla/5.0 (Linux) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0.0",
		"facebookexternalhit/1.1",
		"curl/7.88.1",
		"python-requests/2.31",
		"AhrefsBot/7.0; +http://ahrefs.com/robot/",
		"Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
	}
	for _, ua := range bots {
		if !IsBot(ua) {
			t.Errorf("expected bot for UA: %s", ua)
		}
	}
}

func TestIsBot_RealBrowsers(t *testing.T) {
	humans := []string{
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
		"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
	}
	for _, ua := range humans {
		if IsBot(ua) {
			t.Errorf("did NOT expect bot for UA: %s", ua)
		}
	}
}

func TestIsBot_EmptyStringIsBot(t *testing.T) {
	if !IsBot("") {
		t.Error("empty UA should be treated as bot")
	}
}

func TestIsBot_CaseInsensitive(t *testing.T) {
	if !IsBot("BOT/1.0") {
		t.Error("expected case-insensitive match")
	}
}
