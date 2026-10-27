// Watch list bundled with the Worker (deployed config, not a home-dir file).
// Apex plus public subdomains evidenced in the dotfiles repo (ntfy,
// linkwarden). Add entries here as services go public; tunnel-only names
// stay out. A Worker has no stable self egress IP to auto-detect, so fleet
// box public IPs are listed explicitly when they should be watched.
export const WATCH_DOMAINS: string[] = [
  "phillias.cc",
  "ntfy.phillias.cc",
  "linkwarden.phillias.cc",
];

export const WATCH_IPS: string[] = [];
