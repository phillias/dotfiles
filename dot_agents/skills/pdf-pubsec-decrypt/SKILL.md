---
name: pdf-pubsec-decrypt
description: Decrypt Adobe.PubSec certificate-encrypted (public-key) PDFs — the kind Foxit produces that PyMuPDF, pypdf, pikepdf, mutool, and qpdf all refuse to open. Use when a PDF fails to open with "unknown encryption handler: Adobe.PubSec", "unsupported encryption filter", or "only Standard PDF encryption handler is available", when the captain mentions certificate-encrypted PDFs, dad's encrypted PDFs/writings, or asks to unencrypt PDFs from Google Drive using the PDFs certificate. Handles AESV2 with a .p12/.pfx certificate + passphrase; validated end-to-end on the Foxit/ScanSnap-encrypted Dads-Writings set.
---

# pdf-pubsec-decrypt — certificate-encrypted PDF decryption

No mainstream tool decrypts these files. This skill ships a self-contained,
validated Python implementation (`decrypt_pubsec.py` in this directory) that
works end-to-end: stdlib + `cryptography` only.

## When this applies

- `/Encrypt` dict has `/Filter /Adobe.PubSec` (public-key/certificate encryption).
- `mutool clean` says `unknown encryption handler: 'Adobe.PubSec'`; pypdf says
  `only Standard PDF encryption handler is available`; pikepdf says
  `unsupported encryption filter`; PyMuPDF fails to open the file at all.
- Typical provenance: Foxit Reader certificate encryption (a Foxit quirk writes
  `/R 131102` — a date, not a revision; the algorithm is standard ISO 32000-1
  Algorithm 3.2a) over ScanSnap scans.

## The certificate

- Lives in Bitwarden vault entry **"PDFs certificate and password "** (note the
  trailing space in the entry name): `my.p12` attachment + the p12 passphrase
  in the entry's password field.
- Retrieve with `bw get attachment my.p12 --itemid <id>` after unlocking the
  vault (captain supplies `BW_SESSION`, or unlock interactively when the
  captain is present).
- Never record the passphrase or key material in notes, skills, or git.
- The recipient certificate (CN=Darren, phillias@gmail.com, serial
  9258326264C683C2) is the matching identity; any future re-encryption of the
  same PDFs targets the same recipient unless the captain says otherwise.

## Usage

```sh
python3 decrypt_pubsec.py <indir> <outdir> <key.pem|cert.p12> [passphrase]
# passphrase also readable from PDF_CERT_PASSPHRASE
```

Accepts the .p12 bundle directly (preferred), or a PEM private key extracted
with `openssl pkcs12 -in my.p12 -nocerts -nodes -out private.key`.
Processes every PDF in `<indir>`; files without `/Adobe.PubSec` are copied
through unchanged, so it is safe to point at a mixed directory.

## Workflow (proven)

1. Download the PDFs (Google Drive: `gws-axi drive download` when its OAuth is
   fresh, otherwise the `composio` skill's proxy pattern).
2. Run the script per the usage above.
3. Validate: `mutool info <out.pdf>` opens cleanly; `mutool draw -o page.png
   <out.pdf> 1` renders a page; page count matches expectations. Decrypted
   Info strings should show real metadata (ScanSnap/Adobe producer strings),
   not mojibake — a strong signal the string decryption worked too.
4. Expected follow-ons: render at 300 DPI (`mutool draw -r 300`) and OCR
   handwriting with gemini-2.5-flash (established pattern; free tier ~20 RPM,
   guard for blank pages returning empty `parts` and MAX_TOKENS loops).

## Algorithm reference (why this works)

Per file: parse `/Recipients[0]` DER from the literal PDF string (PDF escapes
must be decoded first or the DER corrupts); RSA-PKCS1v15-decrypt the 128-byte
encrypted key; RC4-decrypt the envelope content to a 20-byte seed; file key =
`SHA1(seed20 || all_recipient_DER_bytes)[:16]`; per-object key =
`MD5(mkey || objnum_le3 || gennum_le2 || b"sAlT")[:16]` (the `sAlT` suffix is
required for AESV2); AES-128-CBC with the first 16 bytes as IV, strip PKCS#7.
Streams whose length is not 16-byte aligned are left untouched (they were
never encrypted — e.g. attachments). Each PDF has its own randomized envelope,
so the seed is re-derived per file with the same private key.

Full derivation history is in axi-memory
(`decrypt Adobe.PubSec certificate-encrypted PDFs`).
