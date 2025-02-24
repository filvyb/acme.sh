#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_ddosguard_info='DDOS-Guard
Site: https://ddos-guard.net
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_ddosguard
Options:
 DG_API_KEY API Key
 DG_CLIENT_ID Client ID
Author: Filip Vybihal, @filvyb
'

DG_Api="https://webapi.ddos-guard.net"

########  Public functions #####################

# Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ddosguard_add() {
  fulldomain=$1
  txtvalue=$2

  DG_API_KEY="${DG_API_KEY:-$(_readaccountconf_mutable DG_API_KEY)}"
  DG_CLIENT_ID="${DG_CLIENT_ID:-$(_readaccountconf_mutable DG_CLIENT_ID)}"

  if [ -z "$DG_API_KEY" ] || [ -z "$DG_CLIENT_ID" ]; then
    DG_API_KEY=""
    DG_CLIENT_ID=""
    _err "You didn't specify a DDOS-Guard api key and client ID yet."
    _err "Please create your API key and client ID and try again."
    return 1
  fi

  # Save the credentials to the account conf file
  _saveaccountconf_mutable DG_API_KEY "$DG_API_KEY"
  _saveaccountconf_mutable DG_CLIENT_ID "$DG_CLIENT_ID"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Add TXT record
  _info "Adding record"

  # Prepare form data
  data="dns_id=$_domain_id&name=$fulldomain&type=TXT&content=$txtvalue&ttl=600"

  if _dg_rest "add-record" "$data"; then
    if _contains "$response" "\"id\""; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi

  _err "Add txt record error."
  return 1
}

# Usage: fulldomain txtvalue
dns_ddosguard_rm() {
  fulldomain=$1
  txtvalue=$2

  DG_API_KEY="${DG_API_KEY:-$(_readaccountconf_mutable DG_API_KEY)}"
  DG_CLIENT_ID="${DG_CLIENT_ID:-$(_readaccountconf_mutable DG_CLIENT_ID)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Get list of records
  if ! _dg_rest "list-records" "dns_id=$_domain_id"; then
    _err "Error getting records"
    return 1
  fi

  if ! _contains "$response" "\"id\""; then
    _info "No records found"
    return 0
  fi

  # Find record ID for our TXT record
  record_id=$(echo "$response" | tr -d '\n' | _egrep_o "\{[^\{]*\"name\":\"$fulldomain\"[^\}]*\"content\":\"$txtvalue\"[^\}]*\}" | _egrep_o "\"id\":[^,}]*" | cut -d: -f2)

  if [ -z "$record_id" ]; then
    _info "Record not found"
    return 0
  fi

  _debug "Record ID to remove: $record_id"

  # Delete the record
  if _dg_rest "delete-record" "record_id=$record_id"; then
    if _contains "$response" "\[\]"; then
      _info "Removed successfully"
      return 0
    fi
  fi

  _err "Delete record error"
  return 1
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=1
  p=1

  # First, get all available DNS zones for the client
  if ! _dg_rest "list-dns" ""; then
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # Not valid
      return 1
    fi

    # Look for the domain in the list of available DNS zones
    if _contains "$response" "\"domain\":\"$h\""; then
      _domain_id=$(echo "$response" | _egrep_o "\{[^\{]*\"domain\":\"$h\"[^\}]*\}" | _egrep_o "\"id\":[^,}]*" | cut -d: -f2)
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

# Make API requests to DDOS-Guard
_dg_rest() {
  action=$1
  data="$2"
  _debug action "$action"
  _debug data "$data"

  # Build API URL with auth params
  api_url="$DG_Api/api-dns?action=$action&api_key=$DG_API_KEY&client_id=$DG_CLIENT_ID"
  _debug api_url "$api_url"

  # Set content type header for form data
  export _H1="Content-Type: application/x-www-form-urlencoded"

  # Make the request
  response="$(_post "$data" "$api_url" "" "POST")"

  if [ "$?" != "0" ]; then
    _err "API request failed: $action"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
