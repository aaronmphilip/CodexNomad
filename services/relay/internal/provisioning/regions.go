package provisioning

import "strings"

func ChooseRegion(country, ip string) string {
	c := strings.ToUpper(strings.TrimSpace(country))
	switch c {
	case "IN", "BD", "LK", "NP":
		return "blr1"
	case "SG", "MY", "TH", "VN", "ID", "PH":
		return "sgp1"
	case "JP", "KR", "TW":
		return "sgp1"
	case "AU", "NZ":
		return "syd1"
	case "GB", "IE", "FR", "DE", "NL", "BE", "ES", "IT", "SE", "NO", "DK", "FI", "PL", "CH", "AT":
		return "fra1"
	case "BR", "AR", "CL", "CO", "PE":
		return "nyc3"
	case "CA":
		return "tor1"
	case "US":
		return "nyc3"
	default:
		if strings.Contains(ip, ":") {
			return "nyc3"
		}
		return "nyc3"
	}
}

func CountryFromHeaders(headers map[string]string) string {
	for _, key := range []string{"CF-IPCountry", "X-Vercel-IP-Country", "X-Country-Code", "Fly-Client-Country"} {
		if v := strings.TrimSpace(headers[key]); v != "" && strings.ToUpper(v) != "XX" {
			return strings.ToUpper(v)
		}
	}
	return ""
}
