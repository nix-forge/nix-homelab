lib: path:
lib.hasPrefix "/" path
&& path != "/"
&& !lib.hasPrefix "/nix/store" path
&& !lib.hasInfix "/../" "${path}/"
&& !lib.hasInfix "/./" "${path}/"
&& !lib.hasInfix "//" path
&& !lib.hasInfix ":" path
&& !lib.hasInfix "\n" path
&& !lib.hasInfix "\r" path
