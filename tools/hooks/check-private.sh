#!/bin/sh
# Refuses commits/pushes that contain machine- or company-specific identifiers.
# The terms themselves are never in source control; they come from two ignored files:
#   Solitaire.local.props            bundle id, device UDID, signing ids (read automatically)
#   tools/private-terms.local.txt    any other term, one per line (# starts a comment)
# Usage: check-private.sh --cached     scan what is staged
#        check-private.sh <commit>     scan that commit's files
root=$(git rev-parse --show-toplevel) || exit 1
pat=$(mktemp) || exit 1
trap 'rm -f "$pat"' EXIT

if [ -f "$root/tools/private-terms.local.txt" ]; then
  tr -d '\r' < "$root/tools/private-terms.local.txt" | sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' >> "$pat"
fi
if [ -f "$root/Solitaire.local.props" ]; then
  tr -d '\r' < "$root/Solitaire.local.props" |
    sed -n 's/.*<\(AppBundleId\|TestDeviceId\|PF_DevAdHoc\|PF_DevTeamIdAdHoc\|PF_MobileProvisionAdHoc\)>\([^<][^<]*\)<.*/\2/p' >> "$pat"
fi
if [ ! -s "$pat" ]; then
  echo "check-private: no private terms configured, nothing checked" >&2
  exit 0
fi

if hits=$(git -C "$root" grep -n -I -i -F -f "$pat" "$@" 2>/dev/null); then
  echo "check-private: private identifiers found, refusing:" >&2
  echo "$hits" | cut -c1-200 >&2
  echo "Move them to Solitaire.local.props (or another ignored file) and try again." >&2
  exit 1
fi
exit 0
