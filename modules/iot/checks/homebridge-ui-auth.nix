{
  pkgs,
  nodePackage ? pkgs.nodejs,
}:
pkgs.runCommand "homebridge-ui-auth-compatibility"
  {
    nativeBuildInputs = [
      nodePackage
      pkgs.python3
    ];
  }
  ''
    node ${pkgs.homelab-iot-scripts}/check-homebridge-ui-auth.mjs \
      ${../scripts/homebridge_ui_auth.py} \
      ${pkgs.homebridge-config-ui-x}/lib/node_modules/homebridge-config-ui-x/dist/core/auth/auth.service.js
    touch "$out"
  ''
