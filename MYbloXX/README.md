# MYbloXX — ad-blocking PACs and mobileconfig templates

This folder holds the ad-blocking assets TrollBox ships with. The **Ad
Blocking** section in the app reads them to build the user's chosen
`.mobileconfig` on-device.

## Credits & upstream

The PAC filter format, variant naming (`noFB`, `noXXX`, `noOTA`) and base
blocklist all come from **[MYbloXX for iOS](https://github.com/pegakmupyem/myxxdev)**
by pegakmupyem. The PACs in `PAC/` are a merge of that project's base with
a fresh dump of **[StevenBlack/hosts](https://github.com/StevenBlack/hosts)**
(~81k extra domains covering modern ad / tracker / crypto-mining servers).

## Contents

```
PAC/                         ← 4 PAC files (JavaScript), ~2.3 MB each
  MYbloXX.pac                  Standard blocker
  MYbloXXnoFB.pac              Standard minus graph.facebook.com + graph.instagram.com
                               (lets Facebook / Instagram login SDK work)
  MYbloXXnoXXX.pac             Standard + ~45 wildcard filters for adult keywords
  MYbloXXnoFBnoXXX.pac         noFB + noXXX combined

Templates/                   ← mobileconfig payload skeletons
  proxy-payload.plist          Global HTTP Proxy payload; ABMainViewController
                               fills in ProxyPACURL at install time
  tvos-beta-payload.plist      "iOS updates blocker" via the classic fake
                               tvOS Beta Software Profile trick

scripts/
  merge-stevenblack.py         Refreshes the 4 PACs with a fresh StevenBlack
                               hosts file (run by the GitHub Actions workflow
                               before each build)
  generate-mobileconfigs.py    Pre-builds the 8 .mobileconfig files attached
                               to each GitHub Release (one per toggle combo)
```

## PAC file format

Each PAC is a JavaScript file exposing `FindProxyForURL(url, host)`. iOS
runs it for every HTTP(S) request and uses the return value to decide
whether to route the request through the proxy or let it go DIRECT.

The MYbloXX PACs sinkhole any URL whose host matches a key in
`bad_da_host_JSON = {"doubleclick.net": null, ...}` or matches a wildcard
in the substring regex, by returning `"PROXY 0.0.0.0:53"` (an address
that never answers → the request dies). Everything else returns
`"DIRECT"`. No HTTPS decryption, no MITM — the PAC only sees the URL.

## Refreshing the baseline

Automated at build time via `.github/workflows/build.yml`:

```yaml
- name: Fetch StevenBlack hosts
  run: curl -sL https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts -o /tmp/sb.hosts

- name: Merge into PACs
  run: python3 MYbloXX/scripts/merge-stevenblack.py --pac-dir MYbloXX/PAC --hosts /tmp/sb.hosts --output-dir Resources/AdBlock/PAC

- name: Pre-build the 8 mobileconfigs for the Release
  run: python3 MYbloXX/scripts/generate-mobileconfigs.py --pac-dir Resources/AdBlock/PAC --templates MYbloXX/Templates --output-dir dist/mobileconfigs
```

Users can also refresh from inside the app via the "Refresh blocklist
from StevenBlack" button in the Ad Blocking section.
