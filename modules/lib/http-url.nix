# A host-facing URL must use a reachable address rather than a wildcard bind.
lib: host: port:
let
  reachable =
    if
      lib.elem host [
        ""
        "*"
        "0.0.0.0"
      ]
    then
      "127.0.0.1"
    else if host == "::" then
      "::1"
    else
      host;
  address =
    if lib.hasInfix ":" reachable && !lib.hasPrefix "[" reachable then "[${reachable}]" else reachable;
in
"http://${address}:${toString port}"
