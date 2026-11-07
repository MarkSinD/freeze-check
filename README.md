# freeze-check: which hosting networks work from Russia

[Русский](README.ru.md)

Since 2025 Russian TSPU equipment "freezes" TCP connections to part of the foreign hosting
market. The connection opens, a few packets pass (about 8 on mobile, about 25 on wired home
internet), then nothing arrives and no reset is sent. Websites "load forever, then fail", TCP VPNs
(Reality, XHTTP, OpenVPN TCP) do not connect, while UDP (WireGuard, AmneziaWG) keeps working.

This tool shows in 2-4 minutes which networks freeze **from your connection**, and tests your own
server.

- About 430 points in about 200 networks: public test files of hosting providers, verified from
  the EU.
- Needs only `bash` and `curl`: Linux, macOS, Git Bash on Windows.
- Nothing is uploaded. The results file holds no IP address. ipinfo.io is asked only for your
  country (to warn about a VPN left on) and, for `owner`, about the address you give.

## Download

```bash
mkdir freeze-check && cd freeze-check
curl -fsSLO https://raw.githubusercontent.com/MarkSinD/freeze-check/main/freeze-check.sh
curl -fsSLO https://raw.githubusercontent.com/MarkSinD/freeze-check/main/targets.tsv
```

Or download the ZIP on GitHub (Code → Download ZIP). The script is short: read it before running it.

## From a computer

The VPN must be off, otherwise you measure the VPN server's network, not yours. Easiest: start with
`--wait` and turn the VPN off afterwards; the script waits for a Russian address and starts itself.

```bash
bash freeze-check.sh scan --quick --wait
```

`--quick` checks one point per network, about 30 seconds; without it all points, 2-4 minutes.
Results go to `results/` next to the script, and the script tells you when the VPN can go back on.
To tag a run: `--label "Beeline LTE, Moscow"`.

Ordinary sites on Cloudflare and other CDNs (each URL 3 times):

```bash
bash freeze-check.sh cdn --wait
```

Start of the output on our home connection (November 2026):

```text
437 points: 378 downloaded, 0 slow but alive, 52 frozen, 7 got nothing.

BLOCKED networks (17) - every point there failed:
  AS16276   OVH SAS                            12/12  BlueVPS, IPhoster, KarasHost, OVH, SadeemRDP, ThomasHost
  AS63023   GTHost                             11/11  Qyrax
  AS36352   HostPapa                             7/7  DediRock, HostNamaste, RackNerd, SadeemRDP, Server Wala, SolaDrive
  AS14061   DigitalOcean, LLC                    3/3  LOOKING HOUSE
  AS9009    M247 Europe SRL                      3/3  1Gbits, Hosteroid, servinga Cloud
  AS24940   Hetzner Online GmbH                  2/2  Hetzner, Packetra
  ...
```

- `FROZEN`: the connection opened and stopped after a few KB. This is the freeze.
- `NONE`: nothing arrived. On mobile this is usually the same freeze: the limit is below one TLS
  handshake.
- `SLOW`: data flows, slowly. Not a freeze.
- At the end it lists points where your result differs from our November 2026 measurement.

**Share your result.** Open the [GitHub form](https://github.com/MarkSinD/freeze-check/issues/new?template=freeze-check-result.yml): operator, region, date and the script output,
no IP addresses. This turns one person's measurement into a shared table.

## Test your own server

Who owns the server's network, and what we measured there:

```bash
bash freeze-check.sh owner your.server.example
```

Measure the server itself. **On the server** (needs `python3`; open the port in the firewall):

```bash
bash freeze-check.sh serve 8080
```

It prints the test file's address. **On a computer in Russia, VPN off:**

```bash
bash freeze-check.sh url --wait http://YOUR_SERVER:8080/<token>/freeze-test.bin
```

Or open that address in a phone browser. Check it from abroad too: downloads abroad and stops in
Russia means the freeze. Ctrl+C stops the server and deletes the file. Avoid port 80: some Russian
ISPs intercept it.

## If your server is frozen

1. **Check who owns the network** (`owner`). The network owner decides, not the hosting brand. A
   cheap host sitting in the OVH, M247 or HostPapa network is frozen like the network itself. The
   whole company is frozen: Hetzner's US and Singapore networks have their own AS numbers and are
   frozen like the European ones.
2. **Confirm by measurement** (`serve` + `url`): stops from Russia, downloads from abroad. Compare
   mobile and home internet.
3. **Right now: bring up UDP.** WireGuard or AmneziaWG on the same server usually keeps working; the
   freeze hits TCP. A stopgap, not a fix.
4. **Don't waste time** on a new IP from the same provider, another port, or another protocol over
   TCP. The new address is in the same frozen network; the port does not matter.
5. **Move to a network that passes.** Choose by measurement (`scan`, then `owner` for the
   candidate), not by price or reviews. Hourly billing lets you test a server for cents before
   moving.
6. **Keep a spare in another network.** A second server with a different network owner: the list
   changes, and a network that works today can be frozen tomorrow.
7. **Re-check** every week or two: `scan --quick` takes half a minute.

Short connections also pass, because the packet counter is per connection. But ~8 packets on
mobile is too small to build a reliable link on.

## How it was measured

Raw anonymized runs from November 2026: [`data/2026-11`](data/2026-11).

- Each point: one connection, 256 KB must arrive. Targets and our results are in
  [`targets.tsv`](targets.tsv): columns `home_ru` (wired home ISP) and `mobile_ru` (Beeline LTE),
  2026-11-05/06.
- Control: the same list downloads from the EU; points that failed there are excluded.
- The mechanics (packets, not bytes; per-connection counter; no RST) come from packet captures on a
  server in a frozen network.
- Limits: a provider's test files may sit in another subnet than its VPS. A network with a single
  failed point may just have a dead test server. Other operators and regions may differ.
