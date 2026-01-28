#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CONFIG_DIR="$ROOT_DIR/mcp"
CONFIG_FILE="$CONFIG_DIR/local_servers.json"
REMOTE_CONFIG_FILE="$CONFIG_DIR/remote_servers.json"

mkdir -p "$CONFIG_DIR"

ensure_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"servers":{}}' > "$CONFIG_FILE"
  fi
}

ensure_remote_config() {
  if [ ! -f "$REMOTE_CONFIG_FILE" ]; then
    echo '{"servers":{}}' > "$REMOTE_CONFIG_FILE"
  fi
}

prompt() { # $1=label, returns input
  local label="$1" val
  printf "%s: " "$label" >/dev/tty
  read -r val </dev/tty 2>/dev/null || read -r val || val=""
  echo "$val" | tr -d '\r' | awk '{$1=$1; print}'
}

add_local_stdio() {
  echo "Adding a local stdio MCP server"
  name=$(prompt "Server name (e.g., brave-search)")
  [ -z "$name" ] && { echo "Name is required"; exit 1; }
  transport=$(prompt "Transport [stdio|http] (default: stdio)")
  [ -z "$transport" ] && transport="stdio"
  if [ "$transport" = "stdio" ]; then
    cmd=$(prompt "Command (default: node)")
    [ -z "$cmd" ] && cmd="node"
    args=$(prompt "Args (space-separated, default: dist/index.js)")
    [ -z "$args" ] && args="dist/index.js"
  else
    url=$(prompt "HTTP URL (e.g., http://localhost:8080 or https://api.example.com/mcp)")
    [ -z "$url" ] && { echo "URL is required for http transport"; exit 1; }
  fi
  echo "Enter environment variables to pass (KEY or KEY=${VALUE}), one per line. Blank line to finish:"
  env_lines=()
  while true; do
    read -r line || true
    [ -z "$line" ] && break
    env_lines+=("$line")
  done

  ensure_config
  tmp="$CONFIG_FILE.tmp"
  if [ "$transport" = "stdio" ]; then
    ruby -rjson -e '
      file=ARGV[0]; name=ARGV[1]; cmd=ARGV[2]; args=ARGV[3]; env_kv=ARGV[4..-1];
      cfg=JSON.parse(File.read(file)); cfg["servers"] ||= {};
      env_hash={}; env_kv.each{|l| k,v=l.split("=",2); env_hash[k]= (v||"${#{k}}") };
      cfg["servers"][name] = {
        "enabled"=>true,
        "transport"=>"stdio",
        "command"=>cmd,
        "args"=>args.split(/\s+/),
        "env"=>env_hash
      };
      File.write(file+".tmp", JSON.pretty_generate(cfg));
    ' "$CONFIG_FILE" "$name" "$cmd" "$args" "${env_lines[@]:-}" && mv "$tmp" "$CONFIG_FILE"
  else
    ruby -rjson -e '
      file=ARGV[0]; name=ARGV[1]; url=ARGV[2]; env_kv=ARGV[3..-1];
      cfg=JSON.parse(File.read(file)); cfg["servers"] ||= {};
      env_hash={}; env_kv.each{|l| k,v=l.split("=",2); env_hash[k]= (v||"${#{k}}") };
      cfg["servers"][name] = {
        "enabled"=>true,
        "transport"=>"http",
        "url"=>url,
        "env"=>env_hash
      };
      File.write(file+".tmp", JSON.pretty_generate(cfg));
    ' "$CONFIG_FILE" "$name" "$url" "${env_lines[@]:-}" && mv "$tmp" "$CONFIG_FILE"
  fi
  echo "✅ Added $name to $CONFIG_FILE"
}

import_from_json() {
  echo "Paste Claude-style JSON (press Enter twice when done):" >/dev/tty
  tmpjson=$(mktemp)
  empty_lines=0
  while IFS= read -r line </dev/tty 2>/dev/null || IFS= read -r line; do
    if [ -z "$line" ]; then
      empty_lines=$((empty_lines + 1))
      [ $empty_lines -ge 2 ] && break
    else
      empty_lines=0
      echo "$line" >> "$tmpjson"
    fi
  done

  # Parse JSON and extract first server block
  parsed=$(ruby -rjson -e '
    j=JSON.parse(STDIN.read);
    m=j["mcpServers"] || j["servers"] || {};
    name, cfg = m.first || [nil,nil];
    raise "No mcpServers found" unless name && cfg;
    out={
      name: name,
      command: (cfg["command"] || "node"),
      args: (cfg["args"] || []),
      env: (cfg["env"] || {})
    };
    puts JSON.dump(out)
  ' < "$tmpjson" 2>/dev/null) || { echo "Failed to parse JSON"; rm -f "$tmpjson"; exit 1; }
  rm -f "$tmpjson"

  name=$(echo "$parsed" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["name"]')
  command=$(echo "$parsed" | ruby -rjson -e 'puts JSON.parse(STDIN.read)["command"]')
  # Clean args: remove any --transport <val> to favor stdio default
  args_arr=$(echo "$parsed" | ruby -rjson -e '
    a=JSON.parse(STDIN.read)["args"] || [];
    cleaned=[]; skip=false;
    a.each_with_index do |v,i|
      if skip; skip=false; next; end
      if v=="--transport"
        skip=true; next
      end
      cleaned << v
    end
    puts JSON.dump(cleaned)
  ')
  # Extract env keys
  env_keys=$(echo "$parsed" | ruby -rjson -e 'puts (JSON.parse(STDIN.read)["env"]||{}).keys.join(" ")')

  # Prompt for env values when not already in ${VAR} form
  env_pairs=""
  for k in $env_keys; do
    # Fetch provided value
    val=$(echo "$parsed" | ruby -rjson -e "puts (JSON.parse(STDIN.read)['env']||{})['$k'] || ''")
    if echo "$val" | grep -Eq '^\$\{[A-Z0-9_]+\}$'; then
      env_pairs="$env_pairs $k=$val"
    else
      existing=$(grep -E "^$k=" "$ROOT_DIR/.env" 2>/dev/null || true)
      if [ -n "$existing" ]; then
        env_pairs="$env_pairs $k="'${'"$k"'}'
      else
        printf "Value for $k (will be written to .env): " >/dev/tty
        read -r v_in </dev/tty 2>/dev/null || read -r v_in || v_in=""
        echo "$k=$v_in" >> "$ROOT_DIR/.env"
        env_pairs="$env_pairs $k="'${'"$k"'}'
      fi
    fi
  done

  # Ask transport preference
  detected=$(echo "$parsed" | ruby -rjson -e '
    a=(JSON.parse(STDIN.read)["args"]||[]); idx=a.index("--transport");
    if idx && a[idx+1]; puts a[idx+1]; else puts ""; end
  ')
  default_t="stdio"; [ "$detected" = "http" ] && default_t="http"; [ "$detected" = "stdio" ] && default_t="stdio"
  tchoice=$(prompt "Import as [stdio|http]? (default: $default_t)")
  [ -z "$tchoice" ] && tchoice="$default_t"

  # Write into mcp_servers.json
  ensure_config
  tmp="$CONFIG_FILE.tmp"
  if [ "$tchoice" = "http" ]; then
    url=$(prompt "HTTP URL (e.g., http://localhost:8080 or https://api.example.com/mcp)")
    [ -z "$url" ] && { echo "URL is required for http"; exit 1; }
    ruby -rjson -e '
      file=ARGV[0]; name=ARGV[1]; url=ARGV[2]; env_pairs=ARGV[3..-1];
      cfg=JSON.parse(File.read(file)); cfg["servers"] ||= {};
      env_hash={}; env_pairs.each{|kv| k, v = kv.split("=",2); env_hash[k]=v };
      cfg["servers"][name] = {
        "enabled"=>true,
        "transport"=>"http",
        "url"=>url,
        "env"=>env_hash
      };
      File.write(file+".tmp", JSON.pretty_generate(cfg));
    ' "$CONFIG_FILE" "$name" "$url" $env_pairs && mv "$tmp" "$CONFIG_FILE"
  else
    ruby -rjson -e '
      file=ARGV[0]; name=ARGV[1]; cmd=ARGV[2]; args_json=ARGV[3];
      env_pairs=ARGV[4..-1];
      cfg=JSON.parse(File.read(file)); cfg["servers"] ||= {};
      env_hash={}; env_pairs.each{|kv| k, v = kv.split("=",2); env_hash[k]=v };
      cfg["servers"][name] = {
        "enabled"=>true,
        "transport"=>"stdio",
        "command"=>cmd,
        "args"=>JSON.parse(args_json),
        "env"=>env_hash
      };
      File.write(file+".tmp", JSON.pretty_generate(cfg));
    ' "$CONFIG_FILE" "$name" "$command" "$args_arr" $env_pairs && mv "$tmp" "$CONFIG_FILE"
  fi
  echo "✅ Imported $name to $CONFIG_FILE"
}

add_remote_server() {
  echo "Add a remote MCP server (HTTP transport only)"
  echo ""

  # URL is required
  url=$(prompt "Server URL (e.g., https://mcp.notion.com/mcp)")
  [ -z "$url" ] && { echo "URL is required"; exit 1; }

  # Auto-derive key from URL
  derived=$(ruby -ruri -e '
    url = ARGV[0]
    uri = URI.parse(url)
    host = uri.host || ""

    # Extract service name from domain (e.g., mcp.notion.com -> notion)
    parts = host.split(".")
    if parts[0] == "mcp" && parts.length >= 2
      service = parts[1]
    elsif parts.length >= 2
      service = parts[-2]
    else
      service = parts[0]
    end

    # Generate default display name
    display_name = service.split("-").map(&:capitalize).join(" ")

    puts "#{service}|#{display_name}"
  ' "$url" 2>/dev/null) || derived="remote|Remote MCP"

  key=$(echo "$derived" | cut -d'|' -f1)
  default_name=$(echo "$derived" | cut -d'|' -f2)

  # Ask for display name with default
  name=$(prompt "Display name (default: $default_name)")
  [ -z "$name" ] && name="$default_name"

  # Ask for description with default
  default_desc="$name MCP server"
  desc=$(prompt "Description (default: $default_desc)")
  [ -z "$desc" ] && desc="$default_desc"

  # Ask for auth type with default
  # Note: oauth_consent uses MCP OAuth 2.1 spec with dynamic discovery
  auth_type=$(prompt "Auth type [oauth_consent|api_key] (default: oauth_consent)")
  [ -z "$auth_type" ] && auth_type="oauth_consent"

  # Write to remote_servers.json
  # Note: For oauth_consent, the authorize_url is discovered dynamically from
  # the server's .well-known/oauth-authorization-server endpoint
  ensure_remote_config
  tmp="$REMOTE_CONFIG_FILE.tmp"
  ruby -rjson -e '
    file = ARGV[0]
    key = ARGV[1]
    name = ARGV[2]
    desc = ARGV[3]
    url = ARGV[4]
    auth_type = ARGV[5]

    cfg = JSON.parse(File.read(file))
    cfg["servers"] ||= {}
    server = {
      "enabled" => true,
      "name" => name,
      "description" => desc,
      "url" => url,
      "auth_type" => auth_type
    }
    cfg["servers"][key] = server
    File.write(file + ".tmp", JSON.pretty_generate(cfg))
  ' "$REMOTE_CONFIG_FILE" "$key" "$name" "$desc" "$url" "$auth_type" && mv "$tmp" "$REMOTE_CONFIG_FILE"

  echo ""
  echo "✅ Added $name to $REMOTE_CONFIG_FILE"
  echo "   URL: $url"
  echo "   Auth: $auth_type"
  echo ""
  echo "Restart services for changes to take effect: make restart"
}

main() {
  echo "Add MCP Server"
  echo "1) Import from JSON config block (Claude Desktop style)"
  echo "2) Create new local MCP server"
  echo "3) Add remote MCP server to defaults"
  # Allow non-interactive selection via CHOICE env var
  if [ -n "${CHOICE:-}" ]; then
    sel="$CHOICE"
  else
    printf "Select [1-3]: " >/dev/tty
    read -r sel </dev/tty 2>/dev/null || read -r sel || sel=""
  fi
  # Normalize selection to leading digits only
  sel=$(echo "$sel" | tr -d '\r' | sed -E 's/^[[:space:]]*([0-9]+).*/\1/')
  case "$sel" in
    1)
      import_from_json
      ;;
    2)
      add_local_stdio
      ;;
    3)
      add_remote_server
      ;;
    *)
      echo "Unknown choice";;
  esac
}

main "$@"
