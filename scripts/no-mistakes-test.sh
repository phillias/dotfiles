#!/usr/bin/env bash
# Bounded no-mistakes Test contract for the dotfiles repo.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
cd "$repo"

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-no-mistakes.XXXXXXXXXX")
cleanup() {
  case "${tmp_root:-}" in
    /tmp/dotfiles-no-mistakes.*|/var/tmp/dotfiles-no-mistakes.*)
      rm -rf -- "$tmp_root"
      ;;
  esac
}
trap cleanup EXIT

dest="$tmp_root/home"
cache="$tmp_root/cache"
state="$tmp_root/state.boltdb"
config="$tmp_root/chezmoi.toml"
identity="$tmp_root/age-identity.txt"
recipient_file="$tmp_root/age-recipient.txt"
mkdir -p "$dest" "$cache"

echo "== no-mistakes dotfiles scope"
echo "worktree: $repo"
echo "scratch: $tmp_root"

echo "== throwaway age round-trip"
chezmoi age-keygen --output "$identity"
chezmoi age-keygen --convert "$identity" >"$recipient_file"
recipient=$(head -n 1 "$recipient_file")
if [ -z "$recipient" ]; then
  echo "FAIL: could not derive throwaway age recipient" >&2
  exit 1
fi
chmod 600 "$identity"
cat >"$config" <<CONFIG
encryption = "age"
[age]
    identity = "$identity"
    recipient = "$recipient"
CONFIG

printf 'synthetic no-mistakes fixture\n' >"$tmp_root/plain.txt"
age --encrypt --recipient "$recipient" --output "$tmp_root/plain.txt.age" "$tmp_root/plain.txt"
age --decrypt --identity "$identity" --output "$tmp_root/roundtrip.txt" "$tmp_root/plain.txt.age"
cmp "$tmp_root/plain.txt" "$tmp_root/roundtrip.txt" >/dev/null
echo "age: synthetic fixture round-trip passed"

base_ref="${NO_MISTAKES_BASE_REF:-origin/master}"
if ! git rev-parse --verify -q "$base_ref^{commit}" >/dev/null; then
  base_ref="master"
fi

changed_filelist="$tmp_root/changed-files"
if git rev-parse --verify -q "$base_ref^{commit}" >/dev/null; then
  merge_base=$(git merge-base "$base_ref" HEAD)
  {
    git diff --name-only -z --diff-filter=ACMR "$merge_base...HEAD"
    git diff --name-only -z --diff-filter=ACMR
    git diff --cached --name-only -z --diff-filter=ACMR
    git ls-files --others --exclude-standard -z
  } | sort -zu >"$changed_filelist"
else
  git ls-files -z >"$changed_filelist"
fi

changed=()
while IFS= read -r -d '' path; do
  [ -f "$path" ] || continue
  changed+=("$path")
done <"$changed_filelist"

echo "changed files: ${#changed[@]}"
if [ "${#changed[@]}" -eq 0 ]; then
  echo "no changed files; deterministic dotfiles checks complete"
  exit 0
fi

managed_filelist="$tmp_root/managed-source-files"
chezmoi --source "$repo" \
  --destination "$dest" \
  --config "$config" \
  --persistent-state "$state" \
  --cache "$cache" \
  --no-tty \
  managed --path-style source-relative >"$managed_filelist"

is_managed_source() {
  grep -F -x -q -- "$1" "$managed_filelist"
}

is_encrypted_source() {
  case "$1" in
    *encrypted_*.age|*.age) return 0 ;;
    *) return 1 ;;
  esac
}

is_systemd_unit() {
  case "$1" in
    *.service|*.timer|*.socket|*.target|*.service.tmpl|*.timer.tmpl|*.socket.tmpl|*.target.tmpl)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

rendered_units=()
apply_targets=()
fail=0

echo "== render changed templates"
for path in "${changed[@]}"; do
  case "$path" in
    *.tmpl)
      render_out="$tmp_root/rendered/${path%.tmpl}"
      mkdir -p "$(dirname "$render_out")"
      if ! chezmoi --source "$repo" \
        --destination "$dest" \
        --config "$config" \
        --persistent-state "$state" \
        --cache "$cache" \
        --no-tty \
        execute-template --file "$path" >"$render_out"; then
        echo "FAIL: template render failed: $path"
        fail=1
        continue
      fi
      if is_systemd_unit "$path"; then
        rendered_units+=("$render_out")
      fi
      ;;
  esac
done

echo "== apply changed managed plain files to throwaway destination"
for path in "${changed[@]}"; do
  if ! is_managed_source "$path"; then
    continue
  fi
  if is_encrypted_source "$path"; then
    if ! head -n 1 "$path" | grep -q '^-----BEGIN AGE ENCRYPTED FILE-----$'; then
      echo "FAIL: encrypted source lacks age armor header: $path"
      fail=1
    fi
    continue
  fi
  apply_targets+=("$path")
done

if [ "${#apply_targets[@]}" -gt 0 ]; then
  chezmoi --source "$repo" \
    --destination "$dest" \
    --config "$config" \
    --persistent-state "$state" \
    --cache "$cache" \
    --no-tty \
    --parent-dirs \
    --source-path apply "${apply_targets[@]}"
  if ! chezmoi --source "$repo" \
    --destination "$dest" \
    --config "$config" \
    --persistent-state "$state" \
    --cache "$cache" \
    --no-tty \
    --source-path diff "${apply_targets[@]}" >"$tmp_root/chezmoi.diff"; then
    echo "FAIL: chezmoi diff failed for changed managed files"
    fail=1
  elif [ -s "$tmp_root/chezmoi.diff" ]; then
    echo "FAIL: changed managed files are not idempotent after temp apply"
    sed -n '1,120p' "$tmp_root/chezmoi.diff"
    fail=1
  else
    echo "chezmoi: changed managed plain files apply idempotently"
  fi
else
  echo "chezmoi: no changed managed plain files to apply"
fi

echo "== verify changed systemd user units"
for path in "${changed[@]}"; do
  if is_systemd_unit "$path" && [[ "$path" != *.tmpl ]]; then
    rendered_units+=("$path")
  fi
done

if [ "${#rendered_units[@]}" -gt 0 ]; then
  for unit in "${rendered_units[@]}"; do
    if ! systemd-analyze verify --user "$unit"; then
      echo "FAIL: systemd-analyze verify failed: $unit"
      fail=1
    fi
  done
else
  echo "systemd: no changed user units"
fi

if [ "$fail" -eq 0 ]; then
  echo "no-mistakes dotfiles test: passed"
else
  echo "no-mistakes dotfiles test: FAILED"
fi
exit "$fail"
