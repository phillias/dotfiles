#!/usr/bin/env python3
"""Decrypt Adobe.PubSec (certificate-encrypted, AESV2) PDFs end-to-end.

Self-contained: stdlib + the `cryptography` package only. Handles the
Foxit-written variant (/R 131102 is a Foxit date-quirk, algorithm unchanged).

Key argument accepts either:
  - a PEM private key file (from `openssl pkcs12 -in my.p12 -nocerts -nodes`), or
  - the .p12 / .pfx certificate bundle directly (passphrase required).

Per file:
  1. Parse /Encrypt -> DefaultCryptFilter -> /Recipients[0] DER (PDF-unescape).
  2. Walk DER: RSA-PKCS1v15-decrypt 128B encryptedKey -> RC4 CEK;
     RC4-decrypt [0] content -> 20B seed + 4B permission.
  3. mkey = SHA1(seed20 || recipients_der)[:16]
  4. Per-object key = MD5(mkey || obj_le3 || gen_le2 || b"sAlT")[:16]
  5. AES-128-CBC decrypt every stream and string (IV = first 16 bytes).
  6. Rewrite objects, fresh xref, drop /Encrypt.

Usage:
  python3 decrypt_pubsec.py <indir> <outdir> <key.pem|cert.p12> [passphrase]

Passphrase may also be passed via PDF_CERT_PASSPHRASE. Files without
/Adobe.PubSec are copied through unchanged.

Validated end-to-end against 8 Foxit/ScanSnap PDFs (154 pages); outputs open
cleanly in mutool, pypdf, and PyMuPDF.
"""
import hashlib, re, sys, os
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import serialization, padding as pad
from cryptography.hazmat.primitives.asymmetric import padding as apad
from cryptography.hazmat.primitives.serialization import pkcs12

SALT = b"sAlT"

# ---------- key loading ----------

def load_private_key(keypath, passphrase=None):
    data = open(keypath, "rb").read()
    if data.strip().startswith(b"-----"):
        return serialization.load_pem_private_key(
            data, password=passphrase.encode() if passphrase else None)
    key, _cert, _chain = pkcs12.load_key_and_certificates(
        data, passphrase.encode() if passphrase else None)
    return key

# ---------- PDF string codec ----------

def pdf_unescape(raw: bytes) -> bytes:
    out = bytearray()
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if c != 0x5C:
            out.append(c); i += 1; continue
        i += 1
        if i >= n: break
        d = raw[i]
        if d in (0x0D, 0x0A):  # line continuation
            if d == 0x0D and i + 1 < n and raw[i+1] == 0x0A: i += 2
            else: i += 1
        elif d == 0x72: out.append(0x0D); i += 1
        elif d == 0x6E: out.append(0x0A); i += 1
        elif d == 0x74: out.append(0x09); i += 1
        elif d == 0x62: out.append(0x08); i += 1
        elif d == 0x66: out.append(0x0C); i += 1
        elif d in (0x28, 0x29, 0x5C): out.append(d); i += 1
        elif 0x30 <= d <= 0x37:
            j, val = i, 0
            while j < n and j < i + 3 and 0x30 <= raw[j] <= 0x37:
                val = val * 8 + (raw[j] - 0x30); j += 1
            out.append(val & 0xFF); i = j
        else:
            out.append(d); i += 1
    return bytes(out)


def pdf_escape(data: bytes) -> bytes:
    out = bytearray()
    for b in data:
        if b == 0x5C: out += b"\\\\"
        elif b == 0x28: out += b"\\("
        elif b == 0x29: out += b"\\)"
        elif b == 0x0D: out += b"\\r"
        elif b == 0x0A: out += b"\\n"
        elif b == 0x09: out += b"\\t"
        elif b == 0x08: out += b"\\b"
        elif b == 0x0C: out += b"\\f"
        elif 32 <= b <= 126: out.append(b)
        else: out += b"\\%03o" % b
    return bytes(out)


# ---------- DER walker ----------

def der_walk(buf, off=0):
    """Yield (tag, constructed, content_off, content_len, next_off) one level."""
    tag = buf[off]
    constructed = bool(tag & 0x20)
    i = off + 1
    l = buf[i]; i += 1
    if l & 0x80:
        nb = l & 0x7F
        l = int.from_bytes(buf[i:i+nb], "big"); i += nb
    yield tag, constructed, i, l, i + l


def der_children(buf, off, length):
    """Iterate children of a constructed element starting at off with total length."""
    i = off
    end = off + length
    while i < end:
        for tag, cons, c_off, c_len, n_off in der_walk(buf, i):
            yield tag, cons, c_off, c_len
            i = n_off


def extract_envelope(der: bytes):
    """Return (encrypted_key_128, encrypted_content_bytes)."""
    # ContentInfo SEQ
    for tag, cons, c_off, c_len in der_children(der, 0, len(der)):
        pass
    # top level: SEQ
    for tag, cons, c_off, c_len, _ in der_walk(der, 0):
        top_off, top_len = c_off, c_len
    children = list(der_children(der, top_off, top_len))
    # children[0] = OID envelopedData, children[1] = [0] constructed
    assert children[0][0] == 0x06
    ctag, ccons, cc_off, cc_len = children[1]
    assert ctag == 0xA0
    # EnvelopedData SEQ inside [0]
    for tag, cons, e_off, e_len in der_children(der, cc_off, cc_len):
        if tag == 0x30:
            ed_off, ed_len = e_off, e_len
            break
    ed_children = list(der_children(der, ed_off, ed_len))
    # ed: version INT, recipientInfos SET, encryptedContentInfo SEQ
    rec_set = ed_children[1]
    eci = ed_children[2]
    assert rec_set[0] == 0x31 and eci[0] == 0x30
    # recipient: ktri SEQ
    enc_key = None
    for tag, cons, r_off, r_len in der_children(der, rec_set[2], rec_set[3]):
        if tag == 0x30:
            # walk ktri: version INT, issuer SEQ, serial INT, alg SEQ, key OCTET
            for t2, c2, o2, l2 in der_children(der, r_off, r_len):
                if t2 == 0x04:  # OCTET STRING
                    enc_key = der[o2:o2+l2]
                    break
            if enc_key: break
    # encryptedContentInfo: contentType OID, alg SEQ, [0] primitive content
    enc_content = None
    for t2, c2, o2, l2 in der_children(der, eci[2], eci[3]):
        if t2 == 0x80:  # primitive [0]
            enc_content = der[o2:o2+l2]
    return enc_key, enc_content


def rc4(key: bytes, data: bytes) -> bytes:
    S = list(range(256)); j = 0
    for i in range(256):
        j = (j + S[i] + key[i % len(key)]) & 0xFF
        S[i], S[j] = S[j], S[i]
    out = bytearray(); i = j = 0
    for b in data:
        i = (i + 1) & 0xFF; j = (j + S[i]) & 0xFF
        S[i], S[j] = S[j], S[i]
        out.append(b ^ S[(S[i] + S[j]) & 0xFF])
    return bytes(out)


def seed_from_envelope(der, priv):
    enc_key, enc_content = extract_envelope(der)
    cek = priv.decrypt(enc_key, apad.PKCS1v15())
    content = rc4(cek, enc_content)
    assert len(content) == 24, f"unexpected content len {len(content)}"
    return content[:20]


# ---------- object scanning ----------

OBJ_RE = re.compile(rb"(\d+)\s+(\d+)\s+obj\b")
ENDOBJ_RE = re.compile(rb"endobj\b")
STREAM_RE = re.compile(rb"stream\r?\n")
LEN_RE = re.compile(rb"/Length\s+(\d+)\b")
LEN_IND_RE = re.compile(rb"/Length\s+(\d+)\s+(\d+)\s+R\b")


def find_strings(body: bytes):
    """Yield (start, end, raw_inner|None) for literal/hex strings.
    raw_inner=None marks a hex string. Correctly skips << and >> pairs."""
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if c == 0x28:  # literal string
            depth, j = 1, i + 1
            while j < n and depth > 0:
                d = body[j]
                if d == 0x5C: j += 2; continue
                if d == 0x28: depth += 1
                elif d == 0x29:
                    depth -= 1
                    if depth == 0:
                        yield (i, j + 1, body[i+1:j]); i = j + 1; break
                j += 1
            else:
                return
            continue
        if c == 0x3C:  # <
            if i + 1 < n and body[i+1] == 0x3C:  # dict open
                i += 2; continue
            j = body.find(b">", i + 1)
            if j == -1: return
            yield (i, j + 1, None); i = j + 1; continue
        if c == 0x3E and i + 1 < n and body[i+1] == 0x3E:  # dict close
            i += 2; continue
        i += 1


def aes_dec(key: bytes, data: bytes):
    if len(data) < 32 or (len(data) - 16) % 16 != 0:
        return None
    iv, ct = data[:16], data[16:]
    c = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    pt = c.update(ct) + c.finalize()
    if not pt: return None
    p = pt[-1]
    if 1 <= p <= 16 and pt[-p:] == bytes([p]) * p:
        pt = pt[:-p]
    return pt


class Dec:
    def __init__(self, mkey):
        self.mkey = mkey

    def okey(self, num, gen):
        h = hashlib.md5()
        h.update(self.mkey + num.to_bytes(3, "little") + gen.to_bytes(2, "little") + SALT)
        return h.digest()[:16]

    def stream(self, num, gen, data):
        return aes_dec(self.okey(num, gen), data)

    def string(self, num, gen, data):
        if len(data) < 32: return None
        return aes_dec(self.okey(num, gen), data)


def decrypt_file(inpath, outpath, priv, verbose=True):
    data = open(inpath, "rb").read()
    # --- locate Encrypt dict + recipients ---
    encrypt_obj = None; recipients = []
    for m in OBJ_RE.finditer(data):
        body_s = m.end()
        e = ENDOBJ_RE.search(data, body_s)
        if not e: continue
        seg = data[body_s:e.start()]
        if b"/Adobe.PubSec" in seg:
            encrypt_obj = (int(m.group(1)), int(m.group(2)))
            sm = STREAM_RE.search(seg)
            dictseg = seg[:sm.start()] if sm else seg
            rm = re.search(rb"/Recipients\s*\[", dictseg)
            arr_s = rm.end()
            # scan strings within the recipients array region
            region = dictseg[arr_s:]
            depth = 1
            for (s, en, raw) in find_strings(region):
                if raw is None:
                    hx = re.sub(rb"\s", b"", region[s+1:en-1])
                    if len(hx) % 2: hx += b"0"
                    try: recipients.append(bytes.fromhex(hx.decode()))
                    except ValueError: pass
                else:
                    recipients.append(pdf_unescape(raw))
            break
    if not recipients:
        raise RuntimeError("no recipients found")
    if verbose: print(f"  recipients: {[len(r) for r in recipients]}")
    seed = seed_from_envelope(recipients[0], priv)
    h = hashlib.sha1()
    h.update(seed)
    for r in recipients: h.update(r)
    mkey = h.digest()[:16]
    if verbose: print(f"  seed={seed.hex()} mkey={mkey.hex()}")

    dec = Dec(mkey)

    # --- parse objects ---
    objects = {}
    for m in OBJ_RE.finditer(data):
        num, gen = int(m.group(1)), int(m.group(2))
        e = ENDOBJ_RE.search(data, m.end())
        if not e: continue
        objects[(num, gen)] = (m.start(), m.end(), e.start())

    tm = re.search(rb"trailer\s*(<<.*?>>)", data, re.S)
    trailer_dict = tm.group(1) if tm else b""
    trailer_dict = re.sub(rb"/Encrypt\s+\d+\s+\d+\s+R\b", b"", trailer_dict)

    keep = {k: v for k, v in objects.items() if k != encrypt_obj}
    max_obj = max(num for (num, gen) in keep)

    out = bytearray()
    out += b"%PDF-1.5\n%\xe2\xe3\xcf\xd3\n"
    offsets = {}
    nstr = nstm = 0

    for (num, gen), (os_, bs, be) in sorted(keep.items(), key=lambda kv: kv[0][0]):
        offsets[num] = len(out)
        body = data[bs:be]
        sm = STREAM_RE.search(body)
        if sm:
            dict_part, sdata = body[:sm.start()], body[sm.end():]
            se = sdata.rfind(b"endstream")
            sdata = sdata[:se]
            while sdata and sdata[-1:] in (b"\n", b"\r"): sdata = sdata[:-1]
            lim = LEN_IND_RE.search(dict_part)
            if lim:
                lnum, lgen = int(lim.group(1)), int(lim.group(2))
                if (lnum, lgen) in objects:
                    lb = data[objects[(lnum, lgen)][1]:objects[(lnum, lgen)][2]]
                    lm = re.search(rb"(\d+)", lb)
                    ulen = int(lm.group(1))
                    sdata = sdata[:ulen]
                    dict_part = LEN_IND_RE.sub(b"/Length %d" % 0, dict_part, count=1)
            else:
                lm = LEN_RE.search(dict_part)
                if lm and abs(int(lm.group(1)) - len(sdata)) <= 4:
                    sdata = sdata[:int(lm.group(1))]
            pt = dec.stream(num, gen, sdata)
            if pt is None:
                if verbose: print(f"  obj {num}: stream len {len(sdata)} left as-is")
                new = sdata
            else:
                new = pt; nstm += 1
                dict_part = LEN_RE.sub(b"/Length %d" % len(new), dict_part, count=1)
            out += b"%d %d obj\n" % (num, gen) + dict_part
            if not dict_part.endswith(b"\n"): out += b"\n"
            out += b"stream\n" + new + b"\nendstream\nendobj\n"
        else:
            nb = bytearray(); last = 0
            for (s, e2, raw) in find_strings(body):
                nb += body[last:s]
                if raw is not None:
                    d = pdf_unescape(raw)
                    pt = dec.string(num, gen, d)
                    if pt is not None:
                        nb += b"(" + pdf_escape(pt) + b")"; nstr += 1
                    else:
                        nb += body[s:e2]
                else:
                    hx = re.sub(rb"\s", b"", body[s+1:e2-1])
                    if len(hx) % 2: hx += b"0"
                    try:
                        d = bytes.fromhex(hx.decode())
                        pt = dec.string(num, gen, d)
                        if pt is not None:
                            nb += b"(" + pdf_escape(pt) + b")"; nstr += 1
                        else:
                            nb += body[s:e2]
                    except ValueError:
                        nb += body[s:e2]
                last = e2
            nb += body[last:]
            out += b"%d %d obj\n" % (num, gen) + bytes(nb)
            if not nb.endswith(b"\n"): out += b"\n"
            out += b"endobj\n"

    xref_off = len(out)
    out += b"xref\n0 %d\n" % (max_obj + 1)
    out += b"0000000000 65535 f \n"
    for i in range(1, max_obj + 1):
        if i in offsets:
            out += b"%010d 00000 n \n" % offsets[i]
        else:
            out += b"0000000000 65535 f \n"
    out += b"trailer\n" + trailer_dict + b"\nstartxref\n%d\n%%%%EOF\n" % xref_off
    open(outpath, "wb").write(bytes(out))
    if verbose: print(f"  wrote {outpath}: {len(out)} bytes, {nstm} streams, {nstr} strings decrypted")


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__.strip().splitlines()[-1] and
                 "usage: decrypt_pubsec.py <indir> <outdir> <key.pem|cert.p12> [passphrase]")
    indir, outdir, keypath = sys.argv[1], sys.argv[2], sys.argv[3]
    passphrase = sys.argv[4] if len(sys.argv) > 4 else os.environ.get("PDF_CERT_PASSPHRASE")
    priv = load_private_key(keypath, passphrase)
    os.makedirs(outdir, exist_ok=True)
    for fn in sorted(os.listdir(indir)):
        if not fn.lower().endswith(".pdf"): continue
        src = os.path.join(indir, fn)
        body = open(src, "rb").read()
        if b"Adobe.PubSec" not in body:
            import shutil
            shutil.copy(src, os.path.join(outdir, fn))
            print(f"{fn}: not pubsec-encrypted, copied as-is")
            continue
        print(fn)
        try:
            decrypt_file(src, os.path.join(outdir, fn), priv)
        except Exception as ex:
            print(f"  FAILED: {ex}")


if __name__ == "__main__":
    main()
