# Raw runs, November 2026

Anonymized: no IP addresses (targets are identified by URL and network owner), no names of the
measuring ISPs except the mobile operator. Network owner (ASN) was looked up by the target's IP
through ipinfo.

| File | What | When (UTC) |
|---|---|---|
| `scan-eu-control.tsv` | all 452 points from a VPS in Latvia: the control; points that failed here are excluded from the analysis | 2026-11-05 12:54 |
| `scan-ru-home-wired.tsv` | all points from a wired home ISP in Russia | 2026-11-05 22:04 |
| `scan-ru-beeline-lte.tsv` | all points from Beeline LTE (phone hotspot) | 2026-11-06 11:17 |
| `quick-ru-home-wired.tsv` | `freeze-check.sh scan --quick`, first real run of the public tool | 2026-11-06 12:25 |
| `cdn-ru-home-wired.tsv`, `cdn-ru-beeline-lte.tsv` | `freeze-check.sh cdn`: Cloudflare and other CDN sites, 3 tries each | 2026-11-06 |

The three `scan-*` files come from the research version of the scanner: `FROZEN` there means any
partial download, including slow links cut by the 25 s limit. The public tool separates those as
`SLOW` (more than 64 KB arrived). For the freeze itself look at `bytes`: frozen points stop at
about 16 KB on wired and at 0 on mobile.
