#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
site_root="$repository_root/docs"
canonical_root="https://treafree.github.io/FileIsland/"
sitemap_path="$site_root/sitemap.xml"
robots_path="$site_root/robots.txt"

fail() {
  print -u2 -- "error: $1"
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing required site file: ${1#$repository_root/}"
}

require_file "$site_root/index.html"
require_file "$site_root/assets/guide.css"
require_file "$sitemap_path"
require_file "$robots_path"

if grep -R -n --exclude-dir=.git --exclude='*.mp4' 'treafree\.top' \
  "$repository_root/README.md" \
  "$repository_root/README.zh-CN.md" \
  "$site_root"; then
  fail "the retired treafree.top domain is still present in public site content"
fi

if grep -R -n \
  --exclude='*.mp4' \
  --exclude-dir=audits \
  --exclude-dir=specs \
  --exclude-dir=superpowers \
  -E '/Users/|file://|localhost|127\.0\.0\.1' \
  "$site_root"; then
  fail "site content contains a local-only URL or filesystem path"
fi

xmllint --noout "$sitemap_path" || fail "sitemap.xml is not valid XML"
grep -Fxq 'User-agent: *' "$robots_path" || fail "robots.txt is missing the wildcard user agent"
grep -Fxq 'Allow: /' "$robots_path" || fail "robots.txt does not allow crawling"
grep -Fxq "Sitemap: ${canonical_root}sitemap.xml" "$robots_path" || fail "robots.txt does not advertise the canonical sitemap"

typeset -a html_files
html_files=("${(@f)$(find "$site_root" \
  -type d \( -name audits -o -name specs -o -name superpowers \) -prune \
  -o -type f -name 'index.html' -print | LC_ALL=C sort)}")
(( ${#html_files[@]} > 0 )) || fail "no HTML pages found"

typeset -A seen_canonicals

for html_file in "${html_files[@]}"; do
  relative_path="${html_file#$site_root/}"
  if [[ "$relative_path" == "index.html" ]]; then
    expected_canonical="$canonical_root"
  else
    expected_canonical="${canonical_root}${relative_path%index.html}"
  fi

  title_count="$(grep -Ec '<title>[^<]+</title>' "$html_file" || true)"
  (( title_count == 1 )) || fail "$relative_path must contain exactly one non-empty title"

  for required_pattern in \
    '<meta name="description" content="[^"]+">' \
    '<meta name="robots" content="[^"]+">' \
    '<meta property="og:title" content="[^"]+">' \
    '<meta property="og:description" content="[^"]+">' \
    '<meta property="og:url" content="[^"]+">' \
    '<meta name="twitter:title" content="[^"]+">' \
    '<meta name="twitter:description" content="[^"]+">' \
    '<script type="application/ld\+json">'; do
    grep -Eq "$required_pattern" "$html_file" || fail "$relative_path is missing required SEO metadata: $required_pattern"
  done

  canonical="$(sed -n 's/.*<link rel="canonical" href="\([^"]*\)">.*/\1/p' "$html_file")"
  [[ "$canonical" == "$expected_canonical" ]] || fail "$relative_path canonical is '$canonical', expected '$expected_canonical'"
  [[ -z "${seen_canonicals[$canonical]-}" ]] || fail "duplicate canonical URL: $canonical"
  seen_canonicals[$canonical]="$relative_path"

  og_url="$(sed -n 's/.*<meta property="og:url" content="\([^"]*\)">.*/\1/p' "$html_file")"
  [[ "$og_url" == "$canonical" ]] || fail "$relative_path og:url does not match its canonical"

  grep -Fq "<loc>$canonical</loc>" "$sitemap_path" || fail "$relative_path canonical is missing from sitemap.xml"

  json_ld="$(sed -n '/<script type="application\/ld+json">/,/<\/script>/p' "$html_file" | sed '1d;$d')"
  [[ -n "$json_ld" ]] || fail "$relative_path has empty JSON-LD"
  print -r -- "$json_ld" | plutil -convert json -o /dev/null -- - || fail "$relative_path contains invalid JSON-LD"

  while IFS= read -r attribute; do
    target="${attribute#*\"}"
    target="${target%\"}"
    [[ -z "$target" || "$target" == \#* || "$target" == http://* || "$target" == https://* || "$target" == mailto:* || "$target" == data:* || "$target" == javascript:* ]] && continue
    target="${target%%\#*}"
    target="${target%%\?*}"
    [[ -z "$target" ]] && continue
    resolved="${html_file:h}/$target"
    if [[ "$target" == */ ]]; then
      resolved="${resolved}index.html"
    elif [[ -d "$resolved" ]]; then
      resolved="$resolved/index.html"
    fi
    [[ -e "$resolved" ]] || fail "$relative_path references missing local target: $target"
  done < <(grep -Eo '(href|src)="[^"]+"' "$html_file" || true)
done

typeset -a sitemap_urls
sitemap_urls=("${(@f)$(sed -n 's:.*<loc>\(.*\)</loc>.*:\1:p' "$sitemap_path")}")
(( ${#sitemap_urls[@]} == ${#html_files[@]} )) || fail "sitemap URL count (${#sitemap_urls[@]}) does not match indexable HTML page count (${#html_files[@]})"

grep -Fq '"softwareVersion": "0.3.3"' "$site_root/index.html" || fail "homepage structured data does not match release 0.3.3"
grep -Eq '<meta name="google-site-verification" content="[^"]+">' "$site_root/index.html" || fail "homepage is missing the persistent Google Search Console verification tag"

print -- "Site validation passed: ${#html_files[@]} pages, ${#sitemap_urls[@]} sitemap URLs."
