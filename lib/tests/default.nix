let
  render = import ../render-text.nix;
  execArgs = import ../systemd-args.nix;
  template = ./fixtures/template.txt;
in
{
  rendering = {
    testReplacesRepeatedTokens = {
      expr = render template {
        name = "value";
        keep = "other";
      };
      expected = "value|other|value\n";
    };
    testNullPreservesMarker = {
      expr = render template {
        name = "value";
        keep = null;
      };
      expected = "value|@keep@|value\n";
    };
    testConvertsNumbers = {
      expr = render template {
        name = 42;
        keep = "";
      };
      expected = "42||42\n";
    };
    testConvertsPaths = {
      expr = render template {
        name = template;
        keep = null;
      };
      expected = "${template}|@keep@|${template}\n";
    };
    testRejectsInvalidNames = {
      expr = render template { "invalid-name" = "value"; };
      expectedError.type = "ThrownError";
      expectedError.msg = "renderText: invalid placeholder name";
    };
    testRejectsMissingValues = {
      expr = render template { name = "value"; };
      expectedError.type = "ThrownError";
      expectedError.msg = "renderText: missing replacements.*keep";
    };
    testRejectsUnusedValues = {
      expr = render template {
        name = "value";
        keep = null;
        extra = "unused";
      };
      expectedError.type = "ThrownError";
      expectedError.msg = "renderText: unused replacements.*extra";
    };
  };
  systemdArguments = {
    testEmptyList = {
      expr = execArgs [ ];
      expected = "";
    };
    testEmptyArgument = {
      expr = execArgs [ "" ];
      expected = "\"\"";
    };
    testSpaces = {
      expr = execArgs [
        "one two"
        "three"
      ];
      expected = "\"one two\" \"three\"";
    };
    testExpansionCharacters = {
      expr = execArgs [
        "$HOME"
        "%n"
      ];
      expected = "\"$$HOME\" \"%%n\"";
    };
    testQuotesAndBackslashes = {
      expr = execArgs [
        "a\"b"
        "c\\d"
      ];
      expected = "\"a\\\"b\" \"c\\\\d\"";
    };
  };
}
