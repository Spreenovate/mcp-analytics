package main

import (
	"fmt"

	"github.com/mcp-analytics/ingestion/internal/ua"
)

func main() {
	uas := []string{
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:150.0) Gecko/20100101 Firefox/150.0",
		"Mozilla/5.0 (X11; Linux aarch64; rv:150.0) Gecko/20100101 Firefox/150.0",
		"Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X 14.2; rv:150.0) Gecko/20100101 Firefox/150.0",
	}
	for _, u := range uas {
		p := ua.Parse(u)
		fmt.Printf("Browser=%-10s Version=%-5s OS=%-10s Device=%s\n  UA=%s\n\n",
			p.Browser, p.BrowserVersion, p.OS, p.DeviceType, u)
	}
}
