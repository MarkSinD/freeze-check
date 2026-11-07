# I tested 435 hosting locations from inside Russia. Whole networks are frozen, and the hosting brand doesn't matter

If your server is on Hetzner, OVH, DigitalOcean, Vultr or M247, users in Russia probably can't use
it. They don't get an error. The page just loads forever and then times out. I measured 435 test
points in 211 hosting networks from a wired home connection and a mobile network in Russia. 87%
work fine. The ones that don't are frozen as whole networks, so a small host renting space in a
frozen data center goes down with it. There is a tool at the end that checks your own server in
30 seconds.

![Cover](docs/images/cover.png)

**TL;DR**

- Russia's DPI system (TSPU) lets about **8 packets** through on mobile and about **25 on wired**
  per TCP connection. After that nothing arrives, in either direction, and no RST is sent.
- 378 of 435 test points downloaded fine. The failures cluster into 14 networks frozen at every
  point (OVH, Hetzner, DigitalOcean, M247, HostPapa, Vultr, Scaleway and others), plus 3 more with
  a single failed point each.
- **The network owner is what counts.** RackNerd sits in HostPapa's network and is frozen with it,
  whatever its website says.
- Cloudflare, which Russian ISPs throttled in summer 2025, works again on both connections.
- UDP is not affected. WireGuard on the same frozen server keeps working.

## How I noticed

I ran a small VPN server on Hetzner for a group of people. WireGuard (AmneziaWG) on it was fast,
while Reality, a TCP-based protocol, on the same box never connected at all: the connection just
hung until it timed out. My first thought was that my IP had been blacklisted.

I put a 2 MB test file on the server and opened it from Russia with the VPN off. On mobile
(Beeline LTE) the download stopped at 9,984 bytes over HTTP and 4,096 over HTTPS. On wired home
internet it stopped at 33,304 and 24,576 bytes. Always at the same point. From the EU the same
2 MB arrived in 0.25 s, six times out of six. Then Hetzner's own speed-test files in Finland and
Germany stalled the same way, so my IP had nothing to do with it. When OVH, Vultr and Scaleway
did too, it was clear Hetzner wasn't special either.

## The mechanics: packets, not bytes

Since 9 June 2025 this has been described as "16 KB and then nothing"
([Cloudflare](https://blog.cloudflare.com/russian-internet-users-are-unable-to-access-the-open-internet/),
[heise](https://www.heise.de/en/news/The-16-Kbyte-trick-Russian-providers-block-foreign-content-again-10465087.html)).
I wanted to know what exactly is being counted, so I captured packet headers with `tcpdump` on a
server in a frozen network while a phone in Russia ran a few tests: one big download, many small
chunks over separate connections, the same chunks over one connection, and a stream of tiny
200-byte packets.

The tiny packets settled it. On wired home internet they stopped after 4.8 KB, while full-size
packets stopped after 33 KB. That is seven times fewer bytes, but about the same number of packets,
roughly 25. On mobile (Beeline and MTS) the limit is about 8 packets.

![Packets before the freeze](docs/images/packets.png)

| | Beeline LTE | MTS | Wired home |
|---|---|---|---|
| Packet size (MSS) | 1,260 B | 1,400 B | 1,460 B |
| Data packets before freeze | 8 | 8 | 25 |
| 30 chunks, new connection each | 30/30 | 28/30 | 30/30 |

- **The counter is packets, not bytes.** The well-known "16 KB" is just 25 full-size packets.
- **It is per connection.** Thirty short connections of 3 KB each all went through; over a single
  connection only the first two chunks did.
- **It freezes both ways and silently.** Over one connection, the phone's third request never
  reached the server. When the phone uploaded 1 MB over wired home internet, the server received
  zero bytes of the body. There is no RST, so applications wait for a timeout instead of failing
  fast.
- **On mobile, TLS doesn't even finish.** Eight packets are not enough for a handshake with a
  certificate chain, so HTTPS gets zero bytes of content. That's why my Reality never connected.

## The wide scan: 435 points, 211 networks

I collected public test files from hosting providers, mostly from the looking.house catalog, and
wrote a script that opens one connection per point and expects 256 KB. The whole list ran from the
EU first as a control; points that failed there were dropped. That left 435 points at 154
companies. I mapped each point's IP to the network owner (ASN): 211 networks.

From wired home internet in Russia, 378 points downloaded. 52 stalled, nearly all at the same
~16 KB, across different companies and continents. Random failures don't line up that neatly;
this is one mechanism. 5 more returned nothing. Mobile Beeline matched the wired result on 415 of
435 points; there the freeze shows up as zero bytes, because the limit hits before TLS completes.
On 17 hand-picked points, Beeline, MTS and wired home all agreed. The operator doesn't matter; it
is one nationwide policy.

![Frozen networks](docs/images/frozen-networks.png)

Three networks (GlobalTeleHost, PI Data Centers, UK Dedicated Servers) also failed, but each had
only one point in the list, which could just as well be a dead test server, so I count them as
uncertain.

Networks that passed at every point include Psychz, Shock Hosting, Free Range Cloud, HostHatch,
FlokiNET, AltusHost, Kuroit, Virtua, SpeedyPage, Time4VPS, Serverius, LiteServer and Google Cloud,
about 120 companies in total. I'm not recommending any of them; it is a fact as of the test date.

## The network owner decides, not the brand

At first some hosts looked inconsistent: BlueVPS passed at 9 of its 14 points. Grouping points by
network owner removed the noise completely. Many small hosts rent space in other companies' data
centers. BlueVPS in its own network passed 7 of 7; BlueVPS in OVH, Clouvider and Glesys networks
was frozen. Five different brands sit on OVH's network, and all five are frozen. RackNerd turned
out to be in HostPapa's network, which is frozen at all 7 points across six brands.

![Brand vs network](docs/images/brand-vs-network.png)

Location doesn't help either. Hetzner's US and Singapore networks have their own AS numbers
(AS213230, AS212317, AS215859) and are frozen like the European ones. OVH is frozen in France,
Canada and the US. It looks like whole companies go on the list, with all their networks.

## Why these networks?

Nobody has published the list, so I don't have a direct answer. But there is an overlap that's
hard to miss: the frozen networks are where a lot of VPN servers live. Hetzner and DigitalOcean
are cheap, billed hourly, and
[widely used by Russians for private VPN servers](https://ppc.land/russian-isps-throttle-cloudflare-traffic-to-16kb/).
M247 [sells servers for VPNs](https://www.m247global.com/vpn-servers) itself, and addresses in its
network [are identified](https://www.netify.ai/resources/platforms/m247) as CyberGhost, Hotspot
Shield and other commercial VPN endpoints. OVH, Vultr and Scaleway are in the same category.

What argues against it: plenty of other VPN-friendly hosts pass, HostHatch or FlokiNET for
example. So it looks less like "every host VPN people like" and more like "the biggest of them",
where a freeze hits the most servers at once. That's a guess, and better explanations are welcome.

## Why I think it's TSPU

I can't see the censor's equipment, so this is inference, but the signs line up.

- **It's not an IP block.** A blocked IP never connects or gets reset right away. Here the
  connection opens, the first packets pass, and only then does it go silent. That is equipment
  watching the traffic flow and counting packets.
- **It's not the server.** The same server serves the file instantly from the EU, and Hetzner's
  own test servers freeze from Russia exactly like mine.
- **It's identical at three different companies**: Beeline, MTS and a home ISP, down to the
  packet. Operators configure their networks themselves; they only match like this when the rule
  comes from above. That is how TSPU works: under Russia's "sovereign internet" law, in force since
  November 2019, this equipment sits at every operator and Roskomnadzor sets its filtering rules.
- **It matches earlier reports.** In June 2025
  [Cloudflare described](https://blog.cloudflare.com/russian-internet-users-are-unable-to-access-the-open-internet/)
  the same 16 KB limit, applied by Russian ISPs themselves, and named Rostelecom, MegaFon,
  Vimpelcom (Beeline), MTS and MGTS. My measurement adds the mechanics: what is counted, and on
  which networks.

## What changed since 2025

On 26 June 2025 Cloudflare wrote that since 9 June users in Russia could load only the first 16 KB
of any asset behind Cloudflare. I tested ordinary Cloudflare-served sites and CDNs (cloudflare.com,
cdnjs, unpkg, jsDelivr), three attempts each, from wired home internet and mobile Beeline. All 36
attempts succeeded. The list changes, and not only by growing. Hetzner, DigitalOcean and OVH,
which Cloudflare named as affected back then, are still frozen.

## Seen only on mobile Beeline

Two observations I can't explain yet. Hivelocity (US) stopped at the same 16 KB on Beeline but
passed on wired home. All five points in Ukrainian networks failed to connect on Beeline but worked
on wired home; that looks like a separate block of Ukrainian networks, unrelated to the hosting
freeze. Data from other operators would help.

## If your server is frozen

1. **Check who owns the network** (ipinfo or whois on the IP). If it's OVH, M247, HostPapa or
   Hetzner, the name on the hosting website doesn't matter.
2. **Confirm by measurement:** stops from Russia, downloads from abroad.
3. **Right now, bring up UDP.** WireGuard or AmneziaWG on the same server usually keeps working. A
   stopgap, not a fix.
4. **Don't bother** with a new IP from the same provider or another port. The new IP is in the same
   frozen network; the port doesn't matter.
5. **Move to a network that passes.** Pick it by measurement; price and reviews won't tell you.
   Hourly billing lets you test before moving.
6. **Keep a spare with a different network owner.** The list changes.

## Check it yourself

The script and target list are in this repository.
It needs only `bash` and `curl` and runs on Linux, macOS and Git Bash on Windows. Nothing is
uploaded and the results file contains no IP address. Download two files:

```bash
mkdir freeze-check && cd freeze-check
curl -fsSLO https://raw.githubusercontent.com/MarkSinD/freeze-check/main/freeze-check.sh
curl -fsSLO https://raw.githubusercontent.com/MarkSinD/freeze-check/main/targets.tsv
```

The script is about 300 lines; read it before running it, like any script from the internet. Then:

```bash
bash freeze-check.sh scan --quick --wait
```

`--wait` lets you start it and turn the VPN off afterwards; it waits for a Russian address. For your
own server, `owner` shows who owns its network and what we measured there, and `serve` on the
server plus `url` from Russia measures it directly. If you don't have anyone in Russia to run it,
the `owner` command alone tells you whether your provider's network was frozen in our test.

![freeze-check output](docs/images/tool-output.png)

**If you are in Russia,** please share your result through the
[GitHub form](https://github.com/MarkSinD/freeze-check/issues/new?template=freeze-check-result.yml):
operator, region, date and output, no IP. Two connections in one city are a start, not a map.

<details>
<summary><b>Methodology in detail</b></summary>

**Targets.** 452 public test files at 154 hosting companies: mostly looking.house points, plus 16
of my own (providers' speed-test servers, Cloudflare, Google Cloud Storage).

**Control.** The whole list ran first from a VPS in Latvia on 5 November, 12:54 UTC. Points that
failed there were dropped as dead. 435 remained.

**One point.** `curl` requests the first 256 KB (`Range` header) over a single connection. Limits:
8 s to open the connection including TLS, abort after 6 s without a byte, 25 s per point (40 s in
the public tool, so a slow mobile link isn't mistaken for a freeze). The certificate isn't checked
(`-k`): only delivery is measured. 16 points in parallel; the list takes 2-3 minutes.

**Verdict.** 256 KB or the whole file arrived: pass. Stopped between 1 byte and 64 KB: frozen. More
than 64 KB but too slow: slow, not a freeze. Nothing: empty.

**Network owner.** The ASN and its owner by each point's IP via ipinfo. A network counts as frozen
if none of its points passed.

**Runs from Russia.** Wired home internet over Wi-Fi: 5 November, 22:04-22:06 UTC. Beeline LTE via
a phone hotspot: 6 November, 11:17-11:20 UTC. Before each run the script checks the address is
Russian: I had to discard one early run because a VPN was on.

**Mechanics.** A temporary server in Hetzner's network with a plain HTTP page on ports 8080, 50000,
2053 and 80; `tcpdump` recorded packet headers only. Android phone, Chrome, VPN off. Tests: one
2 MB stream; 30 chunks of 3,000 bytes, each over a new connection; the same chunks over one
connection; 200-byte packets every 30 ms (with `TCP_NODELAY`); a 1 MB upload; other ports.
Networks: Beeline LTE, MTS, wired home. Phone addresses from the captures are not published.

**Raw data.** All runs, anonymized and without IP addresses:
[data/2026-11](https://github.com/MarkSinD/freeze-check/tree/main/data/2026-11).

</details>

## Limitations

- Measured on 5-6 November 2026 from wired home internet and Beeline LTE; MTS on 17 points.
- A provider's test files may sit in a different subnet from its VPS.
- "Zero bytes" on mobile can't tell "connection never opened" from "froze during the handshake".
- A network with a single failed point may just have a dead test server.
- AWS and Azure are in the list for the next run; Oracle, Contabo and Linode had no working public
  test files.
- The list changes. I'll repeat the scan in a week and update the numbers.
