#!/bin/sh
# Ensure the default key profile symlink the zshenv loader expects.
# ~/.zshenv reads ~/.agents/keys/default to export CF_AI_GATEWAY_TOKEN and
# the other key-profile vars; profile restructures (e.g. the masculinecache
# split) have orphaned this symlink before, so re-create it idempotently on
# every apply. The profile name matches the fleet-uniform keys layout.
[ -e "$HOME/.agents/keys/default" ] || ln -s phillias "$HOME/.agents/keys/default"